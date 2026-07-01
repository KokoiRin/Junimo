# Testing Strategy

Junimo should use a testing pyramid rather than treating one large script as the only signal.

## Pyramid

1. Unit tests protect pure policy and parsing behavior.
   - C++ core behavior: `scripts/test_cpp.sh`
   - Swift coordinator, parser, and model behavior: `scripts/test.sh`
2. Integration tests protect seams between modules with fakes or local builds.
   - Swift-to-C++ bridge smoke: `scripts/test.sh`
   - Codex monitor refresh bridge with fake provider and fake stream: `scripts/test.sh`
   - Main panel page/copy contract: `scripts/test.sh`
   - Direct/app builds: `scripts/verify_ci.sh`
3. End-to-end tests stay small and prove the app can launch and run an observable scenario.
   - Launch health: `scripts/verify_launch_health.sh`
   - Functional scenario: `scripts/verify_functional_scenario.sh`

## Harness Meaning

A harness is the script or fixture that runs tests and checks in a repeatable way. It is not a test layer by itself.

`scripts/verify.sh` is the full local harness for Chowa completion checks. It should stay broad and relatively expensive. During development, prefer narrow commands first, then run `scripts/verify.sh` before archiving or reporting completion.

## Current Gaps

- UI visual details such as the exact collapsed attention animation and badge are still covered indirectly by app launch and code-level checks, not by pixel assertions.
- The expanded panel's module/page semantics and Chinese copy contract are
  covered by smoke tests, but final visual layout still needs manual or
  screenshot-based review.
- Menu bar item interaction is implemented and documented, but not clicked by an automated UI driver.
- SwiftPM `swift test` remains a desired entry point once the local CommandLineTools manifest issue is fixed; direct Swift compiler scripts are the current reliable path.
