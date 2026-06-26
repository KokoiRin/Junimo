import JunimoCore
import SwiftUI

enum CornerNoteLayout {
    static let triggerSize = CGSize(width: 40, height: 40)
    static let triggerThickness: CGFloat = 10
    static let expandedWindowSize = CGSize(width: 620, height: 680)
    static let visiblePanelSize = CGSize(width: 460, height: 520)
}

struct CornerNoteSurfaceView: View {
    @ObservedObject var coordinator: TaskCoordinator
    var onTriggerHoverChanged: (Bool) -> Void

    var body: some View {
        Group {
            if coordinator.isCornerNoteExpanded {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.001)
                    expandedNote
                        .frame(width: CornerNoteLayout.visiblePanelSize.width, height: CornerNoteLayout.visiblePanelSize.height)
                }
                    .frame(width: CornerNoteLayout.expandedWindowSize.width, height: CornerNoteLayout.expandedWindowSize.height)
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        if !isInside {
                            coordinator.setCornerNoteExpanded(false)
                        }
                    }
            } else {
                cornerTrigger
                    .frame(width: CornerNoteLayout.triggerSize.width, height: CornerNoteLayout.triggerSize.height)
                    .onHover(perform: onTriggerHoverChanged)
            }
        }
    }

    private var cornerTrigger: some View {
        CornerTriggerShape(thickness: CornerNoteLayout.triggerThickness)
            .fill(Color.black.opacity(0.001))
            .contentShape(CornerTriggerShape(thickness: CornerNoteLayout.triggerThickness))
        .help("Quick note edge")
    }

    private var expandedNote: some View {
        VStack(spacing: 16) {
            header
            todoList
            noteSection
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
        .foregroundStyle(.white.opacity(0.94))
        .background(panelBackground)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.mint)
            Text("Todo")
                .font(.system(size: 24, weight: .semibold))
            Spacer()
            Button {
                coordinator.addCornerTodo(title: "")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.08), in: Circle())
            .help("Add todo")

            Button {
                coordinator.setCornerNoteExpanded(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.08), in: Circle())
            .help("Close")
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Note", systemImage: "note.text")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            noteEditor
        }
    }

    private var noteEditor: some View {
        TextEditor(
            text: Binding(
                get: { coordinator.cornerNoteText },
                set: { coordinator.updateCornerNoteText($0) }
            )
        )
        .font(.system(size: 17, weight: .regular))
        .scrollContentBackground(.hidden)
        .foregroundStyle(.white.opacity(0.90))
        .padding(10)
        .frame(height: 170)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var todoList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(coordinator.cornerTodos) { todo in
                    todoRow(todo)
                }
            }
        }
    }

    private func todoRow(_ todo: CornerTodoItem) -> some View {
        HStack(spacing: 8) {
            Button {
                coordinator.toggleCornerTodo(id: todo.id)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(todo.isDone ? .mint : .white.opacity(0.48))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark open" : "Mark done")

            TextField(
                "Todo",
                text: Binding(
                    get: { todo.title },
                    set: { coordinator.updateCornerTodo(id: todo.id, title: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(todo.isDone ? .white.opacity(0.38) : .white.opacity(0.90))

            Button {
                coordinator.removeCornerTodo(id: todo.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.46))
            .help("Delete todo")
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var panelBackground: some View {
        EdgeAttachedPanelShape(radius: 24)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.018, green: 0.020, blue: 0.018),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(EdgeAttachedPanelShape(radius: 24).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
    }
}

private struct EdgeAttachedPanelShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        return path
    }
}

private struct CornerTriggerShape: Shape {
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let t = min(thickness, rect.width, rect.height)
        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.maxY - t, width: rect.width, height: t))
        path.addRect(CGRect(x: rect.maxX - t, y: rect.minY, width: t, height: rect.height))
        return path
    }
}
