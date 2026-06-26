#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JunimoCoreEngine* JunimoCoreEngineRef;

typedef struct JunimoCoreActionResult {
    int handled;
    const char* activity_title;
    const char* activity_detail;
    const char* agent_id;
    int agent_status;
} JunimoCoreActionResult;

typedef struct JunimoCoreAgentSnapshot {
    const char* id;
    const char* name;
    const char* detail;
    int status;
} JunimoCoreAgentSnapshot;

typedef struct JunimoCoreAgentList {
    int count;
    JunimoCoreAgentSnapshot items[8];
} JunimoCoreAgentList;

typedef struct JunimoCoreActionSnapshot {
    const char* id;
    const char* title;
    const char* subtitle;
    int kind;
    const char* agent_id;
} JunimoCoreActionSnapshot;

typedef struct JunimoCoreActionList {
    int count;
    JunimoCoreActionSnapshot items[8];
} JunimoCoreActionList;

typedef struct JunimoCoreActivitySnapshot {
    const char* title;
    const char* detail;
    long long created_at_unix_seconds;
} JunimoCoreActivitySnapshot;

typedef struct JunimoCoreActivityList {
    int count;
    JunimoCoreActivitySnapshot items[8];
} JunimoCoreActivityList;

typedef struct JunimoCorePomodoroResult {
    int changed;
    int completed;
    const char* activity_title;
    const char* activity_detail;
    const char* notification_title;
    const char* notification_body;
} JunimoCorePomodoroResult;

typedef struct JunimoCorePomodoroSnapshot {
    int has_active;
    const char* title;
    long long started_at_unix_seconds;
    long long duration_seconds;
} JunimoCorePomodoroSnapshot;

typedef struct JunimoCoreCommandSnapshot {
    const char* id;
    const char* title;
    const char* subtitle;
    const char* category;
} JunimoCoreCommandSnapshot;

typedef struct JunimoCoreCommandList {
    int count;
    JunimoCoreCommandSnapshot items[8];
} JunimoCoreCommandList;

typedef struct JunimoCoreProjectProfileSnapshot {
    const char* name;
    const char* path;
    const char* stack;
    const char* shortcut_1;
    const char* shortcut_2;
    const char* shortcut_3;
} JunimoCoreProjectProfileSnapshot;

typedef struct JunimoCoreSessionSnapshot {
    const char* id;
    const char* title;
    const char* detail;
    const char* status_label;
    int status;
    long long started_at_unix_seconds;
} JunimoCoreSessionSnapshot;

typedef struct JunimoCoreSessionList {
    int count;
    JunimoCoreSessionSnapshot items[6];
} JunimoCoreSessionList;

typedef struct JunimoCoreUiPreferencesSnapshot {
    const char* accent;
    const char* density;
    int expanded_width;
    int expanded_height;
    int top_offset;
} JunimoCoreUiPreferencesSnapshot;

typedef struct JunimoCoreCornerTodoSnapshot {
    const char* id;
    const char* title;
    int is_done;
} JunimoCoreCornerTodoSnapshot;

typedef struct JunimoCoreCornerNoteSnapshot {
    const char* text;
    int todo_count;
    JunimoCoreCornerTodoSnapshot todos[16];
} JunimoCoreCornerNoteSnapshot;

JunimoCoreEngineRef junimo_core_engine_create(void);
void junimo_core_engine_destroy(JunimoCoreEngineRef engine);

JunimoCoreAgentList junimo_core_agents(JunimoCoreEngineRef engine);
JunimoCoreActionList junimo_core_actions(JunimoCoreEngineRef engine);
JunimoCoreActivityList junimo_core_recent_activities(JunimoCoreEngineRef engine);
JunimoCorePomodoroSnapshot junimo_core_active_pomodoro(JunimoCoreEngineRef engine);
int junimo_core_has_active_pomodoro(JunimoCoreEngineRef engine);
const char* junimo_core_active_pomodoro_title(JunimoCoreEngineRef engine);
long long junimo_core_active_pomodoro_started_at(JunimoCoreEngineRef engine);
long long junimo_core_active_pomodoro_duration(JunimoCoreEngineRef engine);

JunimoCoreActionResult junimo_core_run_action(
    JunimoCoreEngineRef engine,
    const char* action_id,
    long long unix_seconds
);

void junimo_core_record_activity(
    JunimoCoreEngineRef engine,
    const char* title,
    const char* detail,
    long long unix_seconds
);

void junimo_core_start_pomodoro(
    JunimoCoreEngineRef engine,
    long long duration_seconds,
    long long unix_seconds
);

JunimoCorePomodoroResult junimo_core_cancel_pomodoro(
    JunimoCoreEngineRef engine,
    long long unix_seconds
);

JunimoCorePomodoroResult junimo_core_advance_time(
    JunimoCoreEngineRef engine,
    long long unix_seconds
);

JunimoCoreCommandList junimo_core_search_commands(
    JunimoCoreEngineRef engine,
    const char* query
);

JunimoCoreProjectProfileSnapshot junimo_core_project_profile(
    JunimoCoreEngineRef engine
);

JunimoCoreSessionList junimo_core_recent_sessions(
    JunimoCoreEngineRef engine
);

JunimoCoreUiPreferencesSnapshot junimo_core_ui_preferences(
    JunimoCoreEngineRef engine
);

JunimoCoreUiPreferencesSnapshot junimo_core_set_accent(
    JunimoCoreEngineRef engine,
    const char* accent
);

JunimoCoreUiPreferencesSnapshot junimo_core_set_density(
    JunimoCoreEngineRef engine,
    const char* density
);

const char* junimo_core_ui_accent(JunimoCoreEngineRef engine);
const char* junimo_core_ui_density(JunimoCoreEngineRef engine);
int junimo_core_ui_expanded_width(JunimoCoreEngineRef engine);
int junimo_core_ui_expanded_height(JunimoCoreEngineRef engine);
int junimo_core_ui_top_offset(JunimoCoreEngineRef engine);
void junimo_core_update_accent(JunimoCoreEngineRef engine, const char* accent);
void junimo_core_update_density(JunimoCoreEngineRef engine, const char* density);

JunimoCoreCornerNoteSnapshot junimo_core_corner_note(JunimoCoreEngineRef engine);
JunimoCoreCornerNoteSnapshot junimo_core_update_corner_note_text(
    JunimoCoreEngineRef engine,
    const char* text
);
JunimoCoreCornerNoteSnapshot junimo_core_add_corner_todo(
    JunimoCoreEngineRef engine,
    const char* title
);
JunimoCoreCornerNoteSnapshot junimo_core_update_corner_todo_title(
    JunimoCoreEngineRef engine,
    const char* id,
    const char* title
);
JunimoCoreCornerNoteSnapshot junimo_core_toggle_corner_todo(
    JunimoCoreEngineRef engine,
    const char* id
);
JunimoCoreCornerNoteSnapshot junimo_core_remove_corner_todo(
    JunimoCoreEngineRef engine,
    const char* id
);

#ifdef __cplusplus
}
#endif
