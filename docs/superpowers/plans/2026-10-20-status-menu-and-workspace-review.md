# Status menu polish and workspace review — 2026-10-20

Base: `6d06d96`, existing `master`. User approved the proposed menu reordering and asked to inspect possible main-window improvements. Only menu presentation is implemented; the Web workspace remains unchanged. No new branch, dependencies or menu abstraction.

## Menu change

1. Open Workspace, Quick Prompt, last sent session.
2. Pending approvals/status (existing retry and submenu behavior).
3. Control Center and the existing contextual engine-update entry.
4. Desktop version and Quit.

Native separators define groups; no decorative icons or new actions. The open action is renamed “打开工作区”; version becomes “桌面端 v…” to distinguish it from the engine. Existing selectors, key equivalents, enabled states, pending approvals, update visibility and balance rendering remain unchanged. No source-string order test is added for this mechanical presentation change; compilation, existing regressions and runtime/manual review are the appropriate checks.

## Main-window observations — read only

Inspected the isolated main window at 980×672 in dark appearance, with its sidebar expanded and collapsed, plus the built-in general settings. No message, model request or settings change was submitted; the original collapsed sidebar state was restored.

- Sidebar occupies about 280 px at the minimum window width. A slightly narrower, ideally adjustable sidebar could leave more room for conversation while retaining the current collapse control. This is a proposal, not a confirmed layout defect.
- Model/effort and access-mode controls in the composer are visually subdued. A clearer grouping, better inactive/interactive distinction and Chinese effort labels would improve scanability without replacing the input workflow. This is a visual observation, not a measured contrast failure.
- The native window has a fixed 980 px minimum width (`Sources/App.swift`). Smaller split-screen layouts deserve testing before reducing this constraint; no narrow-width acceptance has been performed.
- The new-task landing page says “探索未至之境 / 预览版” before workspace selection. A direct “选择工作区，开始新会话” instruction could make the first action clearer; replacing upstream copy requires separate approval.
- The native application menus still expose English Edit/View/Window alongside Chinese actions. Localizing the application chrome could improve consistency without rewriting the chat UI.
- The Web settings own language, appearance, models and Agent preferences; desktop preferences remain in Control Center. No duplicate desktop-settings entry was found in the inspected Web settings.

Most of the visible workspace belongs to the upstream Harness Web app, not the native control center. Do not edit installed engine bundles as a styling shortcut. Any future workspace refinement needs separate scope approval and a maintainable integration route.

## Verification and handoff

Menu implementation diff inspected: only construction order and two labels changed in `AppStore.swift`; action bindings and dynamic refresh paths are untouched. `./Scripts/verify.sh`, `./build.sh --test`, strict test signature verification and diff checks: **PASS**. The rebuilt Test app was opened and its main Web page loaded. The exact status-menu appearance and human acceptance remain pending; no automated status-menu screenshot is claimed. Two transient native capture failures occurred during workspace inspection; accessibility-state reads confirmed the settings opened/closed and the original collapsed sidebar state was restored. Screenshot evidence and logs stay in ignored `bin/menu-polish-20261020/`.

No formal app replacement, production restart, engine update, remote push or publication is authorized by this change. The running isolated Test app may be rebuilt/reopened for human acceptance; preserve the test service and samples.
