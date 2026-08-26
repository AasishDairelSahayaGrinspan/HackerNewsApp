import SwiftUI

/// Vector Y monogram used for AppIcon and Launch animation.
/// Normalized to unit rect 0..1 so it scales cleanly at any size.
/// Matches the generated AppIcon geometry (HN orange squircle + white Y).
struct HNLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        Self.addY(to: &path, in: rect)
        return path
    }

    /// Shared geometry helper — draws the full Y (three capsules) into any path.
    /// Option A: pixel-identical to AppIcon generate_icon.py (0.315/0.685, 0.285/0.525)
    static func addY(to path: inout Path, in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let junctionY = rect.minY + h * 0.525
        let armTopY = rect.minY + h * 0.285
        let stemBottomY = rect.minY + h * 0.760
        let leftX = rect.minX + w * 0.315
        let rightX = rect.minX + w * 0.685
        let strokeW = w * 0.122
        capsule(from: CGPoint(x: leftX, y: armTopY), to: CGPoint(x: cx, y: junctionY), width: strokeW, to: &path)
        capsule(from: CGPoint(x: rightX, y: armTopY), to: CGPoint(x: cx, y: junctionY), width: strokeW, to: &path)
        capsule(from: CGPoint(x: cx, y: junctionY), to: CGPoint(x: cx, y: stemBottomY), width: strokeW, to: &path)
    }

    fileprivate static func capsule(from p0: CGPoint, to p1: CGPoint, width: CGFloat, to path: inout Path) {
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = hypot(dx, dy)
        guard len > 0 else { return }
        let nx = -dy / len
        let ny = dx / len
        let hw = width / 2
        let a = CGPoint(x: p0.x + nx * hw, y: p0.y + ny * hw)
        let b = CGPoint(x: p0.x - nx * hw, y: p0.y - ny * hw)
        let c = CGPoint(x: p1.x - nx * hw, y: p1.y - ny * hw)
        let d = CGPoint(x: p1.x + nx * hw, y: p1.y + ny * hw)
        var sub = Path()
        sub.move(to: a)
        sub.addLine(to: d)
        sub.addArc(center: p1, radius: hw, startAngle: Angle(radians: atan2(ny, nx)), endAngle: Angle(radians: atan2(ny, nx) + Double.pi), clockwise: false)
        sub.addLine(to: b)
        sub.addArc(center: p0, radius: hw, startAngle: Angle(radians: atan2(-ny, -nx)), endAngle: Angle(radians: atan2(-ny, -nx) + Double.pi), clockwise: false)
        sub.closeSubpath()
        path.addPath(sub)
    }
}

// MARK: - True Y pieces (no rectangular mask — each is the actual capsule)

struct HNLogoLeftArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width; let h = rect.height
        let cx = rect.midX; let junctionY = rect.minY + h * 0.525
        let leftX = rect.minX + w * 0.315; let armTopY = rect.minY + h * 0.285
        HNLogoShape.capsule(from: CGPoint(x: leftX, y: armTopY), to: CGPoint(x: cx, y: junctionY), width: w * 0.122, to: &p)
        return p
    }
}

struct HNLogoRightArmShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width; let h = rect.height
        let cx = rect.midX; let junctionY = rect.minY + h * 0.525
        let rightX = rect.minX + w * 0.685; let armTopY = rect.minY + h * 0.285
        HNLogoShape.capsule(from: CGPoint(x: rightX, y: armTopY), to: CGPoint(x: cx, y: junctionY), width: w * 0.122, to: &p)
        return p
    }
}

struct HNLogoStemShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width; let h = rect.height
        let cx = rect.midX; let junctionY = rect.minY + h * 0.525; let stemBottomY = rect.minY + h * 0.760
        HNLogoShape.capsule(from: CGPoint(x: cx, y: junctionY), to: CGPoint(x: cx, y: stemBottomY), width: w * 0.122, to: &p)
        return p
    }
}

/// Smaller, squircle background for preview / launch badge.
struct HNSquircleShape: Shape {
    var cornerRadius: CGFloat = 0.2237 // 22.37% continuous
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * cornerRadius
        return Path(roundedRect: rect, cornerRadius: r)
    }
}

// Preview for Xcode
#Preview {
    let size: CGFloat = 220
    ZStack {
        HNSquircleShape().fill(Color(hex: 0xFF6600)).frame(width: size, height: size).shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        HNLogoShape().fill(.white).frame(width: size, height: size).padding(36)
    }
    .padding(40)
    .background(Color(.systemBackground))
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}
