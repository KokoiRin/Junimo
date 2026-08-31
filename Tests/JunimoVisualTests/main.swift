import AppKit
import JunimoCore
import SwiftUI

func fail(_ message: String) -> Never {
    fputs("Visual test failed: \(message)\n", stderr)
    exit(1)
}

final class VisualFakeWorkspace: QuickLaunchOpening {
    func openApplication(bundleIdentifier: String) -> Bool { true }
    func openURL(_ url: URL) -> Bool { true }
}

// 展开真实 companion 时中心必须不透明，且仅底部两个圆角外侧保持透明。
@MainActor
func testExpandedPanelKeepsRoundedCornersTransparent() {
    let hostSize = CGSize(width: 640, height: 380)
    let panelSize = CGSize(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
    let panelOrigin = CGPoint(
        x: (hostSize.width - panelSize.width) / 2,
        y: (hostSize.height - panelSize.height) / 2
    )
    let state = ShellState()
    state.pointerEntered()
    let view = ZStack {
        Color.clear
        JunimoSurfaceView(
            state: state,
            launcher: QuickLauncher(workspace: VisualFakeWorkspace())
        )
    }
    .frame(width: hostSize.width, height: hostSize.height)
    let bitmap = render(view, size: hostSize)

    let centerAlpha = alpha(bitmap, at: CGPoint(x: hostSize.width / 2, y: hostSize.height / 2), size: hostSize)
    guard centerAlpha > 0.95 else {
        fail("expanded panel center should be opaque, alpha was \(centerAlpha)")
    }

    let inset: CGFloat = 3
    let corners = [
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + panelSize.height - inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + panelSize.height - inset)
    ]
    let transparent = corners.filter { alpha(bitmap, at: $0, size: hostSize) < 0.02 }
    guard transparent.count == 2 else {
        fail("exactly two rounded corners should be transparent")
    }
}

// 单一 companion 面板应绘制足量可见内容和绿色强调元素，防止布局退化为空壳或全透明表面。
@MainActor
func testCompanionRendersVisibleAccentContent() {
    let size = CGSize(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
    let state = ShellState()
    state.pointerEntered()
    let bitmap = render(
        JunimoSurfaceView(
            state: state,
            launcher: QuickLauncher(workspace: VisualFakeWorkspace())
        ).frame(width: size.width, height: size.height),
        size: size
    )

    var accentPixels = 0
    var visiblePixels = 0
    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            guard let source = bitmap.colorAt(x: x, y: y),
                  let color = source.usingColorSpace(.deviceRGB) else { continue }
            if color.greenComponent > 0.70 && color.redComponent < 0.55 {
                accentPixels += 1
            }
            if color.alphaComponent > 0.9 && max(color.redComponent, color.greenComponent, color.blueComponent) > 0.08 {
                visiblePixels += 1
            }
        }
    }
    guard accentPixels > 20 else { fail("companion should render green activity and shortcut accents") }
    guard visiblePixels > 100 else { fail("companion should render visible usage and shortcut content") }
}

// 轻量面板的标题和说明文字应维持清晰字号下限。
func testCompanionKeepsReadableTypography() {
    guard JunimoTypography.pageTitle >= 22 else { fail("title should remain at least 22pt") }
    guard JunimoTypography.caption >= 12 else { fail("caption should remain at least 12pt") }
}

// 折叠态应在中央刘海触发区两侧分别画出 Junimo 图标和用量胶囊，中央区域保持视觉透明。
@MainActor
func testCollapsedControlsKeepNotchTriggerClear() {
    let size = CGSize(width: JunimoPanelLayout.collapsedWidth, height: 33)
    let state = ShellState()
    let bitmap = render(
        JunimoSurfaceView(state: state, launcher: QuickLauncher(workspace: VisualFakeWorkspace()))
            .frame(width: size.width, height: size.height),
        size: size
    )
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    let leftEnd = Int(JunimoPanelLayout.collapsedCapsuleLaneWidth * scale)
    let rightStart = Int(
        (JunimoPanelLayout.collapsedCapsuleLaneWidth + JunimoPanelLayout.collapsedNotchClearance * 2) * scale
    )
    var leftVisible = 0
    var centerVisible = 0
    var rightVisible = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.60 else { continue }
            if x < leftEnd {
                leftVisible += 1
            } else if x < rightStart {
                centerVisible += 1
            } else {
                rightVisible += 1
            }
        }
    }
    guard leftVisible > 20 else { fail("collapsed shell should render the Junimo launcher icon") }
    guard rightVisible > 20 else { fail("collapsed shell should render the usage capsule") }
    guard centerVisible == 0 else { fail("the notch hover trigger should remain visually transparent") }
}

@MainActor
func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.wantsLayer = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        fail("could not allocate offscreen bitmap")
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    return bitmap
}

func alpha(_ bitmap: NSBitmapImageRep, at point: CGPoint, size: CGSize) -> CGFloat {
    let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x * CGFloat(bitmap.pixelsWide) / size.width)))
    let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y * CGFloat(bitmap.pixelsHigh) / size.height)))
    return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
}

Task { @MainActor in
    testExpandedPanelKeepsRoundedCornersTransparent()
    testCompanionRendersVisibleAccentContent()
    testCompanionKeepsReadableTypography()
    testCollapsedControlsKeepNotchTriggerClear()
    print("Junimo companion visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
