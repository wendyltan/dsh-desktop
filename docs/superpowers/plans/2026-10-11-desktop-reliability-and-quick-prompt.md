# Desktop reliability and quick prompt implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to execute the tasks below. The user approved implementation on a separate branch after the read-only audit.

> **Status (2026-10-18):** Implementation and isolated UI acceptance are complete. The user authorized a local merge to `master`, followed by installing and restarting the production desktop/Guardian build. Push and publication remain out of scope.

**Goal:** Fix the audited reliability and state-reporting problems, then make quick prompts and recovery easier to use.

**Architecture:** Retain the existing SwiftUI/AppKit client and Guardian CLI. Reuse the official web session navigation and existing bridge. No new dependencies or parallel chat interface.

**Tech Stack:** Swift 5, SwiftUI/AppKit/Carbon, Node.js.

**Spec:** The accepted audit in this conversation: four reliability fixes, two information fixes, and four functional/UI improvements.

## Global constraints

- Branch: `fix/desktop-reliability-and-quick-prompt`, based on `master` at `3796ea1`.
- Preserve production credentials, data, installation, running service, and optical menu-bar icon alignment.
- Do not push, publish, update the Harness engine, or execute a paid model task. Local merge and production desktop/Guardian installation are authorized after verification.
- Keep the last textual answer as context, but label it accurately.
- Duplicate session labels receive a stable short ID; session search remains deferred as proposed in the audit.
- Build an isolated test app only after deterministic checks pass.

## Review focus

- A live operation must retain its lock beyond five minutes; another owner cannot release it.
- A competing snapshot must not replace another operation's working recovery directories.
- A foreign process occupying the configured port must never receive a signal.
- Failed or duplicate shortcut changes preserve the old registration and settings.
- Session navigation uses the server-returned ID; stale model fetches and degraded service state cannot imply success.

## Task 1: Guardian safety

**Files:** `Guardian/guardian.mjs`, `Guardian/verify.mjs`, focused Guardian test fixtures as needed.

- [x] Add regression cases for lock lifetime/ownership, locked snapshot commands, and foreign port/PID ownership. Confirm they fail before fixing.
- [x] Replace age-only lock eviction with live-owner validation and guarded release; put the public snapshot command under the same lock.
- [x] Validate process ownership before stopping saved PIDs or port listeners. Report a conflict without signalling foreign processes.
- [x] Run isolated Guardian verification and inspect the diff.

## Task 2: Shortcuts and bridge summary

**Files:** `Sources/GlobalHotKey.swift`, `Tests/GlobalHotKeyTests.swift`, `HarnessBridge/lib/index.js`, `HarnessBridge/verify.mjs` as needed.

**Interface:** `GlobalHotKeyManager.replace(_ previous: Shortcut, with shortcut: Shortcut, action: @escaping () -> Void) -> String?`; registration failure must leave the previous shortcut active. Duplicate registration must not replace another action.

- [x] Add focused failing tests for duplicate registration and failed replacement preserving the old registration.
- [x] Implement transactional replacement using existing Carbon registration; no generic backend framework.
- [x] Preserve text-summary semantics; Task 3 labels it as the previous textual answer. Change the bridge only if evidence establishes a remaining defect.
- [x] Run focused tests and report the interface to Task 3.

## Task 3: Native functionality and UI

**Files:** `Sources/AppStore.swift`, `Sources/EventBridge.swift`, `Sources/QuickPromptPanel.swift`, `Sources/SettingsView.swift`, `Sources/GuardianPanel.swift`, `Sources/App.swift`, associated Swift tests and `Bridge/Verify.swift`.

**Interfaces:** Consume Task 2's transactional shortcut API; preserve `sendPrompt` callers while returning a validated session ID. Keep navigation on the existing official web handoff.

- [x] Add focused failing tests for new prompt session IDs, same-title/same-directory labels, model load state, and safe-mode state wherever existing test seams permit.
- [x] Reject equal shortcuts, show field-level errors, and save only after successful registration. Preserve prior registrations on failure.
- [x] Show loading/error/retry for model fetches; prevent stale responses from overriding current state.
- [x] Add mode switching and optional new-session model/effort controls to the prompt panel; reuse stored defaults.
- [x] Add a whale-menu entry to open the most recently sent session. Preserve draft handling and avoid auto-opening the full window on successful send.
- [x] Disambiguate colliding session labels with a stable ID and label the previous textual reply accurately.
- [x] Show safe mode as degraded; fold normal plugin details, cap initial event history, and move recovery controls ahead of history.
- [x] Prefer reload when the service is healthy, with recovery primary only when unavailable.
- [x] Run targeted Swift tests and report changed interfaces.

## Task 4: Integration and review

**Files:** `Scripts/verify.sh`, existing build scripts only if necessary.

- [x] Wire new focused tests into the verification script.
- [x] Run `./Scripts/verify.sh --installed-engines`, compile the GUI using `./build.sh --test`, and verify the test app signature.
- [x] Obtain an independent whole-diff review; fix justified findings and repeat affected checks.
- [x] Record the branch, concrete changes, passing checks, and visual/live coverage limits before local integration.

## Verification status

- Focused and broader local regression: PASS on 2026-10-18.
- Installed-engine V3 to V4 compatibility: PASS on 2026-10-18.
- Isolated app build/signature: PASS on 2026-10-18.
- Human acceptance of the isolated UI: PASS on 2026-10-18; a full UI redesign is explicitly deferred to a later task.
- Production installation/runtime acceptance: authorized and performed only after the branch is locally merged; results are reported outside this implementation plan.

## Ownership and interface scan

| Tasks | Shared boundary | Resolution |
| --- | --- | --- |
| 1 / 3 | Guardian response fields | Keep response schema; Task 3 reads existing safe mode. |
| 2 / 3 | GlobalHotKeyManager.replace | Fixed signature above; Task 3 owns all AppStore and SettingsView edits. |
| 2 / 4 | New hotkey test | Task 4 owns verify.sh integration. |
| 3 / 4 | Swift sources/build | Task 4 waits for source edits before compiling final GUI. |
| 1, 2, 3 | Tests and implementation | Each task owns its source and focused tests; no shared-file edits. |
