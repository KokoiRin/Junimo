import AppKit
import JunimoCore
import SwiftUI

// JunimoPage 是展开壳层的本地导航状态，不进入 Go 产品协议。
enum JunimoPage: Equatable {
    case focus
    case todo
}

// JunimoSurfaceView 在折叠双胶囊与展开多页面容器之间切换。
struct JunimoSurfaceView: View {
    @ObservedObject var state: ShellState
    @State private var selectedPage: JunimoPage

    // 初始页面参数仅决定壳层呈现，便于离屏测试 Todo 页面而不伪造后端导航状态。
    init(state: ShellState, initialPage: JunimoPage = .focus) {
        self.state = state
        _selectedPage = State(initialValue: initialPage)
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

    // expanded 将稳定导航栏与当前页面并列，页面切换不会触发任何 Go 意图。
    private var expanded: some View {
        HStack(spacing: 0) {
            JunimoNavigationRail(state: state, selectedPage: $selectedPage)
                .frame(width: 136)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            Group {
                switch selectedPage {
                case .focus:
                    FocusPage(state: state)
                case .todo:
                    TodoPage(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: JunimoPanelLayout.expandedWidth, height: JunimoPanelLayout.expandedHeight)
        .foregroundStyle(.white.opacity(0.92))
        .background(JunimoPanelBackground())
        .overlay(
            TopAttachedPanelShape(bottomRadius: 22)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(TopAttachedPanelShape(bottomRadius: 22))
    }

    // collapsed 保留原有左右双胶囊，展开导航不会改变菜单栏常驻形态。
    private var collapsed: some View {
        HStack(spacing: 0) {
            focusCapsule
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

    // focusCapsule 展示 Go 番茄钟的当前剩余时间。
    private var focusCapsule: some View {
        HStack(spacing: 8) {
            JunimoAppIcon()
                .frame(width: 20, height: 20)
            Text(timeText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(height: 28)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.94), junimoPanelBlack.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 0)
    }

    // codexUsageCapsule 展示 Go 汇总的主用量窗口。
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

            Text(state.surfaceState.codex?.compactSummary ?? "…")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.92), junimoPanelBlack.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.24), radius: 2, x: 0, y: 0)
    }

    // timeText 把后端秒数格式化为稳定的两位分钟与秒。
    private var timeText: String {
        let remaining = max(0, state.surfaceState.pomodoro.remainingSeconds)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    // codexStatusColor 用颜色区分用量事实的可用状态。
    private var codexStatusColor: Color {
        switch state.surfaceState.codex?.status {
        case .available:
            return junimoAccent
        case .unavailable:
            return .orange
        case .loading, nil:
            return .white.opacity(0.36)
        }
    }

    // codexProgressFraction 把后端百分比限制到圆环可绘制范围。
    private var codexProgressFraction: CGFloat {
        guard state.surfaceState.codex?.status == .available,
              let remaining = state.surfaceState.codex?.primary?.remainingPercent else {
            return 0
        }
        return CGFloat(min(100, max(0, remaining))) / 100
    }
}
