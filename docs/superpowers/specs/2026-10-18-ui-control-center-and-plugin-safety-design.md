# Native Control Center and Plugin Safety Design

**Date:** 2026-10-18
**Status:** Approved for isolated implementation; human visual acceptance pending

## Product Decision

Keep the Harness Web UI as the complete workspace. Reshape the native status surface into a single desktop control center with four task domains:

1. **概览** — service state, one primary action, concise current impact.
2. **插件与兼容** — trustworthy current/candidate findings, recommendation, and route to Harness plugin management.
3. **恢复与版本** — recovery snapshots, engine update/switch, and recent events.
4. **桌面端设置** — shortcuts, Quick Prompt defaults, balance display, and desktop-only behavior.

Quick Prompt remains a separate lightweight launcher. The menu bar remains a compact entry point, not another settings surface.

## Architecture Boundary

| Owner | Responsibilities | Must not do |
| --- | --- | --- |
| SwiftUI control center | Explain current state, group tasks, request refresh, route to existing Web management | Edit profile files, invoke package managers, claim an unresolved dependency is broken |
| Guardian | Inspect current/candidate engine, classify compatibility evidence, preflight and recover service | Become a second plugin manager, silently disable/remove plugins |
| Harness plugin manager | List, enable/disable, install, remove, preserve profile semantics | Be bypassed by direct desktop file edits |
| Web workspace | Conversations, approvals, plugin catalog and plugin management | Duplicate Guardian recovery/version ownership |

The current engine already contains `@deepseek-ai/dsh-plugin-manager`, including persistent enable/disable and restart-required outcomes. Phase 1 therefore links the user to that existing management surface rather than adding a new mutation protocol to dsh-desktop.

## Compatibility Evidence Model

Guardian returns compatibility data with:

- `scope`: `current` or `candidate`.
- `engineVersion`: the engine used for the check.
- `checkedAt`: ISO timestamp.
- `checked`: whether the check could be completed.
- per plugin: enabled state and grouped dependency findings.
- per dependency classification:
  - `range-mismatch`: an installed dependency has a version outside the declared range.
  - `unresolved`: no trustworthy installed version could be located or the range is invalid.

Prerelease engines are evaluated with SemVer prerelease inclusion. A dependency such as `*` must not be reported incompatible only because the engine version is an `-rc` build. An unresolved dependency is not labeled “incompatible” and does not independently block an engine update.

Only enabled plugins with confirmed `range-mismatch` findings are presented as compatibility risks. Candidate results always say the current running service is unchanged.

## Plugin Resolution Flow

For each enabled plugin finding:

1. Show the plugin name, current impact, and one recommendation.
2. Keep raw package/range/version data under “技术详情”.
3. Offer **在工作区管理插件** as the primary action.
4. The Harness plugin manager owns the actual reversible disable/enable action.
5. If its result says a restart is required, ask separately whether to restart. Never combine disable and restart into one confirmation.
6. After management, a deep Guardian refresh verifies current compatibility.

Phase 1 intentionally excludes desktop-side install, automatic repair, automatic disable, remove, bulk actions, and raw `npm`/`pnpm` commands.

## Interaction and Visual Rules

- One selected sidebar item, one main title, one primary action per screen.
- Normal status is quiet. Warnings appear only when actionable or unresolved.
- Use native materials and semantic colors; DeepSeek blue is reserved for primary action and selection.
- Windows use minimum and ideal sizes and remain resizable. Content scrolls; primary controls remain reachable.
- Async state changes expose accessible labels/values. The Quick Prompt editor has a meaningful VoiceOver label.
- The developer-only navigation test command is absent from production menus.
- Opening the control center performs one deep refresh; `AppStore` is the single refresh owner.

The Impeccable Operate direction seed `66e2a555` was run before artifact code. The already approved, brief-pinned “quiet macOS operations console” direction overrides the random assignment. Its Operate constraints remain binding: native navigation and controls stay familiar; the visual world contributes only typography, palette, density, and one signature move. The Guardian ring is that signature move.

## Quick Prompt Completion

On successful send, do not immediately close. Show a short confirmation containing the destination session and an **打开会话** action, while preserving the menu-bar “最近发送” fallback. Errors retain the draft and remain actionable.

## Verification and Acceptance

- Unit/regression tests cover classification, prerelease behavior, current/candidate metadata decoding, and Quick Prompt completion state.
- `./Scripts/verify.sh` must pass.
- `./build.sh --test`, test-environment preparation, and installed-engine compatibility checks must pass in the isolated worktree.
- The isolated Test app is opened for human review. No production installation, service restart, merge, push, or publication occurs before acceptance.

## Deferred Work

- Native one-click plugin mutation protocol.
- Dependency installation/repair suggestions backed by registry metadata and dry-run.
- Plugin removal and data-cleanup policy.
- A full native replacement for the Web plugin catalog or chat workspace.
