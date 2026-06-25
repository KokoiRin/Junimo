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
thread_local std::string pomodoro_title_storage;
thread_local std::string pomodoro_detail_storage;
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

}  // namespace

extern "C" JunimoCoreEngineRef junimo_core_engine_create(void) {
    return new JunimoCoreEngine{};
}

extern "C" void junimo_core_engine_destroy(JunimoCoreEngineRef engine) {
    delete engine;
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
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 540, 6};
    }
    return preferences_snapshot(engine->engine.ui_preferences());
}

extern "C" JunimoCoreUiPreferencesSnapshot junimo_core_set_accent(
    JunimoCoreEngineRef engine,
    const char* accent
) {
    if (engine == nullptr) {
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 540, 6};
    }
    return preferences_snapshot(engine->engine.set_accent(accent == nullptr ? "" : accent));
}

extern "C" JunimoCoreUiPreferencesSnapshot junimo_core_set_density(
    JunimoCoreEngineRef engine,
    const char* density
) {
    if (engine == nullptr) {
        return JunimoCoreUiPreferencesSnapshot{"mint", "comfortable", 760, 540, 6};
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
    return engine == nullptr ? 540 : engine->engine.ui_preferences().expanded_height;
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
