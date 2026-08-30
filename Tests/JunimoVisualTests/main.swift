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

// 折叠态 activity 和用量胶囊应围绕刘海保持对称净空。
@MainActor
func testCollapsedCapsulesStaySymmetric() {
    let size = CGSize(width: JunimoPanelLayout.collapsedWidth, height: 33)
    let state = ShellState()
    let bitmap = render(
        JunimoSurfaceView(state: state, launcher: QuickLauncher(workspace: VisualFakeWorkspace()))
            .frame(width: size.width, height: size.height),
        size: size
    )
    let centerRow = bitmap.pixelsHigh / 2
    let solid = (0..<bitmap.pixelsWide).filter {
        (bitmap.colorAt(x: $0, y: centerRow)?.alphaComponent ?? 0) > 0.60
    }
    var ranges: [ClosedRange<Int>] = []
    for x in solid {
        if let last = ranges.last, x <= last.upperBound + 1 {
            ranges[ranges.count - 1] = last.lowerBound...x
        } else {
            ranges.append(x...x)
        }
    }
    let scale = CGFloat(bitmap.pixelsWide) / size.width
    let capsules = ranges.filter { CGFloat($0.count) / scale > 30 }
    guard capsules.count == 2 else { fail("collapsed shell should render two capsules, got \(capsules)") }
    let leftInner = CGFloat(capsules[0].upperBound + 1) / scale
    let rightInner = CGFloat(capsules[1].lowerBound) / scale
    let center = size.width / 2
    guard abs((center - leftInner) - (rightInner - center)) <= 1.5 else {
        fail("capsule inner edges should remain symmetric")
    }
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
    testCollapsedCapsulesStaySymmetric()
    print("Junimo companion visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
