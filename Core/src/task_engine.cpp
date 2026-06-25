#include "junimo/core/task_engine.hpp"

#include <algorithm>
#include <cctype>

namespace junimo::core {

namespace {

std::string lowercase(std::string_view value) {
    std::string lowered;
    lowered.reserve(value.size());
    for (const char character : value) {
        lowered.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(character))));
    }
    return lowered;
}

bool contains_case_insensitive(std::string_view haystack, std::string_view needle) {
    if (needle.empty()) {
        return true;
    }
    return lowercase(haystack).find(lowercase(needle)) != std::string::npos;
}

bool command_matches(const CommandEntry& command, std::string_view query) {
    if (contains_case_insensitive(command.title, query) ||
        contains_case_insensitive(command.subtitle, query) ||
        contains_case_insensitive(command.category, query)) {
        return true;
    }

    return std::ranges::any_of(command.tags, [query](const std::string& tag) {
        return contains_case_insensitive(tag, query);
    });
}

}  // namespace

TaskEngine::TaskEngine()
    : agents_{
          Agent{.id = "codex", .name = "Codex", .status = AgentStatus::idle, .detail = "Ready for local coding tasks"},
          Agent{.id = "hermes", .name = "Hermes", .status = AgentStatus::idle, .detail = "Ready for orchestration"},
      },
      actions_{
          Action{.id = "codex", .title = "Codex", .subtitle = "Start local coding agent", .kind = ActionKind::agent, .agent_id = "codex"},
          Action{.id = "hermes", .title = "Hermes", .subtitle = "Start mock orchestration", .kind = ActionKind::agent, .agent_id = "hermes"},
          Action{.id = "open-project", .title = "Project", .subtitle = "Queue project shortcut", .kind = ActionKind::project},
          Action{.id = "dev-tools", .title = "Tools", .subtitle = "Queue developer tools", .kind = ActionKind::tool},
      },
      commands_{
          CommandEntry{.id = "codex", .title = "Start Codex", .subtitle = "Queue the local coding agent", .category = "Agents", .tags = {"agent", "coding", "local"}},
          CommandEntry{.id = "hermes", .title = "Start Hermes", .subtitle = "Queue orchestration workflow", .category = "Agents", .tags = {"agent", "orchestration"}},
          CommandEntry{.id = "open-project", .title = "Open Project", .subtitle = "Focus the current Junimo workspace", .category = "Project", .tags = {"workspace", "folder", "repo"}},
          CommandEntry{.id = "dev-tools", .title = "Developer Tools", .subtitle = "Queue local development utilities", .category = "Tools", .tags = {"tool", "build", "test"}},
          CommandEntry{.id = "pomodoro-25", .title = "Start 25m Focus", .subtitle = "Create a Pomodoro focus session", .category = "Focus", .tags = {"timer", "pomodoro", "focus"}},
          CommandEntry{.id = "pomodoro-10s", .title = "Start 10s Focus", .subtitle = "Create a short validation timer", .category = "Focus", .tags = {"timer", "debug", "focus"}},
      },
      project_profile_{
          .name = "Junimo",
          .path = "/Users/guoysh/Documents/Junimo",
          .stack = "Swift/AppKit shell + C++23 core",
          .shortcuts = {"Build app", "Run tests", "OpenSpec validate"},
      } {}

std::span<const Agent> TaskEngine::agents() const {
    return agents_;
}

std::span<const Action> TaskEngine::actions() const {
    return actions_;
}

std::span<const Activity> TaskEngine::activities() const {
    return activities_;
}

std::span<const ExecutionSession> TaskEngine::sessions() const {
    return sessions_;
}

std::span<const CommandEntry> TaskEngine::commands() const {
    return commands_;
}

const ProjectProfile& TaskEngine::project_profile() const {
    return project_profile_;
}

const UiPreferences& TaskEngine::ui_preferences() const {
    return ui_preferences_;
}

const UiPreferences& TaskEngine::set_accent(std::string_view accent) {
    const std::string value{accent};
    if (value == "mint" || value == "amber" || value == "graphite") {
        ui_preferences_.accent = value;
    }
    return ui_preferences_;
}

const UiPreferences& TaskEngine::set_density(std::string_view density) {
    const std::string value{density};
    if (value == "compact") {
        ui_preferences_.density = value;
        ui_preferences_.expanded_width = 700;
        ui_preferences_.expanded_height = 470;
    } else if (value == "comfortable") {
        ui_preferences_.density = value;
        ui_preferences_.expanded_width = 760;
        ui_preferences_.expanded_height = 220;
    }
    return ui_preferences_;
}

std::vector<CommandEntry> TaskEngine::search_commands(std::string_view query, std::size_t limit) const {
    std::vector<CommandEntry> results;
    for (const auto& command : commands_) {
        if (command_matches(command, query)) {
            results.push_back(command);
            if (results.size() >= limit) {
                break;
            }
        }
    }
    return results;
}

std::optional<Activity> TaskEngine::run_action(std::string_view action_id, TimePoint now) {
    if (action_id == "pomodoro-25") {
        start_pomodoro(Seconds{25 * 60}, now);
        return activities_.front();
    }
    if (action_id == "pomodoro-10s") {
        start_pomodoro(Seconds{10}, now);
        return activities_.front();
    }

    const Action* action = find_action(action_id);
    if (action == nullptr) {
        return std::nullopt;
    }

    Activity activity{
        .title = action->title + " queued",
        .detail = "Action routed through C++ core task engine",
        .created_at = now,
    };

    if (action->id == "codex") {
        activity.title = "Started Codex";
        activity.detail = "C++ core marked Codex as running";
    } else if (action->id == "hermes") {
        activity.title = "Started Hermes";
        activity.detail = "C++ core marked Hermes as running";
    }

    if (action->agent_id.has_value()) {
        if (Agent* agent = find_agent(*action->agent_id)) {
            agent->status = AgentStatus::running;
            agent->detail = activity.detail;
        }
    }

    record_session_for_action(*action, activity, now);
    record(activity);
    return activity;
}

void TaskEngine::start_pomodoro(Seconds duration, TimePoint now) {
    active_pomodoro_ = PomodoroSession{
        .title = "Focus",
        .started_at = now,
        .duration = duration,
    };
    record_session(ExecutionSession{
        .id = "pomodoro",
        .title = "Pomodoro focus",
        .detail = "Focus session running",
        .status = SessionStatus::running,
        .started_at = now,
    });
    record(Activity{
        .title = "Pomodoro started",
        .detail = "Focus session created in C++ core",
        .created_at = now,
    });
}

bool TaskEngine::cancel_pomodoro(TimePoint now) {
    if (!active_pomodoro_.has_value()) {
        return false;
    }
    active_pomodoro_.reset();
    record(Activity{
        .title = "Pomodoro cancelled",
        .detail = "Focus session stopped in C++ core",
        .created_at = now,
    });
    return true;
}

std::optional<NotificationRequest> TaskEngine::advance_time(TimePoint now) {
    if (!active_pomodoro_.has_value() || !active_pomodoro_->complete_at(now)) {
        return std::nullopt;
    }

    active_pomodoro_.reset();
    NotificationRequest request{
        .title = "Pomodoro complete",
        .body = "Focus session finished.",
        .created_at = now,
    };
    record(Activity{
        .title = "Pomodoro complete",
        .detail = "Reminder request created in C++ core",
        .created_at = now,
    });
    return request;
}

const std::optional<PomodoroSession>& TaskEngine::active_pomodoro() const {
    return active_pomodoro_;
}

void TaskEngine::record(Activity activity) {
    activities_.insert(activities_.begin(), std::move(activity));
    if (activities_.size() > 16) {
        activities_.resize(16);
    }
}

void TaskEngine::record_session(ExecutionSession session) {
    sessions_.insert(sessions_.begin(), std::move(session));
    if (sessions_.size() > 12) {
        sessions_.resize(12);
    }
}

void TaskEngine::record_session_for_action(const Action& action, const Activity& activity, TimePoint now) {
    const bool is_agent = action.kind == ActionKind::agent;
    record_session(ExecutionSession{
        .id = action.id,
        .title = activity.title,
        .detail = activity.detail,
        .status = is_agent ? SessionStatus::running : SessionStatus::succeeded,
        .started_at = now,
    });
}

Agent* TaskEngine::find_agent(std::string_view id) {
    auto it = std::ranges::find_if(agents_, [id](const Agent& agent) {
        return agent.id == id;
    });
    return it == agents_.end() ? nullptr : &*it;
}

const Action* TaskEngine::find_action(std::string_view id) const {
    auto it = std::ranges::find_if(actions_, [id](const Action& action) {
        return action.id == id;
    });
    return it == actions_.end() ? nullptr : &*it;
}

}  // namespace junimo::core
