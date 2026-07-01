# activity-capture Specification

## Purpose
Define Junimo's manual activity screenshot capture boundary and today's capture statistics surface.

## Requirements

### Requirement: Manual foreground activity capture

Activity screenshot capture SHALL be started manually from a terminal foreground script.

#### Scenario: User starts capture manually

- **WHEN** the user runs `scripts/run_activity_capture_manual.sh`
- **THEN** the script SHALL repeatedly invoke the snapshot capture script in the foreground
- **AND** the user SHALL stop capture with `Ctrl-C`
- **AND** Junimo SHALL NOT install or depend on a LaunchAgent for capture

### Requirement: Today capture statistics

The expanded main panel screenshot page SHALL show statistics for today's captured files.

#### Scenario: Today directory has captures

- **WHEN** today's capture directory contains JPEG files and `index.csv`
- **THEN** Junimo SHALL show image count, indexed validity, total bytes, and latest capture

#### Scenario: Today directory has no captures

- **WHEN** today's capture directory is missing or empty
- **THEN** Junimo SHALL show that there is no data for today without starting capture
