import SwiftUI
import UIKit

// MARK: - Launch Animation — 1:1 X copy with app branding
// Frame map from ScreenRecording_09-13-2026 @10fps (53 frames, 828x1792):
// f10-12 home grid, f14 iOS icon-zoom window expands (system, rounded rect),
// f16 full splash (logo already opaque, no fade), f16-f30 static hold (~1.4s
// in recording incl. lag -> ~900ms real), f30 logo starts growing, f31 ~1.8x,
// f32 giant logo strokes act as mask revealing feed through them, f33+ feed.
// Replica: prev HN orange bg (0xFF6600) + exact app-icon mark (180pt orange
// squircle + 120pt white Y at icon proportions), instant show -> 900ms static
// hold -> 450ms mask-zoom 1x->8x revealing feed behind -> 180ms fade-cut.

struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var onComplete: () -> Void

    @State private var holeScale: CGFloat = 1
    @State private var logoOpacity: Double = 1
    @State private var overlayOpacity: Double = 1
    @State private var completed = false

    private var isReduce: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // Prev brand colour + the REAL icon artwork (LaunchLogo imageset, cut from
    // AppIcon-1024 — no redrawn Shape, pixel-identical Y). Badge 180pt so the
    // Y presence matches the X glyph in f16.
    private static let splashBackground = Color(hex: 0xFF6600)
    private static let badgeSize: CGFloat = 180
    // Mask-hole Y frame ~= PNG's Y extent (~67% of badge). Hole kept slightly
    // inside the artwork (0.9x) so it stays hidden behind the real Y during
    // the hold; it only matters once the artwork fades at zoom start.
    private static let logoSize: CGFloat = 120
    // f32 giant-X fill: hole must cover screen -> 8x (672pt) overflows 393x852.
    private static let zoomScale: CGFloat = 8
    // Hole stays just inside the white Y rim so no feed text slivers leak
    // around the logo edges during the static hold.
    private static let holeInset: CGFloat = 0.9

    var body: some View {
        GeometryReader { proxy in
            let cx = proxy.size.width / 2
            let cy = proxy.size.height / 2
            ZStack {
                // Orange overlay; the Y hole is built in this same stack so it
                // aligns pixel-exact with the visible logo — no text peek.
                // Behind it is the real RootTabView feed, revealed through the
                // growing hole (f32), never random text.
                Self.splashBackground
                    .ignoresSafeArea()
                    .mask {
                        ZStack {
                            Rectangle().fill(.white)
                            HNLogoShape()
                                .fill(.black)
                                .frame(width: Self.logoSize, height: Self.logoSize)
                                .scaleEffect(holeScale * Self.holeInset)
                                .position(x: cx, y: cy)
                        }
                    }

                // The real app-icon artwork — pixel-identical Y, no redraw.
                // (Badge melts into the orange splash like X's black icon
                // melts into its black splash.) Fades the instant the zoom
                // starts so the feed shows through the expanding Y window.
                Image("LaunchLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.badgeSize, height: Self.badgeSize)
                    .position(x: cx, y: cy)
                    .opacity(logoOpacity)
            }
            .opacity(overlayOpacity)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .opacity(completed ? 0 : 1)
        .task(id: isReduce) {
            if isReduce {
                await runReduced()
            } else {
                await runXCopy()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Reduced Motion — static logo, short hold, fade only (no zoom)
    private func runReduced() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            overlayOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 210_000_000)
        completed = true
        onComplete()
    }

    // MARK: - 1:1 X beats — instant show, static hold, mask-zoom reveal
    private func runXCopy() async {
        // Stage 1: logo already visible at opacity 1 (f14->f16, no fade-in).
        // Stage 2: static hold ~900ms (f16-f30 identical, zero motion, hole
        // hidden behind the white Y so no feed text leaks).
        try? await Task.sleep(nanoseconds: 900_000_000)

        // Stage 3: white Y fades fast while the Y hole zooms 1x->8x over 450ms
        // (f30->f32, ease-in like X) — feed shows inside the growing Y window.
        withAnimation(.easeOut(duration: 0.12)) {
            logoOpacity = 0
        }
        withAnimation(.timingCurve(0.32, 0.08, 0.24, 1, duration: 0.45)) {
            holeScale = Self.zoomScale
        }
        try? await Task.sleep(nanoseconds: 460_000_000)

        // Stage 4: 180ms fade-cut to feed (f32->f33, giant strokes exit).
        withAnimation(.easeOut(duration: 0.18)) {
            overlayOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 190_000_000)
        completed = true
        onComplete()
    }
}

#Preview("Launch - X 1:1 orange") {
    LaunchAnimationView(onComplete: {}).frame(height: 780)
}
