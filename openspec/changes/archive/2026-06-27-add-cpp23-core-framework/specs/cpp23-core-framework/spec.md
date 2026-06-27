## ADDED Requirements

### Requirement: C++23 core builds
The system SHALL provide a C++23 core library skeleton that builds with Apple clang.

#### Scenario: Build C++ core
- **WHEN** the developer runs the C++ build script
- **THEN** the script compiles the core with `-std=c++23` and produces a static library

### Requirement: Core domain models
The C++23 core SHALL define portable domain models for agents, actions, activities, and Pomodoro sessions.

#### Scenario: Include core headers
- **WHEN** a C++ caller includes the core headers
- **THEN** the caller can create and update core domain state without depending on Swift or AppKit

### Requirement: C++ core tests
The system SHALL provide C++ tests for core action dispatch and Pomodoro lifecycle behavior.

#### Scenario: Run C++ tests
- **WHEN** the developer runs the C++ test script
- **THEN** the tests pass without requiring CMake or external dependencies

### Requirement: Future Swift bridge boundary
The documentation SHALL describe how Swift UI will consume the C++ core through a narrow bridge in a later step.

#### Scenario: Developer checks architecture notes
- **WHEN** the developer reads the architecture documentation
- **THEN** the intended Swift/AppKit UI to C++ core boundary is clear
