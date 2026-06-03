//
//  RobotFaceShapes.swift
//  BabelRobot
//
//  Reusable vector shapes for the robot's facial elements.
//

import SwiftUI

/// A quadratic curve across the frame. `curvature` > 0 bends up (smile),
/// < 0 bends down (frown), 0 is flat.
struct Curve: Shape {
    var curvature: CGFloat
    var animatableData: CGFloat {
        get { curvature }
        set { curvature = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY - curvature * rect.height))
        return p
    }
}

/// A rounded heart that fills the frame.
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.30),
            control1: CGPoint(x: w * 0.15, y: h * 0.70),
            control2: CGPoint(x: 0, y: h * 0.52))
        p.addArc(
            center: CGPoint(x: w * 0.25, y: h * 0.28),
            radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(
            center: CGPoint(x: w * 0.75, y: h * 0.28),
            radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.95),
            control1: CGPoint(x: w, y: h * 0.52),
            control2: CGPoint(x: w * 0.85, y: h * 0.70))
        p.closeSubpath()
        return p
    }
}

/// A gentle sine wave across the frame (confused mouth).
struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let amp = rect.height * 0.5
        p.move(to: CGPoint(x: rect.minX, y: midY))
        let steps = 24
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let y = midY - sin(CGFloat(i) / CGFloat(steps) * .pi * 2) * amp
            p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}

/// An upward-pointing triangle (cat ear).
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A downward-pointing triangle (cat nose).
struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// An open ring (used for the loading spinner eye), leaving a gap.
struct ArcRing: Shape {
    var gap: Angle = .degrees(90)
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2
        p.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(360 - 90) - gap,
            clockwise: false)
        return p
    }
}
