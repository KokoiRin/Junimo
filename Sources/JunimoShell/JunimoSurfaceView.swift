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
                    Circle().stroke(UsageRingPalette.antigravity.idle.opacity(0.38), lineWidth: 2)
                    if state.surfaceState.antigravity?.isWorking == true {
                        WorkingQuotaArc(fraction: 0.35, palette: .antigravity)
                    }
                }
            }
        }
        .frame(width: 12, height: 12)
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
        HStack(spacing: 12) {
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
            Circle().stroke(.white.opacity(0.12), lineWidth: 2)
            if usage.status == .available, let remaining = usage.primary?.remainingPercent {
                let fraction = CGFloat(min(100, max(0, remaining))) / 100
                if working {
                    WorkingQuotaArc(fraction: fraction, palette: palette)
                } else if fraction > 0 {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(palette.idle, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                if working { WorkingQuotaArc(fraction: 0, palette: palette) }
                Text(usage.status == .loading ? "·" : "—")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(statusColor(usage, accent: palette.idle))
            }
        }
        .frame(width: 12, height: 12)
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

// UsageRingPalette 为每个 Agent 定义正常主色与运行态等宽弧头高光，整条剩余弧保持正常亮度与 2pt 等宽质感。
private struct UsageRingPalette {
    let idle: Color
    let workingHead: Color

    static let codex = UsageRingPalette(
        idle: junimoAccent,
        workingHead: Color(red: 0.60, green: 0.86, blue: 0.71)
    )
    static let grok = UsageRingPalette(
        idle: Color(red: 0.84, green: 0.72, blue: 0.42),
        workingHead: Color(red: 0.91, green: 0.81, blue: 0.56)
    )
    static let antigravity = UsageRingPalette(
        idle: Color(red: 0.68, green: 0.58, blue: 0.82),
        workingHead: Color(red: 0.80, green: 0.71, blue: 0.90)
    )
}

private struct WorkingQuotaArc: View {
    let fraction: CGFloat
    let palette: UsageRingPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        let gradient = AngularGradient(
            stops: [
                .init(color: palette.idle, location: 0),
                .init(color: palette.idle, location: 0.73),
                .init(color: palette.workingHead, location: 0.94)
            ],
            center: .center,
            startAngle: .zero,
            endAngle: .degrees(360 * fraction)
        )
        ZStack {
            if fraction > 0 {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                // 零额度或无读数时，用沿环移动的点表示工作，中心仍显示原来的额度状态。
                GeometryReader { geometry in
                    Circle().fill(palette.workingHead)
                        .frame(width: 2, height: 2)
                        .position(x: geometry.size.width, y: geometry.size.height / 2)
                }
            }
        }
        .rotationEffect(.degrees(spinning && !reduceMotion ? 270 : -90))
        .animation(reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false),
                   value: spinning && !reduceMotion)
        .onAppear { spinning = true }
    }
}
