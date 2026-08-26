import SwiftUI
import UIKit

// MARK: - Launch Animation — Simplified Y Logo + Normal Zoom (every open)
// Premium: flat white Y on HN orange -> gentle scale-in -> hold -> normal zoom toward camera -> reveal UI
// No split, no 3D extrusion — just the Y you see on the Home icon.

struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var onComplete: () -> Void

    @State private var initialScale: CGFloat = 0.88
    @State private var initialOpacity: Double = 0
    @State private var dollyScale: CGFloat = 1
    @State private var reveal: CGFloat = 0
    @State private var completed = false

    private var isReduce: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: 0xFF6600)
                    .ignoresSafeArea()

                ZStack {
                    if isReduce {
                        reducedBody
                    } else {
                        cinematicBody
                    }
                }
                .frame(width: 164, height: 164)
                .position(x: proxy.size.width/2, y: proxy.size.height/2)
                .opacity(completed ? 0 : 1)
                .compositingGroup()
            }
        }
        .ignoresSafeArea()
        .task(id: isReduce) {
            if isReduce {
                await runReduced()
            } else {
                await runCinematic()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Reduced Motion — minimal fade
    private var reducedBody: some View {
        ZStack {
            HNSquircleShape()
                .fill(Color.white.opacity(0.12))
                .frame(width: 132, height: 132)
                .opacity(initialOpacity)
                .shadow(color: .black.opacity(0.16), radius: 20, y: 8)
            HNLogoShape()
                .fill(Color.white)
                .frame(width: 148, height: 148)
                .scaleEffect(initialScale)
                .opacity(initialOpacity)
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        }
    }

    private func runReduced() async {
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18)) {
            initialScale = 1.0
            initialOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 280_000_000)
        withAnimation(.timingCurve(0.33, 0, 0.67, 1, duration: 0.16)) {
            initialOpacity = 0
            initialScale = 1.06
        }
        try? await Task.sleep(nanoseconds: 170_000_000)
        completed = true
        onComplete()
    }

    // MARK: - Cinematic — one Y -> normal zoom (750-800ms total)
    private var cinematicBody: some View {
        HNLogoShape()
            .fill(Color.white)
            .frame(width: 168, height: 168)
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
            .scaleEffect(initialScale * dollyScale * (1 + reveal * 3.2))
            .opacity(initialOpacity * Double(1 - reveal * 0.85))
            .blur(radius: reveal > 0.6 ? Double((reveal - 0.6) * 6) : 0)
    }

    private func runCinematic() async {
        // Stage 1: 0-170ms appear flat Y
        withAnimation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.16)) {
            initialScale = 1.0
            initialOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 210_000_000)

        // Stage 2: hold 100ms (premium pause, still flat Y)
        try? await Task.sleep(nanoseconds: 110_000_000)

        // Stage 3: 280-620ms normal zoom toward camera (single Y, no split)
        withAnimation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.34)) {
            dollyScale = 3.25
        }
        try? await Task.sleep(nanoseconds: 340_000_000)

        // Stage 4: 620-780ms reveal into UI
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1, duration: 0.16)) {
            reveal = 1
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        completed = true
        HapticsManager.selectionChanged()
        onComplete()
    }
}

#Preview("Launch - Cinematic") {
    LaunchAnimationView(onComplete: {}).frame(height: 780)
}
