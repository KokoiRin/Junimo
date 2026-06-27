import Foundation

public struct CornerNoteFeatureSnapshot: Equatable {
    public var isExpanded: Bool
    public var text: String
    public var todos: [CornerTodoItem]

    /// 业务语义：Corner Note feature snapshot 是 SwiftUI 和诊断读取角落便签状态的唯一投影。
    public init(isExpanded: Bool, text: String, todos: [CornerTodoItem]) {
        self.isExpanded = isExpanded
        self.text = text
        self.todos = todos
    }
}

public struct CornerNoteFeature {
    private let core: CornerNoteCore
    public private(set) var snapshot: CornerNoteFeatureSnapshot

    /// 业务语义：CornerNoteFeature 初始化时从持久化 core 读取内容，但展开态仍是本次 UI 会话状态。
    public init(core: CornerNoteCore, isExpanded: Bool = false) {
        self.core = core
        let note = core.cornerNote()
        self.snapshot = CornerNoteFeatureSnapshot(
            isExpanded: isExpanded,
            text: note.text,
            todos: note.todos
        )
    }

    /// 业务语义：展开态属于 UI 会话，不应该改写便签文本或 todo 内容。
    public mutating func setExpanded(_ isExpanded: Bool) {
        snapshot.isExpanded = isExpanded
    }

    /// 业务语义：文本更新必须以 CornerNoteCore 返回的持久化快照为准。
    public mutating func updateText(_ text: String) {
        apply(core.updateCornerNoteText(text))
    }

    /// 业务语义：新增 todo 后公开 snapshot 必须与 core 的 todo 顺序保持一致。
    public mutating func addTodo(title: String = "") {
        apply(core.addCornerTodo(title: title))
    }

    /// 业务语义：todo 标题更新由 core 决定是否命中，feature 只同步返回快照。
    public mutating func updateTodo(id: UUID, title: String) {
        apply(core.updateCornerTodo(id: id, title: title))
    }

    /// 业务语义：todo 完成态切换由 core 决定是否命中，feature 只同步返回快照。
    public mutating func toggleTodo(id: UUID) {
        apply(core.toggleCornerTodo(id: id))
    }

    /// 业务语义：删除 todo 后公开 snapshot 必须反映 core 的剩余 todo 集合。
    public mutating func removeTodo(id: UUID) {
        apply(core.removeCornerTodo(id: id))
    }

    /// 业务语义：内容变更只替换文本和 todo，保留当前展开态。
    private mutating func apply(_ note: CornerNoteSnapshot) {
        snapshot.text = note.text
        snapshot.todos = note.todos
    }
}
