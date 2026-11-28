import JunimoCore
import SwiftUI

// JunimoSurfaceView 在折叠用量圆环与展开 companion 面板之间切换。
@MainActor
struct JunimoSurfaceView: View {
    @ObservedObject var state: ShellState
    @ObservedObject var quickLaunchStore: QuickLaunchConfigurationStore
    var notchClearance: CGFloat = JunimoPanelLayout.collapsedNotchClearance
    private let launcher: QuickLauncher

    init(
        state: ShellState,
        launcher: QuickLauncher = QuickLauncher(workspace: MacQuickLaunchWorkspace())
    ) {
        self.state = state
        self.quickLaunchStore = QuickLaunchConfigurationStore()
        self.launcher = launcher
    }

    init(
        state: ShellState,
        quickLaunchStore: QuickLaunchConfigurationStore,
        launcher: QuickLauncher = QuickLauncher(workspace: MacQuickLaunchWorkspace())
    ) {
        self.state = state
        self.quickLaunchStore = quickLaunchStore
        self.launcher = launcher
    }

    var body: some View {
        if state.isExpanded {
            expanded
                .onHover { inside in
                    inside ? state.pointerEntered() : state.pointerExited()
                }
        } else {
            collapsed
        }
    }

    // expanded 直接呈现用量、最近完成与快捷入口，不保留功能页导航。
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                JunimoAppIcon()
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Junimo")
                        .font(.system(size: JunimoTypography.pageTitle, weight: .semibold))
                    Text(activitySummary)
                        .font(.system(size: JunimoTypography.caption, weight: .medium))
                        .foregroundStyle(activityColor.opacity(0.78))
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 8) {
                    if state.surfaceState.showsCodex {
                        usageCard("Codex", usage: state.surfaceState.codex, palette: .codex, working: codexWorking)
                    }
                    if state.surfaceState.showsGrok {
                        usageCard("Grok Bot", usage: state.surfaceState.grok, palette: .grok)
                    }
                }
                .layoutPriority(1)
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 18)

            HStack(spacing: 8) {
                Text("快速打开")
                    .font(.system(size: JunimoTypography.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.46))
                if let error = quickLaunchStore.lastErrorDescription {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.9))
                        .help(error)
                }
                Spacer()
                if state.surfaceState.showsAntigravity {
                    antigravityRing
                    Text(antigravitySummary)
                        .font(.system(size: JunimoTypography.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.bottom, 10)

            shortcutRow
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
        .foregroundStyle(.white.opacity(0.92))
        .background(JunimoPanelBackground())
        .overlay(
            TopAttachedPanelShape(bottomRadius: 22)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(TopAttachedPanelShape(bottomRadius: 22))
        .accessibilityIdentifier("companion.surface")
    }

    @ViewBuilder
    private var shortcutRow: some View {
        if quickLaunchStore.commands.count <= 4 {
            HStack(spacing: 10) {
                ForEach(quickLaunchStore.commands) { command in
                    shortcutButton(command)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(quickLaunchStore.commands) { command in
                        shortcutButton(command)
                            .frame(width: 112)
                    }
                }
            }
            .frame(height: 74)
        }
    }

    private var antigravitySummary: String {
        let activity = state.surfaceState.antigravity?.isWorking.map { $0 ? "正在工作" : "空闲" } ?? "状态未知"
        let weekly = state.surfaceState.antigravity?.weeklyQuota
        let remaining = weekly?.primary == nil ? "未知" : weekly?.compactSummary ?? "未知"
        return "Antigravity " + activity + " · Gemini 周额度剩余 " + remaining
    }

    private var antigravityRing: some View {
        Group {
            if let weekly = state.surfaceState.antigravity?.weeklyQuota, weekly.status == .available {
                usageRing(weekly, palette: .antigravity, working: state.surfaceState.antigravity?.isWorking == true)
            } else {
                ZStack {
                    Circle().strokeBorder(UsageRingPalette.antigravity.idle.opacity(0.38), lineWidth: ringStroke)
                    if state.surfaceState.antigravity?.isWorking == true {
                        WorkingQuotaArc(fraction: 0.35, palette: .antigravity)
                    }
                }
            }
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .help(antigravitySummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(antigravitySummary)
    }

    private var codexWorking: Bool { state.surfaceState.activity.isWorking == true }

    private func usageCard(_ name: String, usage: CodexUsageSnapshot, palette: UsageRingPalette, working: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(name) 剩余")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            HStack(spacing: 7) {
                usageRing(usage, palette: palette, working: working)
                Text(usage.compactSummary)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(statusColor(usage, accent: palette.idle))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .help(usageHelp(name, usage: usage, working: working))
    }

    private func shortcutButton(_ command: QuickLaunchCommand) -> some View {
        Button {
            _ = launcher.open(command)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(junimoAccent)
                Text(command.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shortcut.\(command.id)")
    }

    private var collapsed: some View {
        let laneWidth = JunimoPanelLayout.collapsedCapsuleLaneWidth(
            showsCodex: state.surfaceState.showsCodex,
            showsGrok: state.surfaceState.showsGrok,
            showsAntigravity: state.surfaceState.showsAntigravity
        )
        return HStack(spacing: 0) {
            if state.surfaceState.visibleAgentRingCount > 0 {
                agentUsageCapsule
                    .frame(width: laneWidth, alignment: .trailing)
            }
            notchHoverTrigger
        }
        .frame(width: laneWidth + notchClearance * 2)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                state.pointerEntered()
            }
        }
    }

    private var notchHoverTrigger: some View {
        Color.black.opacity(0.001)
            .frame(width: notchClearance * 2)
            .contentShape(Rectangle())
            .accessibilityIdentifier("notch.expandTrigger")
    }

    private var agentUsageCapsule: some View {
        HStack(spacing: 8) {
            if state.surfaceState.showsCodex {
                compactUsage(name: "Codex", usage: state.surfaceState.codex, palette: .codex, working: codexWorking)
            }
            if state.surfaceState.showsGrok {
                compactUsage(name: "Grok Bot", usage: state.surfaceState.grok, palette: .grok)
            }
            if state.surfaceState.showsAntigravity { antigravityRing }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(junimoSurfaceFill, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 2)
    }

    private func compactUsage(name: String, usage: CodexUsageSnapshot, palette: UsageRingPalette, working: Bool = false) -> some View {
        usageRing(usage, palette: palette, working: working)
            .help(usageHelp(name, usage: usage, working: working))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)\(working ? " 正在工作，" : " ")剩余用量 \(usage.compactSummary)")
            .accessibilityIdentifier("usage.\(name)")
    }

    private func usageRing(_ usage: CodexUsageSnapshot, palette: UsageRingPalette, working: Bool) -> some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: ringStroke)
            if usage.status == .available, let remaining = usage.primary?.remainingPercent {
                let fraction = CGFloat(min(100, max(0, remaining))) / 100
                if working {
                    WorkingQuotaArc(fraction: fraction, palette: palette)
                } else if fraction > 0 {
                    Circle().inset(by: ringStroke / 2)
                        .trim(from: 0, to: fraction)
                        .stroke(palette.idle, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                if working { WorkingQuotaArc(fraction: 0, palette: palette) }
                Text(usage.status == .loading ? "·" : "—")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(statusColor(usage, accent: palette.idle))
            }
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    private func statusColor(_ usage: CodexUsageSnapshot, accent: Color) -> Color {
        switch usage.status {
        case .available: return accent
        case .unavailable: return .orange
        case .loading: return .white.opacity(0.36)
        }
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private func usageHelp(_ name: String, usage: CodexUsageSnapshot, working: Bool) -> String {
        var text = "\(name) 剩余用量：\(usage.compactSummary)"
        if working { text += "\n正在工作" }
        if let message = usage.message { text += "\n" + message }
        if let timestamp = usage.refreshedAt, let date = Self.iso8601Formatter.date(from: timestamp) {
            text += "\n更新于 " + date.formatted(date: .abbreviated, time: .shortened)
        }
        return text
    }

    private var activitySummary: String {
        if codexWorking { return "Codex 正在工作" }
        switch state.surfaceState.activity.status {
        case .loading:
            return "正在连接 Codex 任务"
        case .unavailable:
            return "任务提醒暂不可用"
        case .available:
            if let event = state.surfaceState.activity.completionEvent {
                return "最近完成：\(event.title)"
            }
            return "任务完成后会用特别声音提醒你"
        }
    }

    private var activityColor: Color {
        switch state.surfaceState.activity.status {
        case .available: return junimoAccent
        case .unavailable: return .orange
        case .loading: return .white.opacity(0.36)
        }
    }

}

private let ringDiameter: CGFloat = 16
private let ringStroke: CGFloat = 2.5

struct UsageRingPalette {
    let idle: Color
    let workingHead: Color

    static let codex = UsageRingPalette(
        idle: Color(red: 0.27, green: 0.755, blue: 0.49),
        workingHead: Color(red: 0.68, green: 0.93, blue: 0.78)
    )
    static let grok = UsageRingPalette(
        idle: Color(red: 0.80, green: 0.68, blue: 0.36),
        workingHead: Color(red: 0.95, green: 0.86, blue: 0.62)
    )
    static let antigravity = UsageRingPalette(
        idle: Color(red: 0.70, green: 0.62, blue: 0.83),
        workingHead: Color(red: 0.86, green: 0.76, blue: 0.96)
    )
}

private struct WorkingQuotaArc: View {
    let fraction: CGFloat
    let palette: UsageRingPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        RotatingQuotaStroke(fraction: fraction, palette: palette, degrees: spinning && !reduceMotion ? 270 : -90)
            .animation(reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false),
                       value: spinning && !reduceMotion)
            .onAppear { spinning = true }
    }
}

// 在固定画布中沿圆周移动起点，避免旋转已栅格化的小圆环时反复采样边缘。
struct RotatingQuotaStroke: View, Animatable {
    let fraction: CGFloat
    let palette: UsageRingPalette
    var degrees: Double

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = (min(size.width, size.height) - ringStroke) / 2
            let start = Angle.degrees(degrees)
            let end = Angle.degrees(degrees + 360 * fraction)
            func point(at angle: Angle) -> CGPoint {
                CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
            }
            let tip = point(at: end)
            guard fraction > 0 else {
                let dot = CGRect(x: tip.x - ringStroke / 2, y: tip.y - ringStroke / 2, width: ringStroke, height: ringStroke)
                context.fill(Path(ellipseIn: dot), with: .color(palette.workingHead))
                return
            }

            let style = StrokeStyle(lineWidth: ringStroke, lineCap: .round)
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(arc, with: .color(palette.idle), style: style)

            // 只在前端短弧内沿弦渐变，尾部圆角始终取弧身色。
            let headStart = Angle.degrees(end.degrees - min(54, 90 * fraction))
            var head = Path()
            head.addArc(center: center, radius: radius, startAngle: headStart, endAngle: end, clockwise: false)
            let highlight = Gradient(stops: [
                .init(color: palette.idle, location: 0),
                .init(color: palette.workingHead, location: 0.8)
            ])
            context.stroke(head, with: .linearGradient(highlight, startPoint: point(at: headStart), endPoint: tip), style: style)
        }
    }
}
