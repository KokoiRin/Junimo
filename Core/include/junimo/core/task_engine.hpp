#pragma once

#include "junimo/core/models.hpp"

#include <optional>
#include <span>
#include <vector>

namespace junimo::core {

class TaskEngine {
public:
    TaskEngine();

    [[nodiscard]] std::span<const Agent> agents() const;
    [[nodiscard]] std::span<const Action> actions() const;
    [[nodiscard]] std::span<const Activity> activities() const;
    [[nodiscard]] std::span<const ExecutionSession> sessions() const;
    [[nodiscard]] std::span<const CommandEntry> commands() const;
    [[nodiscard]] const ProjectProfile& project_profile() const;
    [[nodiscard]] const UiPreferences& ui_preferences() const;
    [[nodiscard]] const UiPreferences& set_accent(std::string_view accent);
    [[nodiscard]] const UiPreferences& set_density(std::string_view density);
    [[nodiscard]] std::vector<CommandEntry> search_commands(std::string_view query, std::size_t limit = 8) const;

    [[nodiscard]] std::optional<Activity> run_action(std::string_view action_id, TimePoint now);

    void start_pomodoro(Seconds duration, TimePoint now);
    [[nodiscard]] bool cancel_pomodoro(TimePoint now);
    [[nodiscard]] std::optional<NotificationRequest> advance_time(TimePoint now);

    [[nodiscard]] const std::optional<PomodoroSession>& active_pomodoro() const;

private:
    std::vector<Agent> agents_;
    std::vector<Action> actions_;
    std::vector<CommandEntry> commands_;
    ProjectProfile project_profile_;
    UiPreferences ui_preferences_;
    std::vector<ExecutionSession> sessions_;
    std::vector<Activity> activities_;
    std::optional<PomodoroSession> active_pomodoro_;

    void record(Activity activity);
    void record_session(ExecutionSession session);
    void record_session_for_action(const Action& action, const Activity& activity, TimePoint now);
    Agent* find_agent(std::string_view id);
    const Action* find_action(std::string_view id) const;
};

}  // namespace junimo::core
