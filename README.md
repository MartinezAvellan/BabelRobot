# BabelRobot

**BabelRobot is a desktop AI companion for macOS that runs local language models using Apple Silicon and MLX.**

It pairs a fully offline, on-device LLM with an animated robot personality that
lives on your desktop — reacting to what the model is doing, listening to your
voice, and speaking its answers back. No cloud, no API keys, no telemetry. Your
prompts stay on your Mac.

> **Status:** proof of concept / early prototype. Built for personal,
> educational, and research use.

---

## Features

- **Local LLM execution** — inference runs entirely on-device; nothing is sent to a server.
- **MLX support** — built on Apple's [MLX](https://github.com/ml-explore/mlx-swift-lm) for fast Apple Silicon inference.
- **Multiple model support** — a curated registry of small, medium, and large models with one-tap load/unload.
- **Voice interaction** — speak to the robot and hear its answers (Apple Speech in, AVSpeech out), spoken sentence-by-sentence while the model is still writing.
- **Desktop companion mode** — a floating, draggable robot that follows your cursor, sleeps when idle, and wakes on interaction.
- **Animated robot personality** — a lightweight SwiftUI face with moods, blinking, gaze, and a sound-wave "tuner" mouth.
- **Clipboard integration** — assist with whatever you're working on (roadmap).
- **Privacy-first design** — audio is never written to disk; transcripts are not persisted.
- **Offline-first architecture** — models download once from Hugging Face for setup, then run offline.

---

## Requirements

- macOS 14 or later (Apple Silicon — M1 or newer)
- Xcode 16+
- Enough RAM for your chosen model (see below — an 8B 4-bit model needs ~5 GB)
- **Dictation enabled** (System Settings ▸ Keyboard ▸ Dictation) for voice input
- Microphone permission for voice input

---

## Getting started

```bash
git clone https://github.com/<your-org>/BabelRobot.git
cd BabelRobot
open BabelRobot.xcodeproj
```

1. Build and run the **BabelRobot** scheme in Xcode (or `xcodebuild -scheme BabelRobot -destination 'platform=macOS' build`).
2. On first launch the app downloads and loads the default model (Llama 3.1 8B Instruct, 4-bit) from Hugging Face. A progress bar shows the download.
3. Pick a different model from the picker and tap **Load** to switch. Only one model is active at a time.
4. Click the floating robot (or use the Talk button) to start a voice turn.

Swift Package Manager resolves the MLX dependencies automatically on first build.

---

## Supported models

The model registry is grouped into three tiers. Only one model is loaded at a
time; switching unloads the previous one and frees GPU memory first.

### Small

- Llama 3.2 3B Instruct
- Qwen 3 4B
- DeepSeek R1 Distill Qwen 7B
- Gemma 3 4B

### Medium

- Llama 3.1 8B Instruct *(default)*
- Qwen 3 8B
- DeepSeek R1 Distill Qwen 14B
- Gemma 3 12B

### Large

- Llama 3.3 70B Instruct
- Qwen 3 14B
- DeepSeek R1 Distill Qwen 32B
- Qwen 3 32B

Larger models need substantially more memory. If a model fails to load, try a
smaller tier.

---

## Architecture

BabelRobot is organized into clear engines, each with a single responsibility:

- **UI Layer** — SwiftUI views, theme, and the main window.
- **Robot Engine** — the face state machine, animator, and behavior/emotion engines.
- **Model Engine** — model lifecycle, the registry, and the MLX inference path.
- **Voice Engine** — microphone capture, speech recognition, and text-to-speech.
- **Metrics Engine** — always-on system metrics (RAM, CPU, GPU, thermal).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the state machine, model
lifecycle, memory management, and the voice/metrics pipelines in detail.

---

## Roadmap

### Phase 1 — Foundation
- Local inference
- Robot personality
- System metrics

### Phase 2 — Interaction
- Voice interaction
- Clipboard assistant

### Phase 3 — Understanding
- OCR
- Screen understanding

### Phase 4 — Autonomy
- Automation
- Agent workflows

---

## Privacy

- LLM inference is **100% local** (MLX). No cloud LLM calls, no API keys, no telemetry.
- Model weights download from Hugging Face once for setup/cache, then run offline.
- Voice audio is fed straight into the recognizer and **never written to disk**; transcripts are not persisted.
- Apple's Speech framework may use the system speech service depending on your settings; the app surfaces this and prefers on-device recognition when supported. The LLM never leaves your Mac.

---

## Contributing

Contributions are welcome for personal, educational, and research use. Please
open an issue to discuss a change before submitting a large pull request, and
follow the templates in [.github](.github). By contributing you agree your
contributions are licensed under the project license.

---

## License

This project is licensed under **PolyForm Noncommercial 1.0.0**.

Personal, educational, and research use are permitted.

Commercial use, resale, SaaS offerings, paid redistribution, and monetization
require explicit written permission from the copyright holder.

See [LICENSE](LICENSE) for the full text.
