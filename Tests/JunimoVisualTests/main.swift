import AppKit
import JunimoCore
import SwiftUI

// fail 终止离屏视觉测试并输出可定位的失败原因。
func fail(_ message: String) -> Never {
    fputs("Visual test failed: \(message)\n", stderr)
    exit(1)
}

// 在 500×300 透明画布中离屏展开真实 420×236 面板时，面板中心应完全不透明，只有两个底部圆角外侧保持透明，任何重新引入的阴影都应使测试失败。
@MainActor
func testExpandedPanelKeepsRoundedCornersTransparent() {
    let hostSize = CGSize(width: 500, height: 300)
    let panelSize = CGSize(width: 420, height: 236)
    let panelOrigin = CGPoint(
        x: (hostSize.width - panelSize.width) / 2,
        y: (hostSize.height - panelSize.height) / 2
    )

    let state = ShellState()
    state.pointerEntered()
    let rootView = ZStack {
        Color.clear
        JunimoSurfaceView(state: state)
    }
    .frame(width: hostSize.width, height: hostSize.height)

    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = NSRect(origin: .zero, size: hostSize)
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor

    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    window.displayIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        fail("could not allocate an offscreen bitmap")
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    let xScale = CGFloat(bitmap.pixelsWide) / hostSize.width
    let yScale = CGFloat(bitmap.pixelsHigh) / hostSize.height
    // alpha 将逻辑坐标映射到离屏位图并读取最终透明度。
    func alpha(at point: CGPoint) -> CGFloat {
        let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x * xScale)))
        let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y * yScale)))
        return bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    // 画布中心位于黑色面板内部，alpha 必须接近 1，先排除“整个视图没有成功渲染”的假阳性。
    let centerAlpha = alpha(at: CGPoint(x: hostSize.width / 2, y: hostSize.height / 2))
    guard centerAlpha > 0.95 else {
        fail("expanded panel center should be opaque, alpha was \(centerAlpha)")
    }

    // 在四个包围盒角内缩 3pt 采样时，顶部直角应不透明、底部两个 22pt 圆角外侧应透明，因此透明点必须恰好为两个。
    let inset: CGFloat = 3
    let cornerPoints = [
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + inset),
        CGPoint(x: panelOrigin.x + inset, y: panelOrigin.y + panelSize.height - inset),
        CGPoint(x: panelOrigin.x + panelSize.width - inset, y: panelOrigin.y + panelSize.height - inset)
    ]
    let transparentCorners = cornerPoints.filter { alpha(at: $0) < 0.02 }
    guard transparentCorners.count == 2 else {
        let alphas = cornerPoints.map { alpha(at: $0) }
        fail("exactly the two rounded corners should be transparent; corner alphas were \(alphas)")
    }
}

Task { @MainActor in
    testExpandedPanelKeepsRoundedCornersTransparent()
    print("Junimo expanded panel visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
