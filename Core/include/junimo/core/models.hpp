#pragma once

#include <chrono>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace junimo::core {

using Clock = std::chrono::system_clock;
using TimePoint = Clock::time_point;
using Seconds = std::chrono::seconds;

enum class AgentStatus {
    idle,
    running,
    succeeded,
    failed
};

enum class ActionKind {
    agent,
    tool,
    project
};

enum class SessionStatus {
    queued,
    running,
    succeeded,
    failed
};

struct Agent {
    std::string id;
    std::string name;
    AgentStatus status = AgentStatus::idle;
    std::string detail;
};

struct Action {
    std::string id;
    std::string title;
    std::string subtitle;
    ActionKind kind = ActionKind::tool;
    std::optional<std::string> agent_id;
};

struct Activity {
    std::string title;
    std::string detail;
    TimePoint created_at;
};

struct NotificationRequest {
    std::string title;
    std::string body;
    TimePoint created_at;
};

struct CommandEntry {
    std::string id;
    std::string title;
    std::string subtitle;
    std::string category;
    std::vector<std::string> tags;
};

struct ProjectProfile {
    std::string name;
    std::string path;
    std::string stack;
    std::vector<std::string> shortcuts;
};

struct UiPreferences {
    std::string accent = "mint";
    std::string density = "comfortable";
    int expanded_width = 760;
    int expanded_height = 220;
    int top_offset = 6;
};

struct ExecutionSession {
    std::string id;
    std::string title;
    std::string detail;
    SessionStatus status = SessionStatus::queued;
    TimePoint started_at;
};

struct PomodoroSession {
    std::string title = "Focus";
    TimePoint started_at;
    Seconds duration{25 * 60};

    [[nodiscard]] TimePoint ends_at() const;
    [[nodiscard]] Seconds remaining_at(TimePoint now) const;
    [[nodiscard]] bool complete_at(TimePoint now) const;
};

[[nodiscard]] std::string_view status_label(AgentStatus status);
[[nodiscard]] std::string_view session_status_label(SessionStatus status);

}  // namespace junimo::core
