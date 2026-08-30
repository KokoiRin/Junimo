import AppKit
import JunimoCore
import QuartzCore
import SwiftUI

// 本地开发构建没有 Apple Team ID，macOS 会拒绝系统通知；这里用 Junimo 自己的可点击提示条交付同一行为。
@MainActor
final class MacCodexCompletionNotificationService {
    private let workspace = MacQuickLaunchWorkspace()
    private var bannerPanel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func notifyCompletion(_ event: CodexCompletionEvent) {
        NSSound(named: NSSound.Name("Hero"))?.play()
        presentBanner(for: event)
    }

    private func presentBanner(for event: CodexCompletionEvent) {
        dismissWorkItem?.cancel()
        bannerPanel?.close()

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = CodexCompletionBanner(
            taskTitle: event.title.isEmpty ? "未命名任务" : event.title,
            openTask: { [weak self] in
                self?.openCodexTask(threadID: event.threadId)
            }
        )
        panel.contentView = FirstClickHostingView(rootView: view)

        let size = NSSize(width: 268, height: 56)
        panel.setFrame(bannerFrame(size: size), display: true, animate: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        bannerPanel = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let dismiss = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel, panel === self.bannerPanel else { return }
            self.dismiss(panel)
        }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: dismiss)
    }

    private func bannerFrame(size: NSSize) -> NSRect {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: size.width + 32, height: size.height + 32)
        return NSRect(
            x: frame.maxX - size.width,
            y: frame.maxY - size.height - 16,
            width: size.width,
            height: size.height
        )
    }

    private func openCodexTask(threadID: String) {
        dismissWorkItem?.cancel()
        if let panel = bannerPanel {
            dismiss(panel)
        }

        if let taskURL = CodexTaskLink.url(threadID: threadID), workspace.openURL(taskURL) {
            return
        }
        _ = workspace.openApplication(bundleIdentifier: CodexTaskLink.bundleIdentifier)
    }

    private func dismiss(_ panel: NSPanel) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        bannerPanel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
        })
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CodexCompletionBanner: View {
    let taskTitle: String
    let openTask: () -> Void

    var body: some View {
        Button(action: openTask) {
            HStack(spacing: 11) {
                ZStack {
                    LeafBadgeShape()
                        .fill(junimoAccent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(junimoPanelBlack)
                }
                .frame(width: 31, height: 31)

                VStack(alignment: .leading, spacing: 4) {
                    Text("任务完成")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(taskTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(junimoAccent.opacity(0.78))
            }
            .padding(.leading, 13)
            .padding(.trailing, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.97), junimoPanelBlack.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RightEdgeBannerShape()
        )
        .overlay {
            RightEdgeBannerShape()
                .strokeBorder(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

// RightEdgeBannerShape 让提示条贴住屏幕右边，仅保留左侧圆角。
private struct RightEdgeBannerShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(15, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> RightEdgeBannerShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// LeafBadgeShape 用一个不对称圆角提示 Junimo 的叶片意象。
private struct LeafBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let largeRadius = min(10, rect.width / 2, rect.height / 2)
        let smallRadius: CGFloat = 4
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + largeRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - largeRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + largeRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - largeRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - largeRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + smallRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - smallRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + largeRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + largeRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
