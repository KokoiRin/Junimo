import JunimoCore
import SwiftUI

// FocusPage 渲染 Go 番茄钟快照并发送类型化番茄钟意图。
struct FocusPage: View {
    @ObservedObject var state: ShellState
    @State private var selectedFocusDuration = 25 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("专注")
                        .font(.system(size: JunimoTypography.pageTitle, weight: .semibold))
                    Text("专注当下，一次只做一件事")
                        .font(.system(size: JunimoTypography.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                statusBadge
            }

            Spacer(minLength: 12)

            Text(timeText)
                .font(.system(size: 68, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.96))
            Text(statusText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.top, 3)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                actionControls
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .onAppear { selectedFocusDuration = snapshot.focusDurationSeconds }
        .onChange(of: snapshot.focusDurationSeconds) { _, value in
            selectedFocusDuration = value
        }
        .accessibilityIdentifier("page.focus")
    }

    // statusBadge 显示 Go 当前模式，不承担状态推导。
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(snapshot.mode == .focus ? "专注" : "休息")
                .font(.system(size: JunimoTypography.caption, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // actionControls 按后端状态选择当前可发送的用户动作。
    @ViewBuilder
    private var actionControls: some View {
        switch (snapshot.mode, snapshot.status) {
        case (.focus, .idle), (.rest, .idle):
            HStack(spacing: 6) {
                durationButton(minutes: 15)
                durationButton(minutes: 25)
                durationButton(minutes: 45)
            }
            Button { state.startFocus(durationSeconds: selectedFocusDuration) } label: {
                Label("开始", systemImage: "play.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))
        case (.focus, .running):
            Button { state.pausePomodoro() } label: { Label("暂停", systemImage: "pause.fill") }
                .buttonStyle(JunimoButtonStyle(tone: .primary))
            resetButton
        case (.focus, .paused):
            Button { state.resumePomodoro() } label: { Label("继续", systemImage: "play.fill") }
                .buttonStyle(JunimoButtonStyle(tone: .primary))
            resetButton
        case (.focus, .completed):
            Button { state.startBreak() } label: { Label("开始休息", systemImage: "cup.and.saucer.fill") }
                .buttonStyle(JunimoButtonStyle(tone: .primary))
            Button { state.startFocus(durationSeconds: snapshot.focusDurationSeconds) } label: {
                Label("再来一轮", systemImage: "repeat")
            }
            .buttonStyle(JunimoButtonStyle())
            resetButton
        case (.rest, .running), (.rest, .paused):
            if snapshot.status == .paused {
                Button { state.resumePomodoro() } label: { Label("继续", systemImage: "play.fill") }
                    .buttonStyle(JunimoButtonStyle(tone: .primary))
            }
            Button { state.skipBreak() } label: { Label("跳过休息", systemImage: "forward.fill") }
                .buttonStyle(JunimoButtonStyle(tone: .primary))
            resetButton
        case (.rest, .completed):
            Button { state.startFocus(durationSeconds: snapshot.focusDurationSeconds) } label: {
                Label("开始专注", systemImage: "play.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))
            resetButton
        }
    }

    // durationButton 修改尚未提交的专注时长选择。
    private func durationButton(minutes: Int) -> some View {
        let seconds = minutes * 60
        let selected = selectedFocusDuration == seconds
        return Button { selectedFocusDuration = seconds } label: {
            Text("\(minutes) 分")
                .font(.system(size: JunimoTypography.body, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.black.opacity(0.88) : Color.white.opacity(0.72))
                .frame(width: 54, height: 38)
                .background(
                    selected ? junimoAccent : Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // resetButton 提供各运行状态共享的重置动作。
    private var resetButton: some View {
        Button { state.resetPomodoro() } label: { Label("重置", systemImage: "arrow.counterclockwise") }
            .buttonStyle(JunimoButtonStyle())
    }

    private var snapshot: PomodoroSnapshot { state.surfaceState.pomodoro }

    private var timeText: String {
        let remaining = max(0, snapshot.remainingSeconds)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private var statusText: String {
        switch (snapshot.mode, snapshot.status) {
        case (.focus, .idle): return "准备开始专注"
        case (.focus, .running): return "正在专注"
        case (.focus, .paused): return "专注已暂停"
        case (.focus, .completed): return "本轮专注完成"
        case (.rest, .running): return "正在休息"
        case (.rest, .paused): return "休息已暂停"
        case (.rest, .completed): return "休息结束"
        case (.rest, .idle): return "准备就绪"
        }
    }

    private var statusColor: Color { snapshot.status == .paused ? .yellow : junimoAccent }
}
