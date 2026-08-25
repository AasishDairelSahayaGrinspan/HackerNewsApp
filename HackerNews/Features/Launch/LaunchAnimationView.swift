import SwiftUI
import UIKit

// MARK: - Launch Animation (X-inspired motion language, HN brand)

/// Premium 700–1100ms launch: flat Y → split → 3D extrusion → camera dolly → mask reveal → UI.
/// Lightweight: SwiftUI + CATransform3D m34 perspective + stacked extrusion. No RealityKit/Lottie.
struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme

    var onComplete: () -> Void

    // Timeline state
    @State private var initialScale: CGFloat = 0.86
    @State private var initialOpacity: Double = 0
    @State private var split: CGFloat = 0 // 0→1
    @State private var extrude: CGFloat = 0 // 0→1
    @State private var rotY: Double = 0
    @State private var rotX: Double = 0
    @State private var dollyScale: CGFloat = 1
    @State private var dollyProgress: CGFloat = 0
    @State private var reveal: CGFloat = 0
    @State private var completed = false

    // Accessibility fast path detection
    private var isReduce: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // HN Orange brand continuity — same as icon, no banding
                Color(hex: 0xFF6600)
                    .ignoresSafeArea()

                // Centered composition — sized to screen, not hard 164pt bitmap
                ZStack {
                    if isReduce {
                        reducedBody
                    } else {
                        cinematicBody
                    }
                }
                .frame(width: 164, height: 164)
                .position(x: proxy.size.width/2, y: proxy.size.height/2)
                .scaleEffect(reveal > 0 ? 1 + reveal * 0.06 : 1)
                .opacity(completed ? 0 : 1)
                .compositingGroup()
                
            }
        }
        .ignoresSafeArea()
        .task(id: isReduce) {
            // Re-trigger task when reduce mode flips for previews
            if isReduce {
                await runReduced()
            } else {
                await runCinematic()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Reduced Motion (120–280ms)

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
        // 0–150ms appear
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

    // MARK: - Cinematic (1050ms) — one → white split → 3D arm extrusion → dolly
    private var cinematicBody: some View {
        ZStack {
            // Stage 1-2: unified white Y (flat) — visible until split replaces it
            HNLogoShape()
                .fill(Color.white)
                .frame(width: 164, height: 164)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
                .scaleEffect(initialScale)
                .opacity(Double(1 - split * 0.98))
                .opacity(initialOpacity)
                .rotation3DEffect(.degrees(rotY * 0.35), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
                .rotation3DEffect(.degrees(rotX * 0.35), axis: (x: 1, y: 0, z: 0), perspective: 0.54)

            // Stage 2-4: three white arms — first flat white split, then per-arm 3D extrusion
            YSplitPieces(split: split, extrude: extrude, rotY: rotY, rotX: rotX, dollyScale: dollyScale)
        }
        .rotation3DEffect(.degrees(rotY * 0.22), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
        .rotation3DEffect(.degrees(rotX * 0.16), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
        .scaleEffect(dollyScale)
        .scaleEffect(initialScale)
        .opacity(initialOpacity)
        .scaleEffect(1 + reveal * 8.0)
        .blur(radius: reveal > 0.62 ? Double((reveal - 0.62) * 9) : 0)
        .opacity(Double(1 - reveal * 0.68))
    }

    private func runCinematic() async {
        // Stage 1: 0–170ms — one white Y appears flat (scale 0.86→1, opacity 0→1) — premium hold
        withAnimation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.16)) {
            initialScale = 1.0
            initialOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Stage 2: 170–420ms — split like white (flat white 3 arms separate, no 3D yet)
        withAnimation(.timingCurve(0.38, 0.0, 0.22, 1, duration: 0.24)) {
            split = 1
        }
        try? await Task.sleep(nanoseconds: 230_000_000)

        // Stage 3: 420–720ms — arm in 3-D extrusion (per-arm depth + rotation)
        withAnimation(.timingCurve(0.22, 0.68, 0.32, 1, duration: 0.30)) {
            extrude = 1
            rotY = 14
            rotX = -7
        }
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Stage 4: 720–970ms — dolly toward camera (logo huge, passes camera)
        withAnimation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.26)) {
            dollyScale = 3.0
            rotY = -5
            rotX = 4
            dollyProgress = 1
        }
        try? await Task.sleep(nanoseconds: 140_000_000)

        // Stage 5: 970–1090ms — reveal into UI
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1, duration: 0.18)) {
            reveal = 1
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        completed = true
        HapticsManager.selectionChanged()
        onComplete()
    }
}

// MARK: - Y Split Pieces

private struct YSplitPieces: View {
    var split: CGFloat
    var extrude: CGFloat
    var rotY: Double
    var rotX: Double
    var dollyScale: CGFloat

    var body: some View {
        ZStack {
            // Left arm — white split first, then per-arm 3D extrusion
            YPiece(region: .leftArm, extrude: extrude)
                .offset(x: -split * 20, y: -split * 5)
                .rotationEffect(.degrees(-split * 5))
                .rotation3DEffect(.degrees(rotY * 0.85 + split * -7), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
                .rotation3DEffect(.degrees(rotX * 0.55), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
                .shadow(color: .black.opacity(0.16 * Double(split)), radius: 9 * split, y: 5 * split)

            // Right arm
            YPiece(region: .rightArm, extrude: extrude)
                .offset(x: split * 20, y: -split * 5)
                .rotationEffect(.degrees(split * 5))
                .rotation3DEffect(.degrees(rotY * 0.85 + split * 7), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
                .rotation3DEffect(.degrees(rotX * 0.55), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
                .shadow(color: .black.opacity(0.16 * Double(split)), radius: 9 * split, y: 5 * split)

            // Stem — drives forward in dolly
            YPiece(region: .stem, extrude: extrude)
                .offset(y: split * 12)
                .rotation3DEffect(.degrees(rotY * -0.42), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
                .rotation3DEffect(.degrees(rotX * 0.75 + split * 3), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
                .shadow(color: .black.opacity(0.18 * Double(split)), radius: 12 * split, y: 7 * split)
        }
        .frame(width: 164, height: 164)
        .opacity(split > 0.04 ? 1 : 0)
        .scaleEffect(dollyScale > 1.5 ? (1 + (dollyScale - 1.5) * 0.10) : 1)
    }
}

private struct YPiece: View {
    enum Region { case leftArm, rightArm, stem }
    var region: Region
    var extrude: CGFloat = 0
    var body: some View {
        let size: CGFloat = 164
        let w = size; let h = size
        let cx = w/2; let junctionY = h * 0.522; let armTopY = h * 0.288
        let stemBottomY = h * 0.760; let leftX = w * 0.318; let rightX = w * 0.682
        let strokeW: CGFloat = w * 0.122
        let leftDX = cx - leftX; let leftDY = junctionY - armTopY
        let rightDX = cx - rightX; let rightDY = junctionY - armTopY
        let stemLen = stemBottomY - junctionY

        return ZStack {
            // Per-arm extrusion — darker capsules behind white when extrude >0 (arm in 3-D)
            if extrude > 0.02 {
                let depthCount = 7
                ForEach(0..<depthCount, id: \.self) { i in
                    let d = CGFloat(i+1) * extrude
                    let alpha = Double(i+1) * 0.028 * Double(extrude)
                    Group {
                        if region == .leftArm {
                            let len = hypot(leftDX, leftDY)
                            let midX = (leftX + cx)/2 - w/2
                            let midY = (armTopY + junctionY)/2 - h/2
                            let angle = atan2(leftDY, leftDX) * 180 / .pi - 90
                            Capsule().fill(Color(hex: 0x8A3D00).opacity(alpha))
                                .frame(width: strokeW, height: len)
                                .rotationEffect(.degrees(angle))
                                .offset(x: midX, y: midY + d * 0.9)
                                .scaleEffect(1 - d * 0.003)
                        } else if region == .rightArm {
                            let len = hypot(rightDX, rightDY)
                            let midX = (rightX + cx)/2 - w/2
                            let midY = (armTopY + junctionY)/2 - h/2
                            let angle = atan2(rightDY, rightDX) * 180 / .pi - 90
                            Capsule().fill(Color(hex: 0x8A3D00).opacity(alpha))
                                .frame(width: strokeW, height: len)
                                .rotationEffect(.degrees(angle))
                                .offset(x: midX, y: midY + d * 0.9)
                                .scaleEffect(1 - d * 0.003)
                        } else {
                            let midY = (junctionY + stemBottomY)/2 - h/2
                            Capsule().fill(Color(hex: 0x8A3D00).opacity(alpha))
                                .frame(width: strokeW, height: stemLen)
                                .offset(y: midY + d * 0.9)
                                .scaleEffect(1 - d * 0.003)
                        }
                    }
                }
            }
            // White on top
            if region == .leftArm {
                let len = hypot(leftDX, leftDY)
                let midX = (leftX + cx)/2 - w/2
                let midY = (armTopY + junctionY)/2 - h/2
                let angle = atan2(leftDY, leftDX) * 180 / .pi - 90
                Capsule().fill(Color.white)
                    .frame(width: strokeW, height: len)
                    .rotationEffect(.degrees(angle))
                    .offset(x: midX, y: midY)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            } else if region == .rightArm {
                let len = hypot(rightDX, rightDY)
                let midX = (rightX + cx)/2 - w/2
                let midY = (armTopY + junctionY)/2 - h/2
                let angle = atan2(rightDY, rightDX) * 180 / .pi - 90
                Capsule().fill(Color.white)
                    .frame(width: strokeW, height: len)
                    .rotationEffect(.degrees(angle))
                    .offset(x: midX, y: midY)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            } else {
                let midY = (junctionY + stemBottomY)/2 - h/2
                Capsule().fill(Color.white)
                    .frame(width: strokeW, height: stemLen)
                    .offset(y: midY)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

// Helpers

private extension View {
    func perspective(_ m34: Double) -> some View {
        // Bridge to CATransform3D m34 if needed — SwiftUI rotation3DEffect already exposes perspective, so no-op here.
        self
    }
}

#Preview("Launch - Cinematic") {
    LaunchAnimationView(onComplete: {}).frame(height: 780)
}
