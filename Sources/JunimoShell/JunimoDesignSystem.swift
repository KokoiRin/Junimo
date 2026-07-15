import AppKit
import SwiftUI

let junimoAccent = Color(red: 0.24, green: 0.95, blue: 0.58)
let junimoPanelBlack = Color(red: 0.006, green: 0.007, blue: 0.008)

// JunimoPanelLayout 集中定义控制器与 SwiftUI 必须共享的面板尺寸。
enum JunimoPanelLayout {
    static let collapsedWidth: CGFloat = 420
    // collapsedNotchClearance 包含半个刘海宽度与不贴边的安全间隔，决定胶囊内边缘到屏幕中心的距离。
    static let collapsedNotchClearance: CGFloat = 102
    // collapsedCapsuleLaneWidth 为每侧胶囊保留独立等宽轨道，避免内容宽度不同破坏刘海两侧对称性。
    static let collapsedCapsuleLaneWidth: CGFloat = collapsedWidth / 2 - collapsedNotchClearance
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 380
}

// JunimoTypography 统一多页面壳层的字号层级，避免功能增加后重新退化为密集小字。
enum JunimoTypography {
    static let pageTitle: CGFloat = 22
    static let navigation: CGFloat = 15
    static let body: CGFloat = 14
    static let caption: CGFloat = 12
}

// JunimoButtonTone 区分主要动作与低强调动作。
enum JunimoButtonTone {
    case primary
    case secondary
}

// JunimoButtonStyle 提供 Focus 和 Todo 页面一致的紧凑按钮视觉。
struct JunimoButtonStyle: ButtonStyle {
    var tone: JunimoButtonTone = .secondary

    // makeBody 根据动作层级和按压状态渲染按钮。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: JunimoTypography.body, weight: .semibold))
            .foregroundStyle(tone == .primary ? Color.black.opacity(0.88) : junimoAccent)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(
                tone == .primary ? junimoAccent : Color.white.opacity(configuration.isPressed ? 0.11 : 0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tone == .primary ? Color.clear : junimoAccent.opacity(0.50), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

// TopAttachedPanelShape 保持顶部贴屏直角、底部圆角的刘海展开轮廓。
struct TopAttachedPanelShape: Shape {
    var bottomRadius: CGFloat = 22

    // path 构造只有底边两个圆角的封闭路径。
    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

// JunimoPanelBackground 提供页面切换时不变的统一背景。
struct JunimoPanelBackground: View {
    var body: some View {
        TopAttachedPanelShape(bottomRadius: 22)
            .fill(
                LinearGradient(
                    colors: [Color.black, junimoPanelBlack, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

// JunimoAppIcon 复用应用资源，并在资源缺失时提供稳定图标。
struct JunimoAppIcon: View {
    var body: some View {
        Group {
            if let image = NSImage(named: "junimo-junimo-sprite") {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "timer")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(junimoAccent)
            }
        }
    }
}
