import JunimoCore
import SwiftUI

// JunimoNavigationRail 只表达本地页面选择与连接摘要，不发送产品意图。
struct JunimoNavigationRail: View {
    @ObservedObject var state: ShellState
    @Binding var selectedPage: JunimoPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                JunimoAppIcon().frame(width: 28, height: 28)
                Text("Junimo")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            pageButton(.focus, title: "专注", systemImage: "timer")
            pageButton(.todo, title: "待办", systemImage: "checklist")

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.backendMessage == "Connected" ? junimoAccent : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(state.backendMessage == "Connected" ? "已连接" : "离线")
                }
                Text(state.surfaceState.codex?.compactSummary ?? "…")
                    .monospacedDigit()
            }
            .font(.system(size: JunimoTypography.caption, weight: .medium))
            .foregroundStyle(.white.opacity(0.52))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white.opacity(0.018))
    }

    // pageButton 渲染一个可选择功能标签，并把选择限制在 Swift 本地状态。
    private func pageButton(_ page: JunimoPage, title: String, systemImage: String) -> some View {
        let selected = selectedPage == page
        return Button {
            // 导航点击本身发生在面板内部，先刷新指针事实，避免页面销毁释放编辑锁时误触发折叠。
            state.pointerEntered()
            selectedPage = page
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: JunimoTypography.navigation, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.black.opacity(0.88) : .white.opacity(0.72))
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                selected ? junimoAccent : Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .accessibilityIdentifier("navigation.\(title.lowercased())")
    }
}
