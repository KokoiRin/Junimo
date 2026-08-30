import JunimoCore
import SwiftUI

// JunimoSurfaceView 在折叠 Codex 摘要与展开 companion 面板之间切换。
struct JunimoSurfaceView: View {
    @ObservedObject var state: ShellState
    private let launcher: QuickLauncher

    init(
        state: ShellState,
        launcher: QuickLauncher = QuickLauncher(workspace: MacQuickLaunchWorkspace())
    ) {
        self.state = state
        self.launcher = launcher
    }

    var body: some View {
        Group {
            if state.isExpanded {
                expanded
            } else {
                collapsed
            }
        }
        .onHover { inside in
            inside ? state.pointerEntered() : state.pointerExited()
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
                usageCard
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 18)

            Text("快速打开")
                .font(.system(size: JunimoTypography.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                ForEach(QuickLaunchCatalog.commands) { command in
                    shortcutButton(command)
                }
            }
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

    private var usageCard: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Codex 剩余用量")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Text(state.surfaceState.codex.compactSummary)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(codexStatusColor)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
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

    // collapsed 在刘海两侧分别展示 activity 身份与主用量窗口。
    private var collapsed: some View {
        HStack(spacing: 0) {
            activityCapsule
                .frame(width: JunimoPanelLayout.collapsedCapsuleLaneWidth, alignment: .trailing)
            Color.clear
                .frame(width: JunimoPanelLayout.collapsedNotchClearance * 2)
            codexUsageCapsule
                .frame(width: JunimoPanelLayout.collapsedCapsuleLaneWidth, alignment: .leading)
        }
        .frame(width: JunimoPanelLayout.collapsedWidth)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
    }

    private var activityCapsule: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(activityColor)
                .frame(width: 7, height: 7)
            Text("Codex")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(capsuleBackground, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 2)
    }

    private var codexUsageCapsule: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: codexProgressFraction)
                    .stroke(codexStatusColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text(state.surfaceState.codex.compactSummary)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(capsuleBackground, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 2)
    }

    private var capsuleBackground: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.94), junimoPanelBlack.opacity(0.90)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var activitySummary: String {
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

    private var codexStatusColor: Color {
        switch state.surfaceState.codex.status {
        case .available: return junimoAccent
        case .unavailable: return .orange
        case .loading: return .white.opacity(0.36)
        }
    }

    private var codexProgressFraction: CGFloat {
        guard state.surfaceState.codex.status == .available,
              let remaining = state.surfaceState.codex.primary?.remainingPercent else {
            return 0
        }
        return CGFloat(min(100, max(0, remaining))) / 100
    }
}
