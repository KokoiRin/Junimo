import AppKit
import JunimoCore
import SwiftUI

struct JunimoSurfaceView: View {
    @ObservedObject var coordinator: TaskCoordinator
    @State private var commandText = ""

    var body: some View {
        Group {
            if coordinator.isExpanded {
                expandedConsole
                    .frame(
                        width: CGFloat(coordinator.preferences.expandedWidth),
                        height: CGFloat(coordinator.preferences.expandedHeight)
                    )
            } else {
                collapsedCapsule
                    .frame(width: 236, height: 46)
            }
        }
        .onHover { isInside in
            if isInside {
                coordinator.pointerEntered()
            } else {
                coordinator.pointerExited()
                scheduleDelayedCollapse()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            coordinator.advanceTime(to: date)
        }
    }

    private var collapsedCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 15, weight: .semibold))
            Text("Junimo")
                .font(.system(size: 14, weight: .semibold))
            Divider()
                .frame(height: 18)
            statusDot(for: coordinator.agents.contains(where: { $0.status == .running }) ? .running : .idle)
            Text(runningSummary)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(accentColor.opacity(0.45), lineWidth: 1))
    }

    private var expandedConsole: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .padding(.trailing, 36)

            Divider().opacity(0.45)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    projectProfileSection
                    agentsSection
                    pomodoroSection
                }
                .frame(width: 260)

                VStack(alignment: .leading, spacing: 12) {
                    commandPaletteSection
                    sessionsSection
                    activitySection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(18)
        }
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accentColor.opacity(0.35), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            quitButton
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Junimo")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Local agent console")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(ConsoleDensity.allCases) { density in
                    Button {
                        coordinator.setDensity(density)
                    } label: {
                        Text(density.label)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .background(
                        coordinator.preferences.density == density ? accentColor.opacity(0.20) : Color.primary.opacity(0.06),
                        in: Capsule()
                    )
                    .help(density.label)
                }

                ForEach(ConsoleAccent.allCases) { accent in
                    Button {
                        coordinator.setAccent(accent)
                    } label: {
                        Circle()
                            .fill(color(for: accent))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().stroke(
                                    coordinator.theme.accent == accent ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(accent.label)
                }

            }
        }
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(Color.red.opacity(0.16), in: Circle())
        .foregroundStyle(.red)
        .help("Quit Junimo")
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Agents", systemImage: "person.2.wave.2.fill")
            ForEach(coordinator.agents) { agent in
                HStack(spacing: 10) {
                    statusDot(for: agent.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(agent.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(agent.status.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var projectProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Project", systemImage: "rectangle.stack.fill")
            VStack(alignment: .leading, spacing: 7) {
                Text(coordinator.projectProfile.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(coordinator.projectProfile.stack)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(coordinator.projectProfile.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(coordinator.projectProfile.shortcuts.prefix(3), id: \.self) { shortcut in
                        Text(shortcut)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.16), in: Capsule())
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var commandPaletteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Command Palette", systemImage: "command")
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search commands", text: $commandText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onChange(of: commandText) { _, newValue in
                            coordinator.updateCommandQuery(newValue)
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(coordinator.commandResults.prefix(6)) { command in
                        Button {
                            coordinator.performCommand(id: command.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: icon(forCommandCategory: command.category))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(command.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(command.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Actions", systemImage: "bolt.fill")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(coordinator.actions) { action in
                    Button {
                        coordinator.performAction(id: action.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: action.kind))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(action.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
            }
        }
    }

    private var pomodoroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Pomodoro", systemImage: "timer")
            VStack(alignment: .leading, spacing: 10) {
                if let session = coordinator.activePomodoro {
                    HStack {
                        Text(remainingText(for: session))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Spacer()
                        Button {
                            coordinator.cancelPomodoro()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)
                        .help("Cancel")
                    }
                    Text("Ends \(session.endsAt, style: .time)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            coordinator.startPomodoro(duration: 25 * 60)
                        } label: {
                            Label("25m", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)

                        Button {
                            coordinator.startPomodoro(duration: 10)
                        } label: {
                            Label("10s", systemImage: "hare.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Start short timer")
                    }
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recent", systemImage: "clock.arrow.circlepath")
            VStack(spacing: 6) {
                ForEach(coordinator.recentActivities.prefix(5)) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(entry.date, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Sessions", systemImage: "list.bullet.rectangle")
            VStack(spacing: 6) {
                if coordinator.sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else {
                    ForEach(coordinator.sessions.prefix(3)) { session in
                        HStack(spacing: 8) {
                            statusDot(forSession: session.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(session.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(session.statusLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(color(forSession: session.status).opacity(0.16), in: Capsule())
                                .foregroundStyle(color(forSession: session.status))
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var runningSummary: String {
        coordinator.agents.contains(where: { $0.status == .running }) ? "Active" : "Ready"
    }

    private var accentColor: Color {
        color(for: coordinator.theme.accent)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func statusDot(for status: AgentStatus) -> some View {
        Circle()
            .fill(status == .running ? Color.green : status == .failed ? Color.red : accentColor)
            .frame(width: 8, height: 8)
    }

    private func statusDot(forSession status: ExecutionSessionStatus) -> some View {
        Circle()
            .fill(color(forSession: status))
            .frame(width: 7, height: 7)
    }

    private func color(forSession status: ExecutionSessionStatus) -> Color {
        switch status {
        case .queued: .secondary
        case .running: .green
        case .succeeded: accentColor
        case .failed: .red
        }
    }

    private func icon(for kind: ConsoleActionKind) -> String {
        switch kind {
        case .agent: "sparkles"
        case .tool: "hammer.fill"
        case .project: "folder.fill"
        }
    }

    private func icon(forCommandCategory category: String) -> String {
        switch category {
        case "Agents": "sparkles"
        case "Project": "folder.fill"
        case "Focus": "timer"
        case "Tools": "hammer.fill"
        default: "command"
        }
    }

    private func color(for accent: ConsoleAccent) -> Color {
        switch accent {
        case .mint: .mint
        case .amber: .orange
        case .graphite: .gray
        }
    }

    private func remainingText(for session: PomodoroSession) -> String {
        let remaining = Int(ceil(session.remaining(at: Date())))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func scheduleDelayedCollapse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + TaskCoordinator.collapseDelay + 0.05) {
            coordinator.advanceTime(to: Date())
        }
    }
}
