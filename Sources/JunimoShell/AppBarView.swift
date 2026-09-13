import AppKit
import Combine
import JunimoCore
import SwiftUI

@MainActor
final class AppBarPresentation: ObservableObject {
    @Published var placement: AppBarPlacement
    @Published var enabled: Bool
    @Published var availableWidth: CGFloat = 158
    @Published var activeBundleID: String?
    @Published var icons: [String: NSImage] = [:]
    @Published var error: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        placement = AppBarPlacement(rawValue: defaults.string(forKey: "appBar.placement") ?? "right") ?? .right
        enabled = defaults.object(forKey: "appBar.enabled") as? Bool ?? true
    }
    func setPlacement(_ value: AppBarPlacement) {
        defaults.set(value.rawValue, forKey: "appBar.placement")
        placement = value
    }
    func toggle() { enabled.toggle(); defaults.set(enabled, forKey: "appBar.enabled") }
    func refreshApplications(_ items: [AppShortcut]) {
        let workspace = NSWorkspace.shared
        activeBundleID = workspace.frontmostApplication?.bundleIdentifier
        var images: [String: NSImage] = [:]
        for item in items {
            if let url = workspace.urlForApplication(withBundleIdentifier: item.bundleId) {
                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 24, height: 24)
                images[item.bundleId] = icon
            }
        }
        icons = images
    }
}

@MainActor
struct AppBarView: View {
    @ObservedObject var store: AppShortcutsStore
    @ObservedObject var presentation: AppBarPresentation
    var open: (AppShortcut) -> Void
    var manage: () -> Void
    var showMore: ([AppShortcut]) -> Void = { _ in }

    var body: some View {
        let layout = AppBarCapacity(count: store.items.count, placement: presentation.placement,
                                    availableWidth: presentation.availableWidth)
        HStack(spacing: 0) {
            ForEach(Array(store.items.prefix(layout.visibleCount))) { item in
                Button { open(item) } label: {
                    AppBarIcon(item: item, presentation: presentation)
                }
                .buttonStyle(.plain)
                .help(item.name)
                .accessibilityLabel("打开或切换到 \(item.name)")
                .accessibilityIdentifier("appBar.\(item.bundleId)")
            }
            if layout.hasOverflow {
                Button { showMore(Array(store.items.dropFirst(layout.visibleCount))) } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: presentation.placement.cellSize, height: presentation.placement.cellSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("更多常用应用")
                .accessibilityLabel("更多常用应用")
            }
        }
        .padding(.horizontal, 4)
        .foregroundStyle(.white.opacity(0.9))
        .background(Color.black.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .clipShape(Capsule())
        .contextMenu { Button("管理常用应用…", action: manage) }
        .accessibilityIdentifier("appBar.\(presentation.placement.rawValue)")
    }
}

@MainActor
struct AppBarIcon: View {
    let item: AppShortcut
    @ObservedObject var presentation: AppBarPresentation
    var body: some View {
        let isActive = presentation.activeBundleID == item.bundleId
        Group {
            if let image = presentation.icons[item.bundleId] {
                Image(nsImage: image).resizable().interpolation(.high)
            } else { Image(systemName: "app.dashed").resizable().scaledToFit() }
        }
        .frame(width: presentation.placement.iconSize - 4, height: presentation.placement.iconSize - 4)
        .frame(width: presentation.placement.cellSize, height: presentation.placement.cellSize)
        .background(isActive ? Color.green.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 7).inset(by: 1.5))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 7).inset(by: 1.5)
                    .stroke(Color.green.opacity(0.85), lineWidth: 1.25)
            }
        }
        .accessibilityValue(isActive ? "当前应用" : "未选中")
        .contentShape(Rectangle())
    }
}

@MainActor
struct AppShortcutManagerView: View {
    @ObservedObject var store: AppShortcutsStore
    @ObservedObject var presentation: AppBarPresentation
    var add: () -> Void
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("常用应用").font(.title2.bold())
                Spacer()
                Text("\(store.items.count) / 12").foregroundStyle(.secondary)
            }
            Text("固定显示这些应用；打开后点击即可切换。").foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.items) { item in
                        Button { selection = item.bundleId } label: {
                            HStack(spacing: 10) {
                                if let icon = presentation.icons[item.bundleId] {
                                    Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                                } else {
                                    Image(systemName: "app.dashed").frame(width: 26, height: 26)
                                }
                                Text(item.name).lineLimit(1).help(item.name)
                                if presentation.icons[item.bundleId] == nil {
                                    Text("未安装").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(selection == item.bundleId ? Color.accentColor.opacity(0.2) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                }.padding(4)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if store.isLoaded && store.items.isEmpty { Text("还没有常用应用，点击“添加”选择。").foregroundStyle(.secondary) }
            }
            HStack {
                Button("添加…", action: add)
                Button("移除") { change { $0.removeAll { $0.id == selection } } }
                    .disabled(selection == nil)
                Divider().frame(height: 16)
                Button("上移") { move(-1) }.disabled(selectedIndex == nil || selectedIndex == 0)
                Button("下移") { move(1) }.disabled(selectedIndex == nil || selectedIndex == store.items.count - 1)
                Spacer()
                if store.isSaving { ProgressView().controlSize(.small) }
            }.disabled(!store.isLoaded || store.isSaving)
            if let error = store.error ?? presentation.error {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if !store.isLoaded { Text("正在连接后端…").foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(width: 460, height: 370)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private var selectedIndex: Int? { store.items.firstIndex { $0.id == selection } }
    private func change(_ mutation: (inout [AppShortcut]) -> Void) {
        var proposed = store.items
        mutation(&proposed)
        let revision = store.revision
        Task { await store.save(proposed, basedOn: revision) }
    }
    private func move(_ delta: Int) {
        guard let index = selectedIndex, store.items.indices.contains(index + delta) else { return }
        change { $0.swapAt(index, index + delta) }
    }
}
