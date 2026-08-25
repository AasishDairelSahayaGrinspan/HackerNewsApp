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
                // Premium crisp compositing — render at native scale, no low-res raster
                .drawingGroup(opaque: false, colorMode: .extendedLinear)
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
        .drawingGroup(opaque: false)
        
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

    // MARK: - Cinematic (950ms)

    private var cinematicBody: some View {
        ZStack {
            // Faux extrusion — 10 layers for real depth, each 1pt z-offset, darker orange side
            ZStack {
                ForEach(0..<10, id: \.self) { i in
                    let depth = CGFloat(i)
                    HNLogoShape()
                        .fill(Color(hex: 0xB84D00).opacity(Double(i) * 0.032))
                        .frame(width: 164, height: 164)
                        .offset(y: depth * 1.05)
                        .scaleEffect(1 - depth * 0.0038)
                        .opacity(i == 9 ? 0 : 1)
                        
                }
            }
            .opacity(extrude > 0 ? 1 : 0)
            .allowsHitTesting(false)

            // Split pieces overlay
            YSplitPieces(split: split, extrude: extrude, rotY: rotY, rotX: rotX, dollyScale: dollyScale)

            // Unified cap — fades to pieces as split →1
            HNLogoShape()
                .fill(Color.white)
                .frame(width: 164, height: 164)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
                .scaleEffect(initialScale)
                .opacity(Double(1 - split * 0.96))
                .opacity(initialOpacity)
                .rotation3DEffect(.degrees(rotY * 0.45), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
                .rotation3DEffect(.degrees(rotX * 0.45), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
                
        }
        .rotation3DEffect(.degrees(rotY * 0.26), axis: (x: 0, y: 1, z: 0), perspective: 0.54)
        .rotation3DEffect(.degrees(rotX * 0.20), axis: (x: 1, y: 0, z: 0), perspective: 0.54)
        .scaleEffect(dollyScale)
        .scaleEffect(initialScale)
        .opacity(initialOpacity)
        .scaleEffect(1 + reveal * 8.0)
        .blur(radius: reveal > 0.62 ? Double((reveal - 0.62) * 9) : 0)
        .opacity(Double(1 - reveal * 0.68))
        
        .drawingGroup(opaque: false)
    }

    private func runCinematic() async {
        // Stage 1: 0–150ms appear flat Y (scale 0.86→1, opacity 0→1)
        withAnimation(.timingCurve(0.2, 0.84, 0.24, 1, duration: 0.16)) {
            initialScale = 1.0
            initialOpacity = 1
        }
        try? await Task.sleep(nanoseconds: 170_000_000)

        // Stage 2: 150–400ms split begins (simultaneous with depth onset)
        withAnimation(.timingCurve(0.42, 0.0, 0.58, 1, duration: 0.26)) {
            split = 1
            extrude = 0.55
        }
        try? await Task.sleep(nanoseconds: 120_000_000)

        // Stage 3: 400–700ms extrusion → 3D, rotation, light perspective
        withAnimation(.timingCurve(0.22, 0.68, 0.32, 1, duration: 0.32)) {
            extrude = 1
            rotY = 14
            rotX = -7
        }
        try? await Task.sleep(nanoseconds: 220_000_000)

        // Stage 4: 700–950ms dolly toward camera (logo becomes huge, passes camera)
        withAnimation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.28)) {
            dollyScale = 2.9
            rotY = -6
            rotX = 5
            dollyProgress = 1
        }
        try? await Task.sleep(nanoseconds: 140_000_000)
        // Stage 5: 950–1080ms mask reveal into UI
        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1, duration: 0.18)) {
            reveal = 1
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        completed = true
        // Small haptic tick at peak for premium feel (mirrors existing HapticsManager language)
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
        // We create three pieces by masking the Y shape to its arms/stem region.
        // Masks are simple rectangles covering left arm, right arm, stem zones.
        ZStack {
            // Left arm piece
            YPiece(region: .leftArm)
                .offset(x: -split * 18, y: -split * 4 - extrude * 1.5)
                .rotationEffect(.degrees(-split * 6))
                .rotation3DEffect(.degrees(rotY * 0.9 + split * -8), axis: (x: 0, y: 1, z: 0), perspective: 0.52)
                .rotation3DEffect(.degrees(rotX * 0.6), axis: (x: 1, y: 0, z: 0), perspective: 0.52)
                .shadow(color: .black.opacity(0.18 * Double(split)), radius: 10 * split, y: 6 * split)

            // Right arm piece
            YPiece(region: .rightArm)
                .offset(x: split * 18, y: -split * 4 - extrude * 1.5)
                .rotationEffect(.degrees(split * 6))
                .rotation3DEffect(.degrees(rotY * 0.9 + split * 8), axis: (x: 0, y: 1, z: 0), perspective: 0.52)
                .rotation3DEffect(.degrees(rotX * 0.6), axis: (x: 1, y: 0, z: 0), perspective: 0.52)
                .shadow(color: .black.opacity(0.18 * Double(split)), radius: 10 * split, y: 6 * split)

            // Stem piece (drives forward most, feels like passing camera)
            YPiece(region: .stem)
                .offset(y: split * 10 + extrude * 2)
                .rotation3DEffect(.degrees(rotY * -0.45), axis: (x: 0, y: 1, z: 0), perspective: 0.52)
                .rotation3DEffect(.degrees(rotX * 0.8 + split * 4), axis: (x: 1, y: 0, z: 0), perspective: 0.52)
                .shadow(color: .black.opacity(0.20 * Double(split)), radius: 14 * split, y: 8 * split)
        }
        .frame(width: 164, height: 164)
        .opacity(split > 0.05 ? 1 : 0)
        .scaleEffect(dollyScale > 1.5 ? (1 + (dollyScale - 1.5) * 0.12) : 1) // stem leads
    }
}

private struct YPiece: View {
    enum Region { case leftArm, rightArm, stem }
    var region: Region
    var body: some View {
        // Clip the full Y to region rect; keep white fill + subtle inner depth edge
        HNLogoShape()
            .fill(Color.white)
            .frame(width: 164, height: 164)
            .clipShape(YPieceMask(region: region))
            .overlay {
                // Very subtle 1pt inner edge for realism at split seam
                YPieceMask(region: region).stroke(Color.black.opacity(0.07), lineWidth: 1)
            }
    }
}

private struct YPieceMask: Shape {
    var region: YPiece.Region
    func path(in rect: CGRect) -> Path {
        // rect is 164x164, same as Y frame. Mask rects proportional to Y geometry.
        // Y junction at y=0.525*size, arm tops 0.278, stem bottom 0.772.
        // Split boundaries: left arm rect covers left half above junction + diagonal; right similarly.
        // Simpler: axis-aligned rects that each contain one arm/stem with overlap at junction (overlap hides seam when split=0)
        switch region {
        case .leftArm:
            // Left half, top to junction
            return Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.58, height: rect.height * 0.56))
        case .rightArm:
            return Path(CGRect(x: rect.minX + rect.width * 0.42, y: rect.minY, width: rect.width * 0.58, height: rect.height * 0.56))
        case .stem:
            // Stem vertical rect
            return Path(CGRect(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.48, width: rect.width * 0.32, height: rect.height * 0.52))
        }
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
