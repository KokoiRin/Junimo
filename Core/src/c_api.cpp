#include "junimo/core/c_api.h"
#include "junimo/core/task_engine.hpp"

#include <chrono>
#include <array>
#include <string>
#include <vector>

struct JunimoCoreEngine {
    junimo::core::TaskEngine engine;
};

namespace {

using junimo::core::Seconds;
using junimo::core::TimePoint;

thread_local std::string action_title_storage;
thread_local std::string action_detail_storage;
thread_local std::string action_agent_storage;
thread_local std::array<std::string, 8> agent_id_storage;
thread_local std::array<std::string, 8> agent_name_storage;
thread_local std::array<std::string, 8> agent_detail_storage;
thread_local std::array<std::string, 8> action_id_list_storage;
thread_local std::array<std::string, 8> action_title_list_storage;
thread_local std::array<std::string, 8> action_subtitle_list_storage;
thread_local std::array<std::string, 8> action_agent_id_list_storage;
thread_local std::array<std::string, 8> activity_title_storage;
thread_local std::array<std::string, 8> activity_detail_storage;
thread_local std::string pomodoro_title_storage;
thread_local std::string pomodoro_detail_storage;
thread_local std::string active_pomodoro_title_storage;
thread_local std::string notification_title_storage;
thread_local std::string notification_body_storage;
thread_local std::array<std::string, 8> command_id_storage;
thread_local std::array<std::string, 8> command_title_storage;
thread_local std::array<std::string, 8> command_subtitle_storage;
thread_local std::array<std::string, 8> command_category_storage;
thread_local std::string profile_name_storage;
thread_local std::string profile_path_storage;
thread_local std::string profile_stack_storage;
thread_local std::array<std::string, 3> profile_shortcut_storage;
thread_local std::array<std::string, 6> session_id_storage;
thread_local std::array<std::string, 6> session_title_storage;
thread_local std::array<std::string, 6> session_detail_storage;
thread_local std::array<std::string, 6> session_status_storage;
thread_local std::string preferences_accent_storage;
thread_local std::string preferences_density_storage;
thread_local std::string corner_note_text_storage;
thread_local std::array<std::string, 16> corner_todo_id_storage;
thread_local std::array<std::string, 16> corner_todo_title_storage;

TimePoint from_unix_seconds(long long unix_seconds) {
    return TimePoint{Seconds{unix_seconds}};
}

int to_c_status(junimo::core::AgentStatus status) {
    switch (status) {
        case junimo::core::AgentStatus::idle:
            return 0;
        case junimo::core::AgentStatus::running:
            return 1;
        case junimo::core::AgentStatus::succeeded:
            return 2;
        case junimo::core::AgentStatus::failed:
            return 3;
    }
    return 0;
}

int to_c_action_kind(junimo::core::ActionKind kind) {
    switch (kind) {
        case junimo::core::ActionKind::agent:
            return 0;
        case junimo::core::ActionKind::tool:
            return 1;
        case junimo::core::ActionKind::project:
            return 2;
    }
    return 1;
}

int to_c_session_status(junimo::core::SessionStatus status) {
    switch (status) {
        case junimo::core::SessionStatus::queued:
            return 0;
        case junimo::core::SessionStatus::running:
            return 1;
        case junimo::core::SessionStatus::succeeded:
            return 2;
        case junimo::core::SessionStatus::failed:
            return 3;
    }
    return 0;
}

long long to_unix_seconds(junimo::core::TimePoint time_point) {
    return std::chrono::duration_cast<Seconds>(time_point.time_since_epoch()).count();
}

JunimoCorePomodoroResult empty_pomodoro_result() {
    return JunimoCorePomodoroResult{
        .changed = 0,
        .completed = 0,
        .activity_title = "",
        .activity_detail = "",
        .notification_title = "",
        .notification_body = "",
    };
}

JunimoCoreUiPreferencesSnapshot preferences_snapshot(const junimo::core::UiPreferences& preferences) {
    preferences_accent_storage = preferences.accent;
    preferences_density_storage = preferences.density;
    return JunimoCoreUiPreferencesSnapshot{
        .accent = preferences_accent_storage.c_str(),
        .density = preferences_density_storage.c_str(),
        .expanded_width = preferences.expanded_width,
        .expanded_height = preferences.expanded_height,
        .top_offset = preferences.top_offset,
    };
}

JunimoCoreCornerNoteSnapshot corner_note_snapshot(const junimo::core::CornerNote& note) {
    JunimoCoreCornerNoteSnapshot snapshot{};
    corner_note_text_storage = note.text;
    snapshot.text = corner_note_text_storage.c_str();
    snapshot.todo_count = static_cast<int>(std::min<std::size_t>(note.todos.size(), corner_todo_id_storage.size()));

    for (std::size_t index = 0; index < note.todos.size() && index < corner_todo_id_storage.size(); ++index) {
        corner_todo_id_storage[index] = note.todos[index].id;
        corner_todo_title_storage[index] = note.todos[index].title;
        snapshot.todos[index] = JunimoCoreCornerTodoSnapshot{
            .id = corner_todo_id_storage[index].c_str(),
            .title = corner_todo_title_storage[index].c_str(),
            .is_done = note.todos[index].is_done ? 1 : 0,
        };
    }

    return snapshot;
}

}  // namespace

extern "C" JunimoCoreEngineRef junimo_core_engine_create(void) {
    return new JunimoCoreEngine{};
}

extern "C" void junimo_core_engine_destroy(JunimoCoreEngineRef engine) {
    delete engine;
}

extern "C" JunimoCoreAgentList junimo_core_agents(JunimoCoreEngineRef engine) {
    JunimoCoreAgentList list{};
    if (engine == nullptr) {
        return list;
    }

    const auto agents = engine->engine.agents();
    list.count = static_cast<int>(std::min<std::size_t>(agents.size(), agent_id_storage.size()));
    for (std::size_t index = 0; index < agents.size() && index < agent_id_storage.size(); ++index) {
        agent_id_storage[index] = agents[index].id;
        agent_name_storage[index] = agents[index].name;
        agent_detail_storage[index] = agents[index].detail;
        list.items[index] = JunimoCoreAgentSnapshot{
            .id = agent_id_storage[index].c_str(),
            .name = agent_name_storage[index].c_str(),
            .detail = agent_detail_storage[index].c_str(),
            .status = to_c_status(agents[index].status),
        };
    }
    return list;
}

extern "C" JunimoCoreActionList junimo_core_actions(JunimoCoreEngineRef engine) {
    JunimoCoreActionList list{};
    if (engine == nullptr) {
        return list;
    }

    const auto actions = engine->engine.actions();
    list.count = static_cast<int>(std::min<std::size_t>(actions.size(), action_id_list_storage.size()));
    for (std::size_t index = 0; index < actions.size() && index < action_id_list_storage.size(); ++index) {
        action_id_list_storage[index] = actions[index].id;
        action_title_list_storage[index] = actions[index].title;
        action_subtitle_list_storage[index] = actions[index].subtitle;
        action_agent_id_list_storage[index] = actions[index].agent_id.value_or("");
        list.items[index] = JunimoCoreActionSnapshot{
            .id = action_id_list_storage[index].c_str(),
            .title = action_title_list_storage[index].c_str(),
            .subtitle = action_subtitle_list_storage[index].c_str(),
            .kind = to_c_action_kind(actions[index].kind),
            .agent_id = action_agent_id_list_storage[index].c_str(),
        };
    }
    return list;
}

extern "C" JunimoCoreActivityList junimo_core_recent_activities(JunimoCoreEngineRef engine) {
    JunimoCoreActivityList list{};
    if (engine == nullptr) {
        return list;
    }

    const auto activities = engine->engine.activities();
    list.count = static_cast<int>(std::min<std::size_t>(activities.size(), activity_title_storage.size()));
    for (std::size_t index = 0; index < activities.size() && index < activity_title_storage.size(); ++index) {
        activity_title_storage[index] = activities[index].title;
        activity_detail_storage[index] = activities[index].detail;
        list.items[index] = JunimoCoreActivitySnapshot{
            .title = activity_title_storage[index].c_str(),
            .detail = activity_detail_storage[index].c_str(),
            .created_at_unix_seconds = to_unix_seconds(activities[index].created_at),
        };
    }
    return list;
}

extern "C" JunimoCorePomodoroSnapshot junimo_core_active_pomodoro(JunimoCoreEngineRef engine) {
    if (engine == nullptr || !engine->engine.active_pomodoro().has_value()) {
        return JunimoCorePomodoroSnapshot{
            .has_active = 0,
            .title = "",
            .started_at_unix_seconds = 0,
            .duration_seconds = 0,
        };
    }

    const auto& pomodoro = *engine->engine.active_pomodoro();
    active_pomodoro_title_storage = pomodoro.title;
    return JunimoCorePomodoroSnapshot{
        .has_active = 1,
        .title = active_pomodoro_title_storage.c_str(),
        .started_at_unix_seconds = to_unix_seconds(pomodoro.started_at),
        .duration_seconds = pomodoro.duration.count(),
    };
}

extern "C" int junimo_core_has_active_pomodoro(JunimoCoreEngineRef engine) {
    return engine != nullptr && engine->engine.active_pomodoro().has_value() ? 1 : 0;
}

extern "C" const char* junimo_core_active_pomodoro_title(JunimoCoreEngineRef engine) {
    if (engine == nullptr || !engine->engine.active_pomodoro().has_value()) {
        return "";
    }
    active_pomodoro_title_storage = engine->engine.active_pomodoro()->title;
    return active_pomodoro_title_storage.c_str();
}

extern "C" long long junimo_core_active_pomodoro_started_at(JunimoCoreEngineRef engine) {
    if (engine == nullptr || !engine->engine.active_pomodoro().has_value()) {
        return 0;
    }
    return to_unix_seconds(engine->engine.active_pomodoro()->started_at);
}

extern "C" long long junimo_core_active_pomodoro_duration(JunimoCoreEngineRef engine) {
    if (engine == nullptr || !engine->engine.active_pomodoro().has_value()) {
        return 0;
    }
    return engine->engine.active_pomodoro()->duration.count();
}

extern "C" JunimoCoreActionResult junimo_core_run_action(
    JunimoCoreEngineRef engine,
    const char* action_id,
    long long unix_seconds
) {
    if (engine == nullptr || action_id == nullptr) {
        return JunimoCoreActionResult{0, "", "", "", 0};
    }

    const auto activity = engine->engine.run_action(action_id, from_unix_seconds(unix_seconds));
    if (!activity.has_value()) {
        return JunimoCoreActionResult{0, "", "", "", 0};
    }

    action_title_storage = activity->title;
    action_detail_storage = activity->detail;
    action_agent_storage.clear();
    int status = 0;

    for (const auto& agent : engine->engine.agents()) {
        if (agent.status == junimo::core::AgentStatus::running && action_detail_storage == agent.detail) {
            action_agent_storage = agent.id;
            status = to_c_status(agent.status);
            break;
        }
    }

    return JunimoCoreActionResult{
        .handled = 1,
        .activity_title = action_title_storage.c_str(),
        .activity_detail = action_detail_storage.c_str(),
        .agent_id = action_agent_storage.c_str(),
        .agent_status = status,
    };
}

extern "C" void junimo_core_record_activity(
    JunimoCoreEngineRef engine,
    const char* title,
    const char* detail,
    long long unix_seconds
) {
    if (engine == nullptr) {
        return;
    }
    engine->engine.record_activity(
        title == nullptr ? "" : title,
        detail == nullptr ? "" : detail,
        from_unix_seconds(unix_seconds)
    );
}

extern "C" void junimo_core_start_pomodoro(
    JunimoCoreEngineRef engine,
    long long duration_seconds,
    long long unix_seconds
) {
    if (engine == nullptr) {
        return;
    }
    engine->engine.start_pomodoro(Seconds{duration_seconds}, from_unix_seconds(unix_seconds));
}

extern "C" JunimoCorePomodoroResult junimo_core_cancel_pomodoro(
    JunimoCoreEngineRef engine,
    long long unix_seconds
) {
    if (engine == nullptr) {
        return empty_pomodoro_result();
    }

    const bool changed = engine->engine.cancel_pomodoro(from_unix_seconds(unix_seconds));
    if (!changed) {
        return empty_pomodoro_result();
    }

    const auto& activity = engine->engine.activities().front();
    pomodoro_title_storage = activity.title;
    pomodoro_detail_storage = activity.detail;

    return JunimoCorePomodoroResult{
        .changed = 1,
        .completed = 0,
        .activity_title = pomodoro_title_storage.c_str(),
        .activity_detail = pomodoro_detail_storage.c_str(),
        .notification_title = "",
        .notification_body = "",
    };
}

extern "C" JunimoCorePomodoroResult junimo_core_advance_time(
    JunimoCoreEngineRef engine,
    long long unix_seconds
) {
    if (engine == nullptr) {
        return empty_pomodoro_result();
    }

    const auto notification = engine->engine.advance_time(from_unix_seconds(unix_seconds));
    if (!notification.has_value()) {
        return empty_pomodoro_result();
    }

    const auto& activity = engine->engine.activities().front();
    pomodoro_title_storage = activity.title;
    pomodoro_detail_storage = activity.detail;
    notification_title_storage = notification->title;
    notification_body_storage = notification->body;

    return JunimoCorePomodoroResult{
        .changed = 1,
        .completed = 1,
        .activity_title = pomodoro_title_storage.c_str(),
        .activity_detail = pomodoro_detail_storage.c_str(),
        .notification_title = notification_title_storage.c_str(),
        .notification_body = notification_body_storage.c_str(),
    };
}

extern "C" JunimoCoreCommandList junimo_core_search_commands(
    JunimoCoreEngineRef engine,
    const char* query
) {
    JunimoCoreCommandList list{};
    if (engine == nullptr) {
        return list;
    }

    const auto results = engine->engine.search_commands(query == nullptr ? "" : query, 8);
    list.count = static_cast<int>(results.size());

    for (std::size_t index = 0; index < results.size() && index < 8; ++index) {
        command_id_storage[index] = results[index].id;
        command_title_storage[index] = results[index].title;
        command_subtitle_storage[index] = results[index].subtitle;
        command_category_storage[index] = results[index].category;
        list.items[index] = JunimoCoreCommandSnapshot{
            .id = command_id_storage[index].c_str(),
            .title = command_title_storage[index].c_str(),
            .subtitle = command_subtitle_storage[index].c_str(),
            .category = command_category_storage[index].c_str(),
        };
    }

    return list;
}

extern "C" JunimoCoreProjectProfileSnapshot junimo_core_project_profile(
    JunimoCoreEngineRef engine
) {
    if (engine == nullptr) {
        return JunimoCoreProjectProfileSnapshot{"", "", "", "", "", ""};
    }

    const auto& profile = engine->engine.project_profile();
    profile_name_storage = profile.name;
    profile_path_storage = profile.path;
    profile_stack_storage = profile.stack;

    for (std::size_t index = 0; index < profile_shortcut_storage.size(); ++index) {
        profile_shortcut_storage[index] = index < profile.shortcuts.size() ? profile.shortcuts[index] : "";
    }

    return JunimoCoreProjectProfileSnapshot{
        .name = profile_name_storage.c_str(),
        .path = profile_path_storage.c_str(),
        .stack = profile_stack_storage.c_str(),
        .shortcut_1 = profile_shortcut_storage[0].c_str(),
        .shortcut_2 = profile_shortcut_storage[1].c_str(),
        .shortcut_3 = profile_shortcut_storage[2].c_str(),
    };
}

extern "C" JunimoCoreSessionList junimo_core_recent_sessions(
    JunimoCoreEngineRef engine
) {
    JunimoCoreSessionList list{};
    if (engine == nullptr) {
        return list;
    }

    const auto sessions = engine->engine.sessions();
    list.count = static_cast<int>(std::min<std::size_t>(sessions.size(), 6));

    for (std::size_t index = 0; index < sessions.size() && index < 6; ++index) {
        session_id_storage[index] = sessions[index].id;
        session_title_storage[index] = sessions[index].title;
        session_detail_storage[index] = sessions[index].detail;
        session_status_storage[index] = std::string(junimo::core::session_status_label(sessions[index].status));
        list.items[index] = JunimoCoreSessionSnapshot{
            .id = session_id_storage[index].c_str(),
            .title = session_title_storage[index].c_str(),
            .detail = session_detail_storage[index].c_str(),
            .status_label = session_status_storage[index].c_str(),
            .status = to_c_session_status(sessions[index].status),
            .started_at_unix_seconds = to_unix_seconds(sessions[index].started_at),
        };
    }

    return list;
}

extern "C" JunimoCoreUiPreferencesSnapshot junimo_core_ui_preferences(
    JunimoCoreEngineRef engine
) {
    if (engine == nullptr) {
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 220, 6};
    }
    return preferences_snapshot(engine->engine.ui_preferences());
}

extern "C" JunimoCoreUiPreferencesSnapshot junimo_core_set_accent(
    JunimoCoreEngineRef engine,
    const char* accent
) {
    if (engine == nullptr) {
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 220, 6};
    }
    return preferences_snapshot(engine->engine.set_accent(accent == nullptr ? "" : accent));
}

extern "C" JunimoCoreUiPreferencesSnapshot junimo_core_set_density(
    JunimoCoreEngineRef engine,
    const char* density
) {
    if (engine == nullptr) {
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 220, 6};
    }
    return preferences_snapshot(engine->engine.set_density(density == nullptr ? "" : density));
}

extern "C" const char* junimo_core_ui_accent(JunimoCoreEngineRef engine) {
    if (engine == nullptr) {
        return "mint";
    }
    preferences_accent_storage = engine->engine.ui_preferences().accent;
    return preferences_accent_storage.c_str();
}

extern "C" const char* junimo_core_ui_density(JunimoCoreEngineRef engine) {
    if (engine == nullptr) {
        return "comfortable";
    }
    preferences_density_storage = engine->engine.ui_preferences().density;
    return preferences_density_storage.c_str();
}

extern "C" int junimo_core_ui_expanded_width(JunimoCoreEngineRef engine) {
    return engine == nullptr ? 760 : engine->engine.ui_preferences().expanded_width;
}

extern "C" int junimo_core_ui_expanded_height(JunimoCoreEngineRef engine) {
    return engine == nullptr ? 220 : engine->engine.ui_preferences().expanded_height;
}

extern "C" int junimo_core_ui_top_offset(JunimoCoreEngineRef engine) {
    return engine == nullptr ? 6 : engine->engine.ui_preferences().top_offset;
}

extern "C" void junimo_core_update_accent(JunimoCoreEngineRef engine, const char* accent) {
    if (engine == nullptr) {
        return;
    }
    (void)engine->engine.set_accent(accent == nullptr ? "" : accent);
}

extern "C" void junimo_core_update_density(JunimoCoreEngineRef engine, const char* density) {
    if (engine == nullptr) {
        return;
    }
    (void)engine->engine.set_density(density == nullptr ? "" : density);
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_corner_note(JunimoCoreEngineRef engine) {
    if (engine == nullptr) {
        return corner_note_snapshot(junimo::core::CornerNote{
            .text = "Quick note",
            .todos = {},
        });
    }
    return corner_note_snapshot(engine->engine.corner_note());
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_update_corner_note_text(
    JunimoCoreEngineRef engine,
    const char* text
) {
    if (engine == nullptr) {
        return junimo_core_corner_note(engine);
    }
    return corner_note_snapshot(engine->engine.update_corner_note_text(text == nullptr ? "" : text));
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_add_corner_todo(
    JunimoCoreEngineRef engine,
    const char* title
) {
    if (engine == nullptr) {
        return junimo_core_corner_note(engine);
    }
    return corner_note_snapshot(engine->engine.add_corner_todo(title == nullptr ? "" : title));
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_update_corner_todo_title(
    JunimoCoreEngineRef engine,
    const char* id,
    const char* title
) {
    if (engine == nullptr) {
        return junimo_core_corner_note(engine);
    }
    return corner_note_snapshot(engine->engine.update_corner_todo_title(id == nullptr ? "" : id, title == nullptr ? "" : title));
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_toggle_corner_todo(
    JunimoCoreEngineRef engine,
    const char* id
) {
    if (engine == nullptr) {
        return junimo_core_corner_note(engine);
    }
    return corner_note_snapshot(engine->engine.toggle_corner_todo(id == nullptr ? "" : id));
}

extern "C" JunimoCoreCornerNoteSnapshot junimo_core_remove_corner_todo(
    JunimoCoreEngineRef engine,
    const char* id
) {
    if (engine == nullptr) {
        return junimo_core_corner_note(engine);
    }
    return corner_note_snapshot(engine->engine.remove_corner_todo(id == nullptr ? "" : id));
}
