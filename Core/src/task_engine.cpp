#include "junimo/core/task_engine.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <regex>
#include <sstream>
#include <utility>

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

int sequence_from_corner_todo_id(std::string_view id) {
    constexpr std::string_view prefix = "00000000-0000-4000-8000-";
    if (!id.starts_with(prefix)) {
        return 0;
    }
    int sequence = 0;
    for (const char character : id.substr(prefix.size())) {
        if (!std::isdigit(static_cast<unsigned char>(character))) {
            return 0;
        }
        sequence = (sequence * 10) + (character - '0');
    }
    return sequence;
}

std::filesystem::path default_corner_note_cache_path() {
    const char* override_path = std::getenv("JUNIMO_CORNER_NOTE_CACHE_PATH");
    if (override_path != nullptr && !std::string_view(override_path).empty()) {
        return std::filesystem::path(override_path);
    }

    const char* home = std::getenv("HOME");
    if (home == nullptr || std::string_view(home).empty()) {
        return std::filesystem::temp_directory_path() / "junimo-corner-note.cache";
    }
    return std::filesystem::path(home) / "Library" / "Application Support" / "Junimo" / "corner-note.cache";
}

std::string escape_cache_field(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const char character : value) {
        switch (character) {
            case '\\':
                escaped += "\\\\";
                break;
            case '\n':
                escaped += "\\n";
                break;
            case '\t':
                escaped += "\\t";
                break;
            default:
                escaped.push_back(character);
                break;
        }
    }
    return escaped;
}

std::string unescape_cache_field(std::string_view value) {
    std::string unescaped;
    unescaped.reserve(value.size());
    bool escaping = false;
    for (const char character : value) {
        if (escaping) {
            switch (character) {
                case 'n':
                    unescaped.push_back('\n');
                    break;
                case 't':
                    unescaped.push_back('\t');
                    break;
                case '\\':
                    unescaped.push_back('\\');
                    break;
                default:
                    unescaped.push_back(character);
                    break;
            }
            escaping = false;
            continue;
        }
        if (character == '\\') {
            escaping = true;
        } else {
            unescaped.push_back(character);
        }
    }
    if (escaping) {
        unescaped.push_back('\\');
    }
    return unescaped;
}

std::vector<std::string> split_tab_fields(std::string_view line) {
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (start <= line.size()) {
        const std::size_t tab = line.find('\t', start);
        if (tab == std::string_view::npos) {
            fields.push_back(std::string(line.substr(start)));
            break;
        }
        fields.push_back(std::string(line.substr(start, tab - start)));
        start = tab + 1;
    }
    return fields;
}

std::optional<std::string> json_string_field(std::string_view object, std::string_view key) {
    const std::regex pattern("\"" + std::string(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");
    std::cmatch match;
    if (!std::regex_search(object.data(), object.data() + object.size(), match, pattern)) {
        return std::nullopt;
    }
    return unescape_cache_field(match[1].str());
}

bool json_bool_field(std::string_view object, std::string_view key) {
    const std::regex pattern("\"" + std::string(key) + "\"\\s*:\\s*true");
    return std::regex_search(object.data(), object.data() + object.size(), pattern);
}

std::optional<CornerNote> parse_legacy_corner_note_json(std::string_view json) {
    CornerNote note;
    if (auto text = json_string_field(json, "text")) {
        note.text = *text;
    }

    const std::regex object_pattern("\\{[^{}]*\\}");
    auto begin = std::cregex_iterator(json.data(), json.data() + json.size(), object_pattern);
    const auto end = std::cregex_iterator();
    for (auto it = begin; it != end; ++it) {
        const std::string object = it->str();
        auto id = json_string_field(object, "id");
        auto title = json_string_field(object, "title");
        if (!id.has_value() || !title.has_value()) {
            continue;
        }
        note.todos.push_back(CornerTodo{
            .id = *id,
            .title = *title,
            .is_done = json_bool_field(object, "isDone"),
        });
    }

    if (note.text.empty() && note.todos.empty()) {
        return std::nullopt;
    }
    return note;
}

}  // namespace

TaskEngine::TaskEngine() : TaskEngine(default_corner_note_cache_path()) {}

TaskEngine::TaskEngine(std::filesystem::path corner_note_cache_path)
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
      },
      corner_note_{
          .text = "Quick note",
          .todos = {
              CornerTodo{.id = "00000000-0000-4000-8000-000000000001", .title = "Capture an idea", .is_done = false},
              CornerTodo{.id = "00000000-0000-4000-8000-000000000002", .title = "Turn it into a task", .is_done = false},
          },
      },
      corner_note_cache_path_{std::move(corner_note_cache_path)} {
    load_corner_note_cache();
    record(Activity{
        .title = "Junimo started",
        .detail = "Hover the capsule to open the console",
        .created_at = Clock::now(),
    });
}

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

const CornerNote& TaskEngine::corner_note() const {
    return corner_note_;
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
        ui_preferences_.expanded_height = 340;
    }
    return ui_preferences_;
}

const CornerNote& TaskEngine::update_corner_note_text(std::string_view text) {
    corner_note_.text = std::string(text);
    save_corner_note_cache();
    return corner_note_;
}

const CornerNote& TaskEngine::add_corner_todo(std::string_view title) {
    corner_note_.todos.push_back(CornerTodo{
        .id = make_corner_todo_id(),
        .title = std::string(title),
        .is_done = false,
    });
    save_corner_note_cache();
    return corner_note_;
}

const CornerNote& TaskEngine::update_corner_todo_title(std::string_view id, std::string_view title) {
    auto it = std::ranges::find_if(corner_note_.todos, [id](const CornerTodo& todo) {
        return todo.id == id;
    });
    if (it != corner_note_.todos.end()) {
        it->title = std::string(title);
        save_corner_note_cache();
    }
    return corner_note_;
}

const CornerNote& TaskEngine::toggle_corner_todo(std::string_view id) {
    auto it = std::ranges::find_if(corner_note_.todos, [id](const CornerTodo& todo) {
        return todo.id == id;
    });
    if (it != corner_note_.todos.end()) {
        it->is_done = !it->is_done;
        save_corner_note_cache();
    }
    return corner_note_;
}

const CornerNote& TaskEngine::remove_corner_todo(std::string_view id) {
    const auto original_size = corner_note_.todos.size();
    std::erase_if(corner_note_.todos, [id](const CornerTodo& todo) {
        return todo.id == id;
    });
    if (corner_note_.todos.size() != original_size) {
        save_corner_note_cache();
    }
    return corner_note_;
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

void TaskEngine::record_activity(std::string_view title, std::string_view detail, TimePoint now) {
    record(Activity{
        .title = std::string(title),
        .detail = std::string(detail),
        .created_at = now,
    });
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

std::string TaskEngine::make_corner_todo_id() {
    std::ostringstream stream;
    stream << "00000000-0000-4000-8000-";
    stream.width(12);
    stream.fill('0');
    stream << next_corner_todo_sequence_++;
    return stream.str();
}

void TaskEngine::load_corner_note_cache() {
    std::ifstream input(corner_note_cache_path_);
    if (!input) {
        const auto legacy_path = corner_note_cache_path_.parent_path() / "corner-note.json";
        std::ifstream legacy_input(legacy_path);
        if (!legacy_input) {
            return;
        }
        std::stringstream buffer;
        buffer << legacy_input.rdbuf();
        auto legacy_note = parse_legacy_corner_note_json(buffer.str());
        if (!legacy_note.has_value()) {
            return;
        }
        corner_note_ = std::move(*legacy_note);
        for (const auto& todo : corner_note_.todos) {
            next_corner_todo_sequence_ = std::max(next_corner_todo_sequence_, sequence_from_corner_todo_id(todo.id) + 1);
        }
        save_corner_note_cache();
        return;
    }

    CornerNote loaded;
    std::string line;
    while (std::getline(input, line)) {
        if (line.starts_with("text\t")) {
            loaded.text = unescape_cache_field(std::string_view(line).substr(5));
            continue;
        }
        if (!line.starts_with("todo\t")) {
            continue;
        }
        auto fields = split_tab_fields(line);
        if (fields.size() < 4) {
            continue;
        }
        loaded.todos.push_back(CornerTodo{
            .id = unescape_cache_field(fields[1]),
            .title = unescape_cache_field(fields[3]),
            .is_done = fields[2] == "1",
        });
    }

    if (!loaded.text.empty() || !loaded.todos.empty()) {
        corner_note_ = std::move(loaded);
        for (const auto& todo : corner_note_.todos) {
            next_corner_todo_sequence_ = std::max(next_corner_todo_sequence_, sequence_from_corner_todo_id(todo.id) + 1);
        }
    }
}

void TaskEngine::save_corner_note_cache() const {
    if (corner_note_cache_path_.empty()) {
        return;
    }

    std::error_code error;
    std::filesystem::create_directories(corner_note_cache_path_.parent_path(), error);
    if (error) {
        return;
    }

    const auto temporary_path = corner_note_cache_path_.string() + ".tmp";
    std::ofstream output(temporary_path, std::ios::trunc);
    if (!output) {
        return;
    }

    output << "text\t" << escape_cache_field(corner_note_.text) << '\n';
    for (const auto& todo : corner_note_.todos) {
        output << "todo\t"
               << escape_cache_field(todo.id) << '\t'
               << (todo.is_done ? "1" : "0") << '\t'
               << escape_cache_field(todo.title) << '\n';
    }
    output.close();
    if (!output) {
        std::filesystem::remove(temporary_path, error);
        return;
    }

    std::filesystem::rename(temporary_path, corner_note_cache_path_, error);
    if (error) {
        std::filesystem::remove(corner_note_cache_path_, error);
        error.clear();
        std::filesystem::rename(temporary_path, corner_note_cache_path_, error);
    }
}

}  // namespace junimo::core
