import Foundation

public struct PreferencesFeature {
    public private(set) var preferences: ConsolePreferences
    public private(set) var theme: ConsoleTheme

    private let core: PreferencesCore

    /// 业务语义：PreferencesFeature 以 core snapshot 初始化 UI preferences/theme 投影。
    public init(core: PreferencesCore) {
        self.core = core
        let resolvedPreferences = core.uiPreferences()
        self.preferences = resolvedPreferences
        self.theme = ConsoleTheme(accent: resolvedPreferences.accent)
    }

    /// 业务语义：accent intent 通过 core 更新，theme 只从返回的 preference accent 派生。
    @discardableResult
    public mutating func setAccent(_ accent: ConsoleAccent) -> ConsolePreferences {
        let updated = core.setAccent(accent)
        apply(updated)
        return updated
    }

    /// 业务语义：density intent 通过 core 更新，panel size/top offset 以 core 返回值为准。
    @discardableResult
    public mutating func setDensity(_ density: ConsoleDensity) -> ConsolePreferences {
        let updated = core.setDensity(density)
        apply(updated)
        return updated
    }

    /// 业务语义：preferences 是唯一投影源，theme 只同步 accent 派生值。
    private mutating func apply(_ updated: ConsolePreferences) {
        preferences = updated
        theme.accent = updated.accent
    }
}
