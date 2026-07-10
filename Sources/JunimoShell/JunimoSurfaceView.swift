import AppKit
import JunimoCore
import SwiftUI

private let junimoAccent = Color(red: 0.24, green: 0.95, blue: 0.58)
private let junimoPanelBlack = Color(red: 0.006, green: 0.007, blue: 0.008)

private enum JunimoButtonTone {
    case primary
    case secondary
}

private struct JunimoButtonStyle: ButtonStyle {
    var tone: JunimoButtonTone = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tone == .primary ? Color.black.opacity(0.88) : junimoAccent)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                tone == .primary ? junimoAccent : Color.white.opacity(configuration.isPressed ? 0.11 : 0.055),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tone == .primary ? Color.clear : junimoAccent.opacity(0.58), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1.0)
    }
}

private struct TopAttachedPanelShape: Shape {
    var bottomRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

struct JunimoSurfaceView: View {
    @ObservedObject var state: ShellState
    @State private var selectedFocusDuration = 25 * 60

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
        .onAppear {
            selectedFocusDuration = snapshot.focusDurationSeconds
        }
        .onChange(of: snapshot.focusDurationSeconds) { _, newValue in
            selectedFocusDuration = newValue
        }
    }

    private var collapsed: some View {
        HStack(spacing: 0) {
            focusCapsule
            Spacer(minLength: 0)
            codexUsageCapsule
        }
        .padding(.horizontal, 8)
        .frame(width: 420)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
    }

    private var focusCapsule: some View {
        HStack(spacing: 8) {
            appIcon
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
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 3, x: 0, y: 1)
    }

    private var codexUsageCapsule: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: codexProgressFraction)
                    .stroke(
                        codexStatusColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)

            Text(codexSummary)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.92),
                    junimoPanelBlack.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 3, x: 0, y: 1)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                appIcon
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Junimo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(state.backendMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                statusBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(timeText)
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                actionControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(width: 420, height: 236)
        .foregroundStyle(.white.opacity(0.92))
        .background(panelBackground)
        .overlay(
            TopAttachedPanelShape(bottomRadius: 22)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 24, x: 0, y: 14)
    }

    private var appIcon: some View {
        Group {
            if let image = NSImage(named: "junimo-junimo-sprite") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "timer")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(junimoAccent)
            }
        }
    }

    private var panelBackground: some View {
        TopAttachedPanelShape(bottomRadius: 22)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black,
                        junimoPanelBlack,
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(titleText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(statusColor.opacity(0.46), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionControls: some View {
        switch (snapshot.mode, snapshot.status) {
        case (.focus, .idle), (.rest, .idle):
            HStack(spacing: 6) {
                durationButton(minutes: 15)
                durationButton(minutes: 25)
                durationButton(minutes: 45)
            }

            Button {
                state.startFocus(durationSeconds: selectedFocusDuration)
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

        case (.focus, .running):
            Button {
                state.pausePomodoro()
            } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

            resetButton

        case (.focus, .paused):
            Button {
                state.resumePomodoro()
            } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

            resetButton

        case (.focus, .completed):
            Button {
                state.startBreak()
            } label: {
                Label("Break", systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

            Button {
                state.startFocus(durationSeconds: snapshot.focusDurationSeconds)
            } label: {
                Label("Again", systemImage: "repeat")
            }
            .buttonStyle(JunimoButtonStyle())

            resetButton

        case (.rest, .running), (.rest, .paused):
            if snapshot.status == .paused {
                Button {
                    state.resumePomodoro()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(JunimoButtonStyle(tone: .primary))
            }

            Button {
                state.skipBreak()
            } label: {
                Label("Skip", systemImage: "forward.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

            resetButton

        case (.rest, .completed):
            Button {
                state.startFocus(durationSeconds: snapshot.focusDurationSeconds)
            } label: {
                Label("Focus", systemImage: "play.fill")
            }
            .buttonStyle(JunimoButtonStyle(tone: .primary))

            resetButton
        }
    }

    private func durationButton(minutes: Int) -> some View {
        let seconds = minutes * 60
        let selected = selectedFocusDuration == seconds
        return Button {
            selectedFocusDuration = seconds
        } label: {
            Text("\(minutes)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.black.opacity(0.88) : Color.white.opacity(0.72))
                .frame(width: 36, height: 32)
                .background(
                    selected ? junimoAccent : Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? Color.clear : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button {
            state.resetPomodoro()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(JunimoButtonStyle())
    }

    private var snapshot: PomodoroSnapshot {
        state.surfaceState.pomodoro
    }

    private var codexSummary: String {
        state.surfaceState.codex?.compactSummary ?? "…"
    }

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

    private var codexProgressFraction: CGFloat {
        guard state.surfaceState.codex?.status == .available,
              let remaining = state.surfaceState.codex?.primary?.remainingPercent else {
            return 0
        }
        return CGFloat(min(100, max(0, remaining))) / 100
    }

    private var titleText: String {
        switch snapshot.mode {
        case .focus:
            return "Focus"
        case .rest:
            return "Break"
        }
    }

    private var timeText: String {
        let remaining = max(0, snapshot.remainingSeconds)
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    private var statusText: String {
        switch (snapshot.mode, snapshot.status) {
        case (.focus, .idle):
            return "Ready to focus"
        case (.focus, .running):
            return "Focus running"
        case (.focus, .paused):
            return "Focus paused"
        case (.focus, .completed):
            return "Focus completed"
        case (.rest, .running):
            return "Break running"
        case (.rest, .paused):
            return "Break paused"
        case (.rest, .completed):
            return "Break completed"
        case (.rest, .idle):
            return "Ready"
        }
    }

    private var statusColor: Color {
        snapshot.status == .paused ? .yellow : junimoAccent
    }
}
