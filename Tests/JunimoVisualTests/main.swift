import AppKit
import JunimoCore
import SwiftUI

// fail 终止离屏视觉测试并输出可定位的失败原因。
func fail(_ message: String) -> Never {
    fputs("Visual test failed: \(message)\n", stderr)
    exit(1)
}

// 在 640×380 透明画布中离屏展开真实 640×380 多页面面板时，中心应不透明且只有两个底部圆角外侧透明。
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

// Todo 被指定为初始本地页面时，离屏结果应同时绘制左侧导航选中强调色与右侧 Todo 内容，证明页面切换容器不是空占位。
@MainActor
func testTodoPageRendersNavigationAndContent() {
    let hostSize = CGSize(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
    let state = ShellState()
    state.pointerEntered()
    let hostingView = NSHostingView(
        rootView: JunimoSurfaceView(state: state, initialPage: .todo)
            .frame(width: hostSize.width, height: hostSize.height)
    )
    hostingView.frame = NSRect(origin: .zero, size: hostSize)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        fail("could not allocate Todo page bitmap")
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    var accentPixels = 0
    var contentPixels = 0
    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            guard let source = bitmap.colorAt(x: x, y: y),
                  let color = source.usingColorSpace(.deviceRGB) else { continue }
            if color.greenComponent > 0.70 && color.redComponent < 0.55 {
                accentPixels += 1
            }
            let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
            if x > bitmap.pixelsWide / 3 && color.alphaComponent > 0.9 && brightness > 0.08 {
                contentPixels += 1
            }
        }
    }
    guard accentPixels > 10 else {
        fail("Todo navigation selection should render the accent treatment")
    }
    guard contentPixels > 10 else {
        fail("Todo page should render visible controls in the right content area")
    }
}

// 多页面面板采用中文高密度工具布局时，页标题、导航、正文和说明文字都应保持明确字号下限，避免再次退化为难读小字。
@MainActor
func testExpandedPanelKeepsReadableTypographyHierarchy() {
    guard JunimoTypography.pageTitle >= 22 else {
        fail("page title should remain at least 22pt")
    }
    guard JunimoTypography.navigation >= 15 else {
        fail("navigation should remain at least 15pt")
    }
    guard JunimoTypography.body >= 14 else {
        fail("body text should remain at least 14pt")
    }
    guard JunimoTypography.caption >= 12 else {
        fail("caption text should remain at least 12pt")
    }
}

// 折叠态两颗不同宽度胶囊围绕刘海显示时，内边缘应到中心等距、保持约 204pt 净空，且阴影后的上下视觉留白近似相等。
@MainActor
func testCollapsedCapsulesStaySymmetricAndVerticallyBalanced() {
    let hostSize = CGSize(width: JunimoPanelLayout.collapsedWidth, height: 33)
    let state = ShellState()
    let hostingView = NSHostingView(
        rootView: JunimoSurfaceView(state: state)
            .frame(width: hostSize.width, height: hostSize.height)
    )
    hostingView.frame = NSRect(origin: .zero, size: hostSize)
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        fail("could not allocate collapsed panel bitmap")
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    let xScale = CGFloat(bitmap.pixelsWide) / hostSize.width
    let yScale = CGFloat(bitmap.pixelsHigh) / hostSize.height
    let centerRow = bitmap.pixelsHigh / 2
    let solidXs = (0..<bitmap.pixelsWide).filter { x in
        (bitmap.colorAt(x: x, y: centerRow)?.alphaComponent ?? 0) > 0.60
    }
    var ranges: [ClosedRange<Int>] = []
    for x in solidXs {
        if let last = ranges.last, x <= last.upperBound + 1 {
            ranges[ranges.count - 1] = last.lowerBound...x
        } else {
            ranges.append(x...x)
        }
    }
    let capsuleRanges = ranges.filter { CGFloat($0.count) / xScale > 30 }
    guard capsuleRanges.count == 2 else {
        fail("collapsed panel should render two opaque capsule ranges, got \(capsuleRanges)")
    }

    let leftInnerEdge = CGFloat(capsuleRanges[0].upperBound + 1) / xScale
    let rightInnerEdge = CGFloat(capsuleRanges[1].lowerBound) / xScale
    let centerX = hostSize.width / 2
    let leftDistance = centerX - leftInnerEdge
    let rightDistance = rightInnerEdge - centerX
    guard abs(leftDistance - rightDistance) <= 1.5 else {
        fail("capsule inner distances should be symmetric, got \(leftDistance) and \(rightDistance)")
    }
    let centerGap = rightInnerEdge - leftInnerEdge
    guard 200...208 ~= centerGap else {
        fail("capsules should keep a near-but-separated notch gap, got \(centerGap)")
    }

    let leftSampleX = (capsuleRanges[0].lowerBound + capsuleRanges[0].upperBound) / 2
    let visibleYs = (0..<bitmap.pixelsHigh).filter { y in
        (bitmap.colorAt(x: leftSampleX, y: y)?.alphaComponent ?? 0) > 0.02
    }
    guard let firstY = visibleYs.first, let lastY = visibleYs.last else {
        fail("left capsule should have visible vertical pixels")
    }
    let firstGap = CGFloat(firstY) / yScale
    let secondGap = hostSize.height - CGFloat(lastY + 1) / yScale
    guard abs(firstGap - secondGap) <= 1.5 else {
        fail("capsule visual vertical gaps should be balanced, got \(firstGap) and \(secondGap)")
    }
}

Task { @MainActor in
    testExpandedPanelKeepsRoundedCornersTransparent()
    testTodoPageRendersNavigationAndContent()
    testExpandedPanelKeepsReadableTypographyHierarchy()
    testCollapsedCapsulesStaySymmetricAndVerticallyBalanced()
    print("Junimo expanded panel visual regression tests passed")
    exit(0)
}
RunLoop.main.run()
