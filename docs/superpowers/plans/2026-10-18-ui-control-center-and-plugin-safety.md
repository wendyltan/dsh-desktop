# Native Control Center and Plugin Safety Implementation Plan

> Execute test-first in the isolated `feature/ui-control-center` worktree. Do not install production, restart the production service, merge, push, or publish before human visual acceptance.

**Goal:** Turn the existing status panel into a resizable native desktop control center, make plugin compatibility evidence trustworthy and actionable through the existing Harness plugin manager, and close the Quick Prompt success/accessibility gaps.

**Architecture:** Extend the existing Guardian status protocol rather than adding a service. Reuse `GuardianPanel`, `AppStore`, `SettingsView`, and existing Web workspace routing. Guardian classifies evidence; SwiftUI presents it. Harness remains the only plugin mutation owner.

**Tech Stack:** SwiftUI/AppKit, Node.js ESM Guardian, existing assert-based verification scripts, existing build/test harness.

---

## Task 1: Make plugin compatibility evidence trustworthy

**Files:**
- Modify: `Guardian/guardian.mjs`
- Modify: `Guardian/verify.mjs`
- Modify: `Sources/GuardianService.swift`
- Modify: `Tests/UpdateCheckerTests.swift`

1. Add failing Guardian tests proving a prerelease engine satisfies wildcard peer ranges and an unresolvable dependency is classified `unresolved`, not confirmed incompatible.
2. Run `node Guardian/verify.mjs` and confirm those assertions fail for the expected missing fields/behavior.
3. Add the smallest Guardian changes: `includePrerelease`, current/candidate scope metadata, engine version, check time, and dependency classification.
4. Add a failing Swift decode fixture for the new metadata and classification, then update the model decoder minimally.
5. Run the focused Guardian and Swift tests, then `./Scripts/verify.sh`.
6. Commit: `fix: classify plugin compatibility evidence`

## Task 2: Reshape the status panel into a native control center

**Files:**
- Modify: `Sources/GuardianPanel.swift`
- Modify: `Sources/AppStore.swift`
- Modify: `Sources/App.swift`
- Modify: `Sources/SettingsView.swift`
- Modify: `Tests/UpdateCheckerTests.swift` only if a pure state seam is needed

1. Add a small failing state test only for new non-trivial selection/label logic; keep visual layout in native components without inventing a view-model layer.
2. Introduce sidebar selection for Overview, Plugins & Compatibility, Recovery & Versions, and Desktop Settings using the existing views and actions.
3. Move plugin warnings into the plugin domain, show current/candidate metadata and one recommendation, and keep dependency rows inside technical disclosure.
4. Add a primary “在工作区管理插件” action using the existing authenticated client URL. Do not mutate plugin state in Swift.
5. Make the panel resizable with minimum/ideal size and remove the duplicate deep refresh from `GuardianPanelController`.
6. Rename ambiguous native labels to “桌面端设置” and “检查 Harness 引擎更新”. Hide the navigation test command outside test builds.
7. Run focused Swift checks and `./Scripts/verify.sh`.
8. Commit: `feat: add native desktop control center`

## Task 3: Complete Quick Prompt success and accessibility states

**Files:**
- Modify: `Sources/QuickPromptPanel.swift`
- Modify: `Tests/QuickPromptPanelTests.swift`

1. Add failing tests for a persistent success result carrying the destination session and for explicit dismissal/open behavior.
2. Confirm the tests fail because success currently closes immediately.
3. Keep the panel open on success, render target confirmation plus “打开会话”, and preserve the existing menu fallback.
4. Add a meaningful editor accessibility label and status value; replace the deprecated `onChange` form while touching the same surface.
5. Run focused tests and `./Scripts/verify.sh`.
6. Commit: `feat: complete quick prompt handoff`

## Task 4: Build the isolated acceptance candidate

**Files:**
- Modify: `README.md`
- Modify: `PROJECT_TODO.md` if present; otherwise add a concise acceptance ledger only if needed
- Modify version files only if all feature work is accepted for the candidate

1. Update README with the control-center boundary, plugin recommendation behavior, and separate restart confirmation.
2. Inspect the complete diff and confirm no direct plugin mutation path or unrelated refactor entered scope.
3. Run `./Scripts/verify.sh`.
4. Run `./build.sh --test`.
5. Run `node Scripts/prepare-test-environment.mjs --refresh` (or initialize once if absent), then `./Scripts/verify.sh --installed-engines`.
6. Open `DeepSeek Harness Test.app` and gather screenshots of Overview, Plugins, Recovery, Settings, and Quick Prompt states without a paid model call.
7. Run implementation review, spec review, quality review, and final review; fix all blocking findings with focused tests.
8. Commit docs/version candidate: `docs: document desktop control center acceptance`
9. Create local semantic tag only after deterministic checks: `feature/ui-control-center-20261018`.
10. Present the isolated app for human acceptance. Production install/merge remains NOT RUN.
