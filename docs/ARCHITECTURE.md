# Architecture

BabelRobot is a SwiftUI macOS app built on Apple's MLX for local LLM inference.
It is organized into a small set of engines, each owning one responsibility and
communicating through closures and SwiftUI's observation rather than hard
references. This keeps the local inference path isolated and the robot
personality decoupled from the model code.

## Source layout

```
BabelRobot/
├── App/            App entry point and entitlements
├── Features/       User-facing features (main window, voice, desktop companion)
├── Robot/          Robot face: state machine, views, animator, behavior/emotion
├── Models/         Local LLM engine: manager, registry, config, benchmark
├── Services/       Voice (speech in/out), cursor tracking, system metrics
├── Infrastructure/ Theme, palette, memory monitor
└── Resources/      Asset catalog
docs/               This documentation
```

## High-level flow

```
            ┌──────────────┐     observation      ┌──────────────────────┐
            │  Robot Engine │ ◀──────────────────  │  RobotAssistantVM     │
            │  (face FSM)   │                       │  (UI ↔ model bridge)  │
            └──────┬───────┘                        └─────────┬────────────┘
                   │ fused face state                         │
                   ▼                                          ▼
        ┌────────────────────┐                     ┌────────────────────┐
        │ Desktop Companion   │                     │  Model Engine      │
        │ (floating NSPanel)  │                     │  (LocalLLMManager) │
        └────────────────────┘                     └─────────┬──────────┘
                   ▲                                          │ MLX
                   │ voice/emotion overrides                  ▼
        ┌────────────────────┐                     ┌────────────────────┐
        │   Voice Engine      │ ── prompt ───────▶  │   MLX inference    │
        │ (speech in/out)     │ ◀── tokens ───────  │   (on-device)      │
        └────────────────────┘                     └────────────────────┘
```

---

## Robot state machine

The face is driven by `RobotFaceState`, an enum of mutually exclusive states.
`RobotFaceAnimator` runs lightweight, cancellable SwiftUI animations for each
state (blink, gaze, breathing, loading spin, fade) and respects Reduce Motion.

States:

- `idle` — neutral; blinks every 3–5 s with subtle eye movement
- `listening` — attentive eyes, small open mouth
- `thinking` — eyes scan side to side, animated ellipsis
- `speaking` — sound-wave "tuner" mouth driven by real-time TTS loudness
- `happy` / `love` — smiling eyes; `love` shows cheek blush
- `warning` / `error` / `confused` — escalating concern, recolored face
- `sleeping` — closed eyes, relaxed mouth
- `loadingModel` / `unloadingModel` — spinner while the model lifecycle runs
- `lookingAtCursor` — companion gaze that tracks the pointer

### State fusion (desktop companion)

The floating companion displays a single fused state, resolved by priority in
`DesktopCompanionManager.refresh()`:

```
voiceState (Voice Engine)  ▸  emotion (AI events)  ▸  behavior (idle/sleep/cursor)
```

- **Voice** wins while a turn is active (listening / transcribing / speaking).
- **Emotion** (`RobotEmotionEngine`) maps assistant events to short-lived moods:
  thinking/speaking are sticky, happy is ~2 s, confused ~3 s.
- **Behavior** (`RobotBehaviorEngine`) is the baseline: watch the cursor, drift
  to sleep after ~5 minutes idle, wake on interaction.

The companion runs the whole feature on a **single timer**
(`CursorTrackingService`): one tick drives gaze, proximity-wake, and the sleep
check. When the companion is hidden, the timer and all animations stop, so idle
CPU stays near zero.

### Mood colors

`RobotFaceMood` recolors the eyes/mouth by state and by thermal state, so the
face doubles as a temperature indicator: red = anger/error, orange = warning or
hot CPU, pink = blush, yellow = confused, cyan = thinking/loading, green =
happy, white = resting. Thermal `serious` forces orange and `critical` forces
red, overriding mood.

---

## Model lifecycle

`LocalLLMManager` (`@MainActor`) owns a strict state machine. Only one model is
ever loaded; switching unloads the previous one first.

```
unloaded ──load──▶ loading(id) ──▶ loaded(id) ──generate──▶ generating(id)
   ▲                   │                │                        │
   │                   ▼ (fail)         │ (done)                 │
   └── unloading(id) ◀──────────────────┴────────────────────────┘
                       │
                       ▼
                   failed(message)
```

Invalid transitions are prevented:

- cannot generate while `unloaded`
- cannot load another model while `generating`
- cannot run two generations concurrently
- a model switch must unload first
- the active task is cancelled before unload

`LocalModelRegistry` provides the curated, tiered model list (Small / Medium /
Large) and the default (Llama 3.1 8B Instruct, 4-bit). `LocalModelProvider` is
the single place that touches the Hugging Face download and tokenizer.

### Timeouts

- model load: 120 s
- generation: 60 s

On timeout the task is cancelled, the manager enters `failed`, the robot shows
`error`, and a friendly message is surfaced (no stack traces in the UI).

### Concurrency

Heavy generation runs on a detached `userInitiated` task and hops to the main
actor only to deliver token chunks. This avoids a user-interactive → default
priority inversion ("Hang Risk") and keeps the UI responsive during inference.

---

## Memory management

The app is designed never to accumulate models in memory.

`unloadModel()`:

1. cancel the current generation task
2. inside an `autoreleasepool`, drop the model container and any
   tokenizer / processor / task references
3. set the MLX GPU cache limit to 0 (`MLX.Memory.cacheLimit = 0`)
4. log memory before/after in DEBUG

Before switching models the manager always unloads first, so two sets of weights
are never resident simultaneously. On app close, generation is cancelled, the
model is unloaded, and the GPU cache is cleared.

`LocalMemoryMonitor` and the always-on metrics pipeline make memory usage
visible while developing.

---

## Voice pipeline

One voice turn, orchestrated by `VoiceConversationManager`, runs end to end:

```
click / hotkey
   ▶ permissions (mic + speech)
      ▶ listen        (SpeechRecognitionService — AVAudioEngine + SFSpeechRecognizer)
         ▶ transcribe (final transcript on silence / stop / max duration)
            ▶ generate (local LLM, streamed token by token)
               ▶ speak (TextToSpeechService — AVSpeechSynthesizer queue)
                  ▶ idle
```

Key properties:

- **One turn at a time.** Starting a new turn cancels any in-flight listening,
  generation, and speech first.
- **Privacy.** Audio buffers are fed straight into the recognizer and never
  written to disk; transcripts are not persisted. On-device recognition is
  forced when the locale supports it.
- **Speak while writing.** Token deltas are buffered into whole sentences
  (`drainSentences`) and enqueued to the synthesizer as each sentence completes,
  so speech starts after the first sentence instead of after the full response.
  Splitting only on sentence boundaries (not commas) keeps prosody smooth.
- **Tuner mouth.** While TTS plays, `willSpeakRangeOfSpeechString` pulses a
  `level` value per spoken word, which the sound-wave mouth renders in sync.

The silence timer is armed only after the first detected speech, so the user has
the full max-duration window to start talking. Voice input requires Dictation to
be enabled; when it is off the recognizer fails immediately and the app maps it
to a clear, actionable message.

---

## Metrics pipeline

`SystemMetricsMonitor` (`@MainActor`) samples real host metrics about once per
second with low overhead, via Mach / Metal / `ProcessInfo`:

- App memory footprint (`task_vm_info` → `phys_footprint`)
- Available RAM (`free + inactive + purgeable + speculative` pages — matches the
  system's sense of "available", not the near-zero raw free count)
- Total RAM, system-wide CPU usage (delta between samples), thermal state
- GPU allocated / budget (Metal `currentAllocatedSize` / `recommendedMaxWorkingSetSize`)
- Static host facts (macOS version, Mac model, chip, architecture)

Values that cannot be read reliably are reported as unavailable — never faked.
The monitor stops when the app closes. The robot face reads the thermal state so
it can turn orange/red under heat.
