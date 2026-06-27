## 1. Core Semantics

- [x] 1.1 Add RED direct tests for release version parsing and comparison, covering `v0.1.5`, equal versions, older versions, and unparseable tags.
- [x] 1.2 Implement `ReleaseVersion`, `SelfUpdateSnapshot`, and `SelfUpdateFeature` in `JunimoCore`.
- [x] 1.3 Add RED direct tests for `SelfUpdateFeature` state transitions: checking, update available, up to date, check failed, installing, and install failed.
- [x] 1.4 Wire self-update snapshot and intents through `TaskCoordinator` without adding network or shell side effects to core.

## 2. Release Checking Service

- [x] 2.1 Add fake-backed app direct tests proving a software update service writes newer/equal/failure manual check results into coordinator state.
- [x] 2.2 Implement `SoftwareUpdateService` with start/stop, manual `checkNow`, optional start-after-launch check, single-flight behavior, and stopped-service guard.
- [x] 2.3 Implement `GitHubReleaseChecker` for latest release metadata, including parse failure and missing asset handling.
- [x] 2.4 Add tests or static validation that check failure does not trigger a blocking modal or installer intent.

## 3. Runtime And Menu Integration

- [x] 3.1 Extend `JunimoRuntime` to own software update service lifecycle and expose user-triggered update-check/install intents to AppDelegate.
- [x] 3.2 Add app direct tests proving runtime starts update checking and stop prevents later coordinator mutation.
- [x] 3.3 Add status menu item `Check for Updates...` / `Install Update...` that delegates intents instead of comparing versions in AppDelegate.
- [x] 3.4 Add minimal menu-state feedback for checking, up-to-date, check-failed, update-available, and installing states without adding a confirmation dialog.

## 4. External Updater

- [x] 4.1 Add `scripts/update_latest.sh` that preserves the current app install directory, terminates running Junimo, delegates download/install to `install_latest.sh`, and reopens Junimo.
- [x] 4.2 Add `ExternalUpdateInstaller` adapter that starts the updater process with the current bundle parent directory and reports launch failures.
- [x] 4.3 Add fake installer tests proving install only starts from available-update state after the user chooses `Install Update...`.
- [x] 4.4 Add static/manual verification for the shell scripts with `bash -n` and a `JUNIMO_DRY_RUN=1` dry-run path where feasible.

## 5. Release And Documentation

- [x] 5.1 Bump `CFBundleShortVersionString` to `0.1.5` for the release that carries self-update.
- [x] 5.2 Update README and distribution docs to describe manual menu check, optional launch-time check, and the external updater fallback command.
- [x] 5.3 Update or add OpenSpec long-lived specs after implementation.
- [x] 5.4 Run `scripts/test.sh`, `scripts/build.sh`, `scripts/verify_ci.sh` or the closest available subset, `openspec validate --all --strict`, and `git diff --check`.
- [x] 5.5 Commit, push, tag `v0.1.5`, and push the tag to trigger GitHub Release packaging.
