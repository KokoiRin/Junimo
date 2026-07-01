import AppKit
import JunimoCore
import SwiftUI

enum JunimoPanelPage: String, CaseIterable, Identifiable {
    case codex
    case focus
    case note
    case capture

    var id: String { rawValue }
}

struct JunimoSurfaceView: View {
    @ObservedObject var coordinator: TaskCoordinator
    @State private var now = Date()
    @State private var selectedPage: JunimoPanelPage = .codex
    @State private var attentionPulse = false
    @State private var attentionSweep = false
    @State private var lastAttentionID = ""

    private let copy = JunimoSurfaceCopy.simplifiedChinese

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
        ZStack {
            islandBackground

            VStack(spacing: 0) {
                islandHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                HStack(alignment: .top, spacing: 14) {
                    pageTabs
                        .frame(width: 118)

                    selectedPageContent
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .frame(height: 184)

                Spacer(minLength: 0)

                latestActivityStrip
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .padding(.top, 10)
            }
        }
        .foregroundStyle(.white.opacity(0.94))
        .clipShape(TopAttachedPanelShape(radius: 36))
        .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 12)
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
                spriteImage
                    .frame(width: 30, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Junimo")
                        .font(.system(size: 14, weight: .semibold))
                    Text(copy.headerSubtitle(coordinator.projectProfile.stack))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(localizedUsageSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(attentionColor)
                Text(copy.currentPageTitle(selectedPage))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }
        }
    }

    private var pageTabs: some View {
        VStack(spacing: 8) {
            ForEach(JunimoPanelPage.allCases) { page in
                Button {
                    selectedPage = page
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copy.pageIcon(page))
                            .font(.system(size: 11, weight: .semibold))
                        Text(copy.pageTitle(page))
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36)
                    .foregroundStyle(selectedPage == page ? Color.black.opacity(0.86) : Color.white.opacity(0.72))
                    .background(
                        selectedPage == page ? accentColor : Color.white.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(selectedPage == page ? 0.0 : 0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(copy.pageHelp(page))
            }
        }
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedPage {
        case .codex:
            codexPage
        case .focus:
            focusPage
        case .note:
            notePage
        case .capture:
            capturePage
        }
    }

    private var codexPage: some View {
        HStack(alignment: .top, spacing: 12) {
            modulePanel(title: copy.codexTitle, status: codexCapabilityStatus, statusColor: attentionColor) {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(copy.quotaLabel, localizedUsageSummary)
                    infoRow(copy.threadLabel, localizedThreadSummary)
                    infoRow(copy.reviewLabel, codexReviewSummary)

                    if let review = coordinator.codexReviewItems.first {
                        cardActionButton(title: copy.markRead, systemImage: "checkmark", help: copy.markReadHelp(review.title)) {
                            coordinator.acknowledgeCodexReview(id: review.id)
                        }
                    }
                }
            }
            .frame(width: 332)

            modulePanel(title: copy.connectionTitle, status: "\(connectionReadyCount)/\(connectionFindings.count)", statusColor: .green) {
                VStack(spacing: 8) {
                    ForEach(connectionFindings.prefix(4)) { finding in
                        connectionRow(finding)
                    }

                    if connectionFindings.isEmpty {
                        Text(copy.noConnectionFindings)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 184)
    }

    private var focusPage: some View {
        HStack(alignment: .top, spacing: 12) {
            modulePanel(title: copy.focusTitle, status: coordinator.activePomodoro == nil ? copy.ready : copy.active, statusColor: coordinator.activePomodoro == nil ? accentColor : .yellow) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(focusPrimaryText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)

                    Text(focusCapabilityDetail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(2)

                    if coordinator.activePomodoro == nil {
                        cardActionButton(title: copy.startFocus, systemImage: "timer", help: copy.startFocusHelp) {
                            coordinator.startPomodoro(duration: 25 * 60)
                        }
                    } else {
                        cardActionButton(title: copy.stopFocus, systemImage: "xmark", help: copy.stopFocusHelp) {
                            coordinator.cancelPomodoro()
                        }
                    }
                }
            }
            .frame(width: 332)

            modulePanel(title: copy.reminderTitle, status: "\(coordinator.pendingNotifications.count)", statusColor: .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(copy.reminderStatusLabel, focusCapabilityFootnote)
                    infoRow(copy.sessionLabel, latestSessionSummary)
                }
            }
        }
        .frame(height: 184)
    }

    private var notePage: some View {
        HStack(alignment: .top, spacing: 12) {
            modulePanel(title: copy.noteTitle, status: coordinator.isCornerNoteExpanded ? copy.open : "\(openTodoCount) \(copy.todoOpenSuffix)", statusColor: accentColor) {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(copy.noteStatusLabel, localizedNoteState)
                    infoRow(copy.todoLabel, "\(coordinator.cornerTodos.count) \(copy.todoCountSuffix)")
                    cardActionButton(title: copy.openNote, systemImage: "square.and.pencil", help: copy.openNoteHelp) {
                        coordinator.setCornerNoteExpanded(true)
                    }
                }
            }
            .frame(width: 332)

            modulePanel(title: copy.todoPreviewTitle, status: "\(openTodoCount)", statusColor: .mint) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(coordinator.cornerTodos.prefix(3)) { todo in
                        todoPreviewRow(todo)
                    }

                    if coordinator.cornerTodos.isEmpty {
                        Text(copy.noTodos)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                }
            }
        }
        .frame(height: 184)
    }

    private var capturePage: some View {
        HStack(alignment: .top, spacing: 12) {
            modulePanel(title: copy.captureTitle, status: copy.externalScript, statusColor: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow(copy.captureOwnerLabel, copy.captureOwner)
                    infoRow(copy.capturePathLabel, "~/Documents/JunimoActivityCaptures")
                    infoRow(copy.capturePolicyLabel, copy.capturePolicy)
                }
            }
            .frame(width: 332)

            modulePanel(title: copy.captureBoundaryTitle, status: copy.detached, statusColor: .gray) {
                Text(copy.captureBoundaryDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 184)
    }

    private func modulePanel<Content: View>(
        title: String,
        status: String,
        statusColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Spacer(minLength: 8)

                statusPill(status, color: statusColor)
            }

            content()

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.080), lineWidth: 1))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.40))
                .frame(width: 56, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todoPreviewRow(_ todo: CornerTodoItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(todo.isDone ? accentColor : Color.white.opacity(0.42))
                .frame(width: 14)

            Text(todo.title.isEmpty ? copy.emptyTodoTitle : todo.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(todo.isDone ? Color.white.opacity(0.38) : Color.white.opacity(0.70))
                .lineLimit(1)
        }
    }

    private var latestActivityStrip: some View {
        HStack(spacing: 8) {
            Text(copy.latestTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))

            Text(latestActivityTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)

            Text(latestActivityDetail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.075), lineWidth: 1))
    }

    private func cardActionButton(title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.88))
        .background(Color.white.opacity(0.095), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .help(help)
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(color.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.18), lineWidth: 1))
    }

    private func connectionRow(_ finding: CodexIntegrationFinding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(color(for: finding.status))
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { context in context[VerticalAlignment.center] }

            VStack(alignment: .leading, spacing: 2) {
                Text(localizedFindingTitle(finding))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                Text(localizedStatus(finding.status))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .help("\(localizedFindingTitle(finding)): \(localizedStatus(finding.status)). \(finding.detail)")
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

    private var codexCapabilityStatus: String {
        if !coordinator.codexReviewItems.isEmpty {
            return "\(coordinator.codexReviewItems.count) \(copy.reviewUnit)"
        }
        return localizedStatus(coordinator.codexMonitor.usage.status)
    }

    private var localizedUsageSummary: String {
        guard let usedPercent = coordinator.codexMonitor.usage.primaryWindow?.usedPercent else {
            return localizedStatus(coordinator.codexMonitor.usage.status)
        }
        return "\(max(0, 100 - usedPercent))% \(copy.remainingSuffix)"
    }

    private var localizedThreadSummary: String {
        let active = coordinator.codexMonitor.activeThreadCount
        let open = coordinator.codexMonitor.openThreadCount
        let visible = coordinator.codexMonitor.threads.count
        return "\(active) \(copy.activeThreadUnit)，\(open) \(copy.openThreadUnit)，\(visible) \(copy.visibleThreadUnit)"
    }

    private var codexReviewSummary: String {
        guard let review = coordinator.codexReviewItems.first else {
            return copy.noReviewPending
        }
        return "\(localizedThreadStatus(review.status)) · \(review.title)"
    }

    private var focusPrimaryText: String {
        guard let session = coordinator.activePomodoro else {
            return "25:00"
        }
        return remainingText(for: session, at: now)
    }

    private var focusCapabilityDetail: String {
        guard let session = coordinator.activePomodoro else {
            return copy.focusReadyDetail
        }
        return "\(session.title) · \(copy.endsAtPrefix) \(session.endsAt.formatted(date: .omitted, time: .shortened))"
    }

    private var focusCapabilityFootnote: String {
        if coordinator.activePomodoro != nil {
            return copy.focusNotificationDetail
        }
        return coordinator.pendingNotifications.isEmpty ? copy.noPendingReminders : "\(coordinator.pendingNotifications.count) \(copy.pendingReminderUnit)"
    }

    private var latestSessionSummary: String {
        guard let session = coordinator.sessions.first else {
            return copy.noSession
        }
        return "\(session.title) · \(localizedSessionStatus(session.status))"
    }

    private var openTodoCount: Int {
        coordinator.cornerTodos.filter { !$0.isDone }.count
    }

    private var localizedNoteState: String {
        coordinator.cornerNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? copy.noNoteText : copy.noteSaved
    }

    private var connectionFindings: [CodexIntegrationFinding] {
        coordinator.codexMonitor.findings
    }

    private var connectionReadyCount: Int {
        connectionFindings.filter { $0.status == .available }.count
    }

    private var latestActivityTitle: String {
        coordinator.recentActivities.first?.title ?? copy.noActivityTitle
    }

    private var latestActivityDetail: String {
        coordinator.recentActivities.first?.detail ?? copy.noActivityDetail
    }

    private func quotaWindowText(_ window: CodexUsageWindow?) -> String? {
        guard let window, let usedPercent = window.usedPercent else {
            return nil
        }
        let remaining = max(0, 100 - usedPercent)
        switch window.durationMinutes {
        case 300:
            return "5 \(copy.hourWindow) \(remaining)%"
        case 10_080:
            return "\(copy.weekWindow) \(remaining)%"
        case let minutes?:
            return "\(minutes) \(copy.minuteWindow) \(remaining)%"
        case nil:
            return "\(window.label) \(remaining)%"
        }
    }

    private var accentColor: Color {
        color(for: coordinator.theme.accent)
    }

    /// 业务语义：collapsed 右侧状态位优先提示待处理 Codex 结果，没有结果时才回到配额。
    private var collapsedStatusText: String {
        if let review = coordinator.codexReviewItems.first {
            return review.status == .failed ? copy.collapsedFailed : copy.collapsedDone
        }
        return localizedUsageSummary
    }

    private var collapsedStatusHelp: String {
        guard let review = coordinator.codexReviewItems.first else {
            return codexQuotaDetail
        }
        return copy.markReadHelp(review.title)
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

    private func color(for accent: ConsoleAccent) -> Color {
        switch accent {
        case .mint: .mint
        case .amber: .orange
        case .graphite: .gray
        }
    }

    private func color(for status: CodexCapabilityStatus) -> Color {
        switch status {
        case .available: .green
        case .needsSetup: .yellow
        case .unsupported: .gray
        case .degraded: .orange
        }
    }

    private func localizedStatus(_ status: CodexCapabilityStatus) -> String {
        switch status {
        case .available: copy.statusAvailable
        case .needsSetup: copy.statusNeedsSetup
        case .unsupported: copy.statusUnsupported
        case .degraded: copy.statusDegraded
        }
    }

    private func localizedThreadStatus(_ status: CodexThreadStatus) -> String {
        switch status {
        case .idle: copy.threadIdle
        case .running: copy.threadRunning
        case .waiting: copy.threadWaiting
        case .open: copy.threadOpen
        case .completed: copy.threadCompleted
        case .failed: copy.threadFailed
        }
    }

    private func localizedSessionStatus(_ status: ExecutionSessionStatus) -> String {
        switch status {
        case .queued: copy.sessionQueued
        case .running: copy.sessionRunning
        case .succeeded: copy.sessionSucceeded
        case .failed: copy.sessionFailed
        }
    }

    private func localizedFindingTitle(_ finding: CodexIntegrationFinding) -> String {
        copy.findingTitle(finding.id, fallback: finding.title)
    }

    private func remainingText(for session: PomodoroSession, at date: Date) -> String {
        let remaining = Int(ceil(session.remaining(at: date)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

}

/// 业务语义：主面板可见文案集中在 copy 对象里，后续切换语言时不需要改散落的 SwiftUI 布局。
struct JunimoSurfaceCopy {
    static let simplifiedChinese = JunimoSurfaceCopy()

    let codexTitle = "Codex 状态"
    let focusTitle = "专注计时"
    let noteTitle = "便签 / 待办"
    let captureTitle = "截图脚本"
    let connectionTitle = "连接情况"
    let reminderTitle = "提醒"
    let todoPreviewTitle = "待办预览"
    let captureBoundaryTitle = "边界"
    let latestTitle = "最近"

    let quotaLabel = "配额"
    let threadLabel = "线程"
    let reviewLabel = "结果"
    let reminderStatusLabel = "状态"
    let sessionLabel = "会话"
    let noteStatusLabel = "便签"
    let todoLabel = "待办"
    let captureOwnerLabel = "归属"
    let capturePathLabel = "目录"
    let capturePolicyLabel = "策略"

    let markRead = "确认"
    let startFocus = "开始"
    let stopFocus = "停止"
    let openNote = "打开"
    let ready = "就绪"
    let active = "运行中"
    let open = "已打开"
    let externalScript = "外部脚本"
    let detached = "已拆出"

    let captureOwner = "LaunchAgent 后台脚本"
    let capturePolicy = "应用内不再请求截图权限"
    let captureBoundaryDetail = "截图能力已经从 Junimo 主面板拆出。这里仅提示它是独立后台脚本；启动、停止和权限处理不放在主工具里。"

    let noConnectionFindings = "还没有连接诊断信息"
    let noReviewPending = "没有待确认结果"
    let focusReadyDetail = "启动一个 25 分钟专注计时"
    let focusNotificationDetail = "结束时会创建提醒"
    let noPendingReminders = "没有待发送提醒"
    let noSession = "暂无会话"
    let noNoteText = "还没有便签内容"
    let noteSaved = "便签内容已保存"
    let noTodos = "还没有待办"
    let noActivityTitle = "暂无活动"
    let noActivityDetail = "Junimo 正在等待下一次本地事件"
    let emptyTodoTitle = "未命名待办"

    let reviewUnit = "个结果"
    let activeThreadUnit = "个运行中"
    let openThreadUnit = "个打开"
    let visibleThreadUnit = "条可见"
    let remainingSuffix = "可用"
    let pendingReminderUnit = "个待提醒"
    let todoOpenSuffix = "个未完成"
    let todoCountSuffix = "条"
    let endsAtPrefix = "预计结束"
    let hourWindow = "小时窗口"
    let weekWindow = "本周窗口"
    let minuteWindow = "分钟窗口"
    let collapsedFailed = "失败"
    let collapsedDone = "完成"

    let statusAvailable = "可用"
    let statusNeedsSetup = "实时配额未连接"
    let statusUnsupported = "不支持"
    let statusDegraded = "降级"

    let threadIdle = "空闲"
    let threadRunning = "运行中"
    let threadWaiting = "等待中"
    let threadOpen = "打开"
    let threadCompleted = "完成"
    let threadFailed = "失败"

    let sessionQueued = "排队中"
    let sessionRunning = "运行中"
    let sessionSucceeded = "完成"
    let sessionFailed = "失败"

    func headerSubtitle(_ stack: String) -> String {
        "本地控制台 · \(stack)"
    }

    func currentPageTitle(_ page: JunimoPanelPage) -> String {
        "当前：\(pageTitle(page))"
    }

    func pageTitle(_ page: JunimoPanelPage) -> String {
        switch page {
        case .codex: "Codex"
        case .focus: "专注"
        case .note: "便签"
        case .capture: "截图"
        }
    }

    func pageIcon(_ page: JunimoPanelPage) -> String {
        switch page {
        case .codex: "terminal"
        case .focus: "timer"
        case .note: "checklist"
        case .capture: "camera.viewfinder"
        }
    }

    func pageHelp(_ page: JunimoPanelPage) -> String {
        switch page {
        case .codex: "查看 Codex 配额、线程和连接"
        case .focus: "查看和控制番茄钟"
        case .note: "打开便签和待办"
        case .capture: "查看独立截图脚本的边界"
        }
    }

    func markReadHelp(_ title: String) -> String {
        "确认已查看 Codex 结果：\(title)"
    }

    var startFocusHelp: String {
        "开始 25 分钟专注计时"
    }

    var stopFocusHelp: String {
        "停止当前专注计时"
    }

    var openNoteHelp: String {
        "打开右下角便签和待办面板"
    }

    func findingTitle(_ id: String, fallback: String) -> String {
        switch id {
        case "app-server", "app-server-status":
            return "本地 app-server"
        case "app-server-rate-limits":
            return "实时配额"
        case "app-server-threads":
            return "本地线程"
        case "exec-json":
            return "Junimo 启动任务"
        case "cloud-list":
            return "云端任务"
        case "analytics":
            return "历史用量"
        case "auth":
            return "认证"
        case "network":
            return "网络"
        case "app-server-realtime":
            return "实时事件"
        default:
            return fallback
        }
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
