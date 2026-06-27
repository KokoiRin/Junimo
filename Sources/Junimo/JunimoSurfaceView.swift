import AppKit
import JunimoCore
import SwiftUI

struct JunimoSurfaceView: View {
    @ObservedObject var coordinator: TaskCoordinator
    @State private var commandText = ""
    @State private var now = Date()
    @State private var attentionPulse = false
    @State private var attentionSweep = false
    @State private var lastAttentionID = ""

    var body: some View {
        Group {
            if coordinator.isExpanded {
                expandedConsole
                    .frame(
                        width: CGFloat(coordinator.preferences.expandedWidth),
                        height: CGFloat(coordinator.preferences.expandedHeight)
                    )
            } else {
                collapsedTriggerStrip
                    .frame(width: 420, height: 28)
            }
        }
        .contentShape(Rectangle())
        .onHover { isInside in
            if isInside {
                coordinator.pointerEntered()
            } else {
                coordinator.pointerExited()
            }
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { date in
            now = date
            coordinator.advanceTime(to: date)
        }
        .onAppear {
            updateCodexAttentionAnimation()
        }
        .onChange(of: latestCodexReviewID) {
            updateCodexAttentionAnimation()
        }
    }

    private var collapsedTriggerStrip: some View {
        HStack(spacing: 16) {
            launchSprite
                .help("Junimo is running")

            Color.clear
                .frame(width: 208, height: 28)

            quotaTriggerPill
                .help(collapsedStatusHelp)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .overlay {
            collapsedPromptVisualEffect
                .allowsHitTesting(false)
        }
        .overlay {
            collapsedReviewBadgeButton
        }
    }

    private var collapsedPromptVisualEffect: some View {
        ZStack {
            if let cue = latestCodexAttentionCue {
                Capsule()
                    .fill(attentionColor.opacity(cue.tone == .failed ? 0.16 : 0.11))
                    .frame(width: 360, height: 28)
                    .scaleEffect(x: attentionPulse ? 1.015 : 0.985, y: attentionPulse ? 1.10 : 0.92)
                    .opacity(attentionPulse ? 0.95 : 0.55)
                    .blur(radius: 0.4)

                Capsule()
                    .stroke(attentionColor.opacity(cue.tone == .failed ? 0.72 : 0.56), lineWidth: 1.4)
                    .frame(width: 360, height: 28)
                    .shadow(color: attentionColor.opacity(0.45), radius: attentionPulse ? 10 : 4)

                Capsule()
                    .stroke(Color.white.opacity(attentionPulse ? 0.22 : 0.10), lineWidth: 1)
                    .frame(width: 250, height: 18)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(cue.tone == .failed ? 0.24 : 0.18),
                                attentionColor.opacity(cue.tone == .failed ? 0.26 : 0.18),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 74, height: 28)
                    .offset(x: attentionSweep ? 194 : -194)
                    .clipShape(Capsule())

                HStack(spacing: 214) {
                    Image(systemName: cue.symbolName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(attentionColor)
                        .scaleEffect(attentionPulse ? 1.10 : 0.92)
                    Image(systemName: cue.symbolName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(attentionColor)
                        .scaleEffect(attentionPulse ? 0.92 : 1.10)
                }
                .opacity(cue.tone == .failed ? 0.72 : 0.58)
            }
        }
        .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: attentionPulse)
        .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: attentionSweep)
    }

    @ViewBuilder
    private var collapsedReviewBadgeButton: some View {
        if let cue = latestCodexAttentionCue {
            Button {
                coordinator.acknowledgeLatestCodexReview()
            } label: {
                Image(systemName: cue.symbolName)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 18, height: 18)
                    .background(attentionColor, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                    .scaleEffect(attentionPulse ? 1.12 : 0.96)
            }
            .buttonStyle(.plain)
            .offset(x: 164)
            .help("Mark latest Codex result reviewed")
            .animation(.spring(response: 0.34, dampingFraction: 0.64), value: attentionPulse)
        }
    }

    private var launchSprite: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.82))
                .frame(width: 36, height: 28)
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))

            spriteImage
                .frame(width: 30, height: 28)
        }
        .shadow(color: accentColor.opacity(0.24), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private var quotaTriggerPill: some View {
        if hasCodexReviewAttention {
            Button {
                coordinator.acknowledgeLatestCodexReview()
            } label: {
                collapsedStatusPillLabel
            }
            .buttonStyle(.plain)
        } else {
            collapsedStatusPillLabel
        }
    }

    private var collapsedStatusPillLabel: some View {
        Text(collapsedStatusText)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(attentionColor)
            .frame(width: 76, height: 24)
            .background(Color.black.opacity(0.82), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 3)
    }

    private var spriteImage: some View {
        Group {
            if let image = bundledSprite {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                PixelSprite(color: accentColor)
            }
        }
    }

    private var expandedConsole: some View {
        ZStack(alignment: .bottom) {
            islandBackground

            VStack(spacing: 0) {
                islandHeader
                    .padding(.horizontal, 26)
                    .padding(.top, 18)

                Spacer(minLength: 0)

                islandCenterStage

                codexStatusStrip
                    .padding(.horizontal, 42)
                    .padding(.top, 14)

                bottomDock
                    .padding(.horizontal, 78)
                    .padding(.bottom, 16)
            }
        }
        .foregroundStyle(.white.opacity(0.94))
        .clipShape(TopAttachedPanelShape(radius: 36))
        .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 12)
        .overlay(alignment: .topTrailing) {
            quitButton
                .padding(.top, 18)
                .padding(.trailing, 22)
        }
    }

    private var islandBackground: some View {
        TopAttachedPanelShape(radius: 36)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.015, green: 0.015, blue: 0.018),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                TopAttachedPanelShape(radius: 36)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var islandHeader: some View {
        HStack {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Junimo")
                        .font(.system(size: 14, weight: .semibold))
                    Text(coordinator.projectProfile.stack)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                ForEach(ConsoleDensity.allCases) { density in
                    Button {
                        coordinator.setDensity(density)
                    } label: {
                        Text(density.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(
                        coordinator.preferences.density == density ? accentColor.opacity(0.28) : Color.white.opacity(0.08),
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
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().stroke(
                                    coordinator.theme.accent == accent ? Color.white : Color.clear,
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

    private var islandCenterStage: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 54, height: 54)
                Image(systemName: centerStageIcon)
                    .font(.system(size: 32, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accentColor)
            }

            VStack(spacing: 6) {
                Text(centerStageTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text(centerStageSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }
        }
        .padding(.top, 8)
    }

    private var codexStatusStrip: some View {
        HStack(spacing: 10) {
            codexMetric(
                icon: "gauge.medium",
                title: "Quota",
                value: coordinator.codexMonitor.usage.summaryText,
                detail: codexQuotaDetail
            )

            codexMetric(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Threads",
                value: "\(coordinator.codexMonitor.activeThreadCount)/\(coordinator.codexMonitor.threads.count)",
                detail: codexThreadsDetail
            )

            codexMetric(
                icon: "bell.badge.fill",
                title: "Alerts",
                value: codexAlertValue,
                detail: codexAlertDetail
            )
        }
        .frame(height: 46)
    }

    private var bottomDock: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if let review = coordinator.codexReviewItems.first {
                    Button {
                        coordinator.acknowledgeCodexReview(id: review.id)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(attentionColor.opacity(0.22), in: Circle())
                    .foregroundStyle(attentionColor)
                    .help("Mark Codex result reviewed: \(review.title)")

                    dockDivider
                }

                ForEach(coordinator.actions) { action in
                    dockButton(icon: icon(for: action.kind), title: action.title) {
                        coordinator.performAction(id: action.id)
                    }
                }
            }

            dockDivider

            HStack(spacing: 8) {
                Button {
                    coordinator.updateCommandQuery("focus")
                    coordinator.performCommand(id: "pomodoro-25")
                } label: {
                    Label("25m", systemImage: "timer")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Start 25 minute focus")

                if let session = coordinator.activePomodoro {
                    Text(remainingText(for: session, at: now))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                        .frame(width: 54, alignment: .leading)
                } else {
                    Text("Ready")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 54, alignment: .leading)
                }

            }

            dockDivider

            HStack(spacing: 8) {
                ForEach(coordinator.agents) { agent in
                    HStack(spacing: 5) {
                        statusDot(for: agent.status)
                        Text(agent.name.prefix(1))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(width: 32, height: 28)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    .help("\(agent.name): \(agent.status.label)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var dockDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 24)
    }

    private func dockButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.08), in: Circle())
        .foregroundStyle(.white.opacity(0.88))
        .help(title)
    }

    private func codexMetric(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .help("\(title): \(value). \(detail)")
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.08), in: Circle())
        .foregroundStyle(.white.opacity(0.78))
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
                        Text(remainingText(for: session, at: now))
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

    private var codexQuotaDetail: String {
        let usage = coordinator.codexMonitor.usage
        let primary = quotaWindowText(usage.primaryWindow)
        let secondary = quotaWindowText(usage.secondaryWindow)
        switch (primary, secondary) {
        case let (primary?, secondary?):
            return "\(primary) · \(secondary)"
        case let (primary?, nil):
            return primary
        case let (nil, secondary?):
            return secondary
        default:
            return usage.source
        }
    }

    private var codexThreadsDetail: String {
        let activeThreads = coordinator.codexMonitor.threads.filter { $0.status.isActive }
        if activeThreads.isEmpty {
            return latestCodexThreadDetail
        }
        return activeThreads.prefix(2).map(\.title).joined(separator: ", ")
    }

    private var latestCodexThreadDetail: String {
        guard let latest = coordinator.codexMonitor.latestThread else {
            return "app-server not connected"
        }
        return "\(latest.status.label) · \(latest.title)"
    }

    private func quotaWindowText(_ window: CodexUsageWindow?) -> String? {
        guard let window, let usedPercent = window.usedPercent else {
            return nil
        }
        let remaining = max(0, 100 - usedPercent)
        switch window.durationMinutes {
        case 300:
            return "5h \(remaining)%"
        case 10_080:
            return "week \(remaining)%"
        case let minutes?:
            return "\(minutes)m \(remaining)%"
        case nil:
            return "\(window.label) \(remaining)%"
        }
    }

    private var codexAlertValue: String {
        if coordinator.codexReviewItems.isEmpty {
            return "Quiet"
        }
        return "\(coordinator.codexReviewItems.count) review"
    }

    private var codexAlertDetail: String {
        guard let review = coordinator.codexReviewItems.first else {
            return "watching completions"
        }
        return "\(review.status.label) · \(review.title)"
    }

    private var centerStageIcon: String {
        if let review = coordinator.codexReviewItems.first {
            return review.status == .failed ? "exclamationmark.triangle.fill" : "bell.badge.fill"
        }
        if coordinator.activePomodoro != nil {
            return "timer"
        }
        if coordinator.sessions.isEmpty {
            return "face.smiling.inverse"
        }
        return "sparkles"
    }

    private var centerStageTitle: String {
        if let review = coordinator.codexReviewItems.first {
            return review.status == .failed ? "Codex needs attention" : "Codex ready"
        }
        if let session = coordinator.activePomodoro {
            return remainingText(for: session, at: now)
        }
        if coordinator.sessions.isEmpty {
            return "暂无会话"
        }
        return coordinator.sessions.first?.title ?? "Junimo"
    }

    private var centerStageSubtitle: String {
        if let review = coordinator.codexReviewItems.first {
            return "\(review.title): \(review.detail)"
        }
        if let session = coordinator.activePomodoro {
            return "Focus until \(session.endsAt.formatted(date: .omitted, time: .shortened))"
        }
        if coordinator.sessions.isEmpty {
            return "Hover to keep the island open"
        }
        return coordinator.sessions.first?.detail ?? runningSummary
    }

    private var accentColor: Color {
        color(for: coordinator.theme.accent)
    }

    /// 业务语义：collapsed 右侧状态位优先提示待处理 Codex 结果，没有结果时才回到配额。
    private var collapsedStatusText: String {
        coordinator.codexCollapsedStatusText
    }

    private var collapsedStatusHelp: String {
        guard let review = coordinator.codexReviewItems.first else {
            return codexQuotaDetail
        }
        return "Mark Codex result reviewed: \(review.title)"
    }

    private var hasCodexReviewAttention: Bool {
        !coordinator.codexReviewItems.isEmpty
    }

    private var latestCodexReviewID: String {
        coordinator.codexReviewItems.first?.id ?? ""
    }

    private var latestCodexAttentionCue: CodexReviewAttentionCue? {
        coordinator.codexReviewItems.first?.attentionCue
    }

    private var attentionColor: Color {
        if coordinator.codexReviewItems.contains(where: { $0.status == .failed }) {
            return .red
        }
        return accentColor
    }

    /// 业务语义：新的 Codex review attention 进入 collapsed 岛时启动持久动画，清除后复位。
    private func updateCodexAttentionAnimation() {
        guard hasCodexReviewAttention else {
            attentionPulse = false
            attentionSweep = false
            lastAttentionID = ""
            return
        }
        guard latestCodexReviewID != lastAttentionID else {
            return
        }
        lastAttentionID = latestCodexReviewID
        attentionPulse = false
        attentionSweep = false
        DispatchQueue.main.async {
            attentionPulse = true
            attentionSweep = true
        }
    }

    private var bundledSprite: NSImage? {
        guard let url = Bundle.main.url(forResource: "junimo-junimo-sprite", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
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

    private func remainingText(for session: PomodoroSession, at date: Date) -> String {
        let remaining = Int(ceil(session.remaining(at: date)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

}

private struct PixelSprite: View {
    var color: Color

    private let rows: [[Int]] = [
        [0, 0, 1, 1, 1, 1, 0, 0],
        [0, 1, 1, 1, 1, 1, 1, 0],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [1, 1, 2, 1, 1, 2, 1, 1],
        [1, 1, 1, 1, 1, 1, 1, 1],
        [0, 1, 1, 1, 1, 1, 1, 0],
        [0, 0, 1, 0, 0, 1, 0, 0],
        [0, 1, 0, 0, 0, 0, 1, 0]
    ]

    var body: some View {
        GeometryReader { proxy in
            let cell = min(proxy.size.width, proxy.size.height) / 8
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Rectangle()
                                .fill(fillColor(for: rows[row][column]))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(width: cell * 8, height: cell * 8)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func fillColor(for value: Int) -> Color {
        switch value {
        case 1: color
        case 2: .black.opacity(0.86)
        default: .clear
        }
    }
}

private struct TopAttachedPanelShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}
