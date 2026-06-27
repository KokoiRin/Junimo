# Design: Extract Corner Note Feature

## Target Type

[P1][架构预备]

## Core Behavior Semantics

当用户展开角落便签、编辑文本或修改 todo 时，Swift 侧应该通过 `CornerNoteFeature` 维护 UI-ready state projection，并通过 `CornerNoteCore` 执行持久化领域变更，而不是让 `TaskCoordinator` 直接拥有便签状态规则。

## Component Contract: `CornerNoteFeature`

- Responsibility: own expanded state, note text projection, todo projection, and note/todo mutation intents.
- Not responsible for: AppKit panel placement, SwiftUI layout, cache file format, or system notifications.
- Owner: Corner Note feature module.
- Interface: `setExpanded`, `updateText`, `addTodo`, `updateTodo`, `toggleTodo`, `removeTodo`, and public `snapshot`.
- State: `isExpanded`, `text`, `todos`; persisted text/todos are sourced from `CornerNoteCore`.
- Side effects: only through `CornerNoteCore` mutation calls.
- Invariants: missing todo IDs leave state unchanged; expanded state changes do not mutate note/todo content; note/todo mutations keep the feature snapshot aligned with core snapshots.
- Lifecycle: constructed by runtime/coordinator with a `CornerNoteCore` backend; coordinator remains a compatibility facade.
- Test surface: direct Swift smoke tests through public feature methods and existing coordinator compatibility tests.

## Migration

1. Add `CornerNoteFeature` and direct tests.
2. Delegate `TaskCoordinator` Corner Note methods to `CornerNoteFeature`.
3. Keep existing public coordinator properties and SwiftUI bindings intact.
4. Update architecture/opportunities after verification.

## Verification

- `scripts/test.sh`
- `scripts/build.sh`
- `openspec validate --all --strict`
- `git diff --check`
- `scripts/verify_ci.sh`
