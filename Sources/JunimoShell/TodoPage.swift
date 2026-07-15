import JunimoCore
import SwiftUI

// TodoField 标识当前直接编辑的草稿，稳定 ID 用于行内改名焦点。
private enum TodoField: Hashable {
    case newTask
    case rename(String)
}

// TodoPage 管理临时文本草稿，正式任务始终只渲染 Go TodoSnapshot。
struct TodoPage: View {
    @ObservedObject var state: ShellState
    @State private var newTitle = ""
    @State private var editingID: String?
    @State private var editingTitle = ""
    @State private var showsCompleted = false
    @FocusState private var focusedField: TodoField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("待办清单")
                        .font(.system(size: JunimoTypography.pageTitle, weight: .semibold))
                    Text("\(openItems.count) 项未完成")
                        .font(.system(size: JunimoTypography.caption, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                if snapshot.status == .unavailable {
                    Label("暂不可用", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: JunimoTypography.caption, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            newTaskField

            if let message = state.todoErrorMessage {
                Text(message)
                    .font(.system(size: JunimoTypography.caption, weight: .medium))
                    .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if snapshot.status == .unavailable {
                        unavailableState
                    } else if snapshot.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(openItems) { item in todoRow(item) }
                        completedSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .onDisappear { state.cancelPanelInteraction() }
        .accessibilityIdentifier("page.todo")
    }

    // newTaskField 保存本地草稿直到 Go 确认创建成功。
    private var newTaskField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(junimoAccent)
            TextField(
                "",
                text: $newTitle,
                prompt: Text("添加一项待办").foregroundStyle(.white.opacity(0.46))
            )
                .textFieldStyle(.plain)
                .font(.system(size: JunimoTypography.body, weight: .medium))
                .focused($focusedField, equals: .newTask)
                .onSubmit { submitNewTask() }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        state.setPanelInteractionActive(true)
                    }
                )
            Button("添加") { submitNewTask() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(junimoAccent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .disabled(snapshot.status == .unavailable)
        .opacity(snapshot.status == .unavailable ? 0.45 : 1)
    }

    // completedSection 把已完成任务保留在同一列表，并默认收起降低视觉噪音。
    @ViewBuilder
    private var completedSection: some View {
        if !completedItems.isEmpty {
            Button {
                showsCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsCompleted ? "chevron.down" : "chevron.right")
                    Text("已完成")
                    Text("\(completedItems.count)").foregroundStyle(.white.opacity(0.28))
                    Spacer()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.top, 7)
                .frame(height: 34)
            }
            .buttonStyle(.plain)

            if showsCompleted {
                ForEach(completedItems) { item in todoRow(item) }
            }
        }
    }

    // todoRow 渲染一条后端任务，并把每个按钮转换为明确目标意图。
    private func todoRow(_ item: TodoItem) -> some View {
        HStack(spacing: 9) {
            Button {
                Task { await state.setTodoCompletion(id: item.id, completed: item.status != .completed) }
            } label: {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.status == .completed ? junimoAccent.opacity(0.70) : .white.opacity(0.40))
            }
            .buttonStyle(.plain)

            if editingID == item.id {
                TextField(
                    "",
                    text: $editingTitle,
                    prompt: Text("待办内容").foregroundStyle(.white.opacity(0.46))
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: JunimoTypography.body, weight: .medium))
                    .focused($focusedField, equals: .rename(item.id))
                    .onSubmit { submitRename(item) }
            } else {
                Button { beginRename(item) } label: {
                    Text(item.title)
                        .font(.system(size: JunimoTypography.body, weight: .medium))
                        .foregroundStyle(.white.opacity(item.status == .completed ? 0.36 : 0.84))
                        .strikethrough(item.status == .completed, color: .white.opacity(0.30))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await state.deleteTodo(id: item.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(Color.white.opacity(0.028), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // submitNewTask 仅在 Go 返回成功快照后清空草稿，失败时保留用户输入。
    private func submitNewTask() {
        let title = newTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if await state.createTodo(title: title) {
                newTitle = ""
                focusedField = nil
                state.setPanelInteractionActive(false)
            }
        }
    }

    // beginRename 建立临时行内草稿并把键盘焦点交给对应稳定 ID。
    private func beginRename(_ item: TodoItem) {
        editingID = item.id
        editingTitle = item.title
        state.setPanelInteractionActive(true)
        DispatchQueue.main.async {
            focusedField = .rename(item.id)
        }
    }

    // submitRename 只在后端确认后结束编辑，失败时保留草稿与焦点上下文。
    private func submitRename(_ item: TodoItem) {
        let title = editingTitle
        Task {
            if await state.renameTodo(id: item.id, title: title) {
                editingID = nil
                editingTitle = ""
                focusedField = nil
                state.setPanelInteractionActive(false)
            }
        }
    }

    private var snapshot: TodoSnapshot { state.surfaceState.todo }
    private var openItems: [TodoItem] { snapshot.items.filter { $0.status == .open } }
    private var completedItems: [TodoItem] { snapshot.items.filter { $0.status == .completed } }

    // emptyState 说明当前没有正式任务，并提示最短下一步。
    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle").font(.system(size: 24, weight: .light))
            Text("暂时没有待办")
                .font(.system(size: JunimoTypography.body, weight: .semibold))
            Text("在上方输入内容，添加第一项任务")
                .font(.system(size: JunimoTypography.caption, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
        }
        .foregroundStyle(.white.opacity(0.62))
        .frame(maxWidth: .infinity)
        .padding(.top, 38)
    }

    // unavailableState 只关闭 Todo 操作区，不暗示 Pomodoro 或 Codex 同时失效。
    private var unavailableState: some View {
        VStack(spacing: 7) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 22))
            Text("待办存储暂不可用")
                .font(.system(size: JunimoTypography.body, weight: .semibold))
            Text("专注计时和 Codex 用量仍可正常使用")
                .font(.system(size: JunimoTypography.caption, weight: .medium))
                .foregroundStyle(.white.opacity(0.44))
        }
        .foregroundStyle(.orange.opacity(0.75))
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
    }
}
