#include "junimo/core/models.hpp"

#include <algorithm>

namespace junimo::core {

TimePoint PomodoroSession::ends_at() const {
    return started_at + duration;
}

Seconds PomodoroSession::remaining_at(TimePoint now) const {
    if (now >= ends_at()) {
        return Seconds{0};
    }
    return std::chrono::duration_cast<Seconds>(ends_at() - now);
}

bool PomodoroSession::complete_at(TimePoint now) const {
    return now >= ends_at();
}

std::string_view status_label(AgentStatus status) {
    switch (status) {
        case AgentStatus::idle:
            return "Idle";
        case AgentStatus::running:
            return "Running";
        case AgentStatus::succeeded:
            return "Ready";
        case AgentStatus::failed:
            return "Needs attention";
    }
    return "Unknown";
}

std::string_view session_status_label(SessionStatus status) {
    switch (status) {
        case SessionStatus::queued:
            return "Queued";
        case SessionStatus::running:
            return "Running";
        case SessionStatus::succeeded:
            return "Done";
        case SessionStatus::failed:
            return "Failed";
    }
    return "Unknown";
}

}  // namespace junimo::core
