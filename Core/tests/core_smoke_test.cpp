#include "junimo/core/task_engine.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "Test failed: " << message << '\n';
        std::exit(1);
    }
}

}  // namespace

int main() {
    using namespace junimo::core;
    using namespace std::chrono_literals;

    const TimePoint start{Seconds{100}};

    TaskEngine engine;
    auto all_commands = engine.search_commands("", 8);
    expect(all_commands.size() >= 6, "empty command query should return default commands");

    auto focus_commands = engine.search_commands("focus", 8);
    expect(!focus_commands.empty(), "focus query should return commands");
    expect(std::ranges::any_of(focus_commands, [](const CommandEntry& command) {
        return command.id == "pomodoro-25" || command.id == "pomodoro-10s";
    }), "focus query should match focus commands");

    auto project_profile = engine.project_profile();
    expect(project_profile.name == "Junimo", "project profile should expose Junimo");
    expect(project_profile.stack.find("C++23") != std::string::npos, "project profile should mention C++23");

    expect(engine.ui_preferences().accent == "mint", "default accent should be mint");
    expect(engine.ui_preferences().expanded_width == 760, "comfortable width should be default");
    expect(engine.ui_preferences().expanded_height == 220, "comfortable height should be default");
    const auto& amber_preferences = engine.set_accent("amber");
    expect(amber_preferences.accent == "amber", "accent should update");
    const auto& compact_preferences = engine.set_density("compact");
    expect(compact_preferences.density == "compact", "density should update");
    expect(compact_preferences.expanded_width == 700, "compact width should apply");

    auto activity = engine.run_action("codex", start);
    expect(activity.has_value(), "codex action should return activity");
    expect(activity->title == "Started Codex", "codex action title should match");
    expect(engine.agents()[0].status == AgentStatus::running, "codex agent should be running");
    expect(engine.sessions()[0].status == SessionStatus::running, "agent action should create running session");
    expect(engine.activities()[0].title == "Started Codex", "activity should be recorded first");

    engine.start_pomodoro(60s, start);
    expect(engine.active_pomodoro().has_value(), "pomodoro should start");
    expect(engine.sessions()[0].title == "Pomodoro focus", "pomodoro should create session");
    expect(engine.active_pomodoro()->remaining_at(start + 15s) == 45s, "remaining time should decrease");

    bool cancelled = engine.cancel_pomodoro(start + 20s);
    expect(cancelled, "active pomodoro should cancel");
    expect(!engine.active_pomodoro().has_value(), "cancel should clear active pomodoro");
    expect(engine.activities()[0].title == "Pomodoro cancelled", "cancel should record activity");

    engine.start_pomodoro(30s, start);
    auto notification = engine.advance_time(start + 30s);
    expect(notification.has_value(), "pomodoro completion should create notification");
    expect(notification->title == "Pomodoro complete", "notification title should match");
    expect(!engine.active_pomodoro().has_value(), "completion should clear active pomodoro");
    expect(engine.activities()[0].title == "Pomodoro complete", "completion should record activity");

    std::cout << "Junimo C++23 core smoke tests passed\n";
}
