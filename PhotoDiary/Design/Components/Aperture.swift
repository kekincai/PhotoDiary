import SwiftUI

/// 相机光圈：几片叶片围成的开口，`closure` 0 是全开、1 是闭合。叶片一边收拢一边转动，像快门合上。
/// 可以做动画：closure 是 animatableData。
struct Aperture: View, Animatable {
    var closure: Double
    var color: Color
    var seam: Color
    var blades = 6

    var animatableData: Double {
        get { closure }
        set { closure = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let closure = min(max(closure, 0), 1)
            // 开口的内切圆半径：全开时留一圈叶片，闭合时归零。
            let open = r * 0.78 * (1 - closure)
            // 叶片收拢时顺着转一点，才像真的光圈。
            let spin = CGFloat(closure) * CGFloat.pi / 3
            context.clip(to: Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)))

            var transforms: [CGAffineTransform] = []
            for i in 0..<blades {
                let angle = CGFloat(i) * 2 * CGFloat.pi / CGFloat(blades) + spin
                transforms.append(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle))
            }
            // 每片叶片是“开口那条边以外的半平面”，几片叠起来，中间剩下一个正多边形的开口。
            for t in transforms {
                var blade = Path()
                blade.addRect(CGRect(x: open, y: -2 * r, width: 4 * r, height: 4 * r), transform: t)
                context.fill(blade, with: .color(color))
            }
            // 叶片的边：从开口的一个角向外到边缘，只画露出来的那一段。
            let half = open * tan(CGFloat.pi / CGFloat(blades))
            let edge = sqrt(max(r * r - open * open, 0))
            for t in transforms {
                var line = Path()
                line.move(to: CGPoint(x: open, y: half).applying(t))
                line.addLine(to: CGPoint(x: open, y: edge).applying(t))
                context.stroke(line, with: .color(seam), lineWidth: 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}
