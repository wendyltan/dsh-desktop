# DeepSeek Harness Desktop Product Context

## Product

DeepSeek Harness Desktop is a native macOS companion for the Harness Web workspace. The Web workspace owns conversations, approvals, and plugin management. The native app owns fast desktop entry points, service health, safe recovery, engine lifecycle, and concise explanations of local risk.

## Audience

- A frequent Harness user who wants a fast path into an existing or new session.
- A local operator who needs to understand whether the service is usable and recover it without losing sessions.
- A less technical user who needs recommendations instead of raw dependency diagnostics.

## Core Jobs

1. Open or continue Harness work quickly.
2. Know whether the local service is usable now.
3. Understand plugin compatibility findings and reach the safest available action.
4. Recover or change the Harness engine without silently changing user data or plugins.

## Platform

Native macOS application with an embedded Web workspace.

## Product Boundaries

- The native app does not recreate the chat workspace.
- The native app does not directly edit plugin manifests or install packages.
- Harness plugin management remains the only owner of plugin enablement, installation, and removal.
- Guardian owns inspection, preflight, service health, snapshots, and recovery.
- Destructive or disruptive actions require explicit confirmation. A plugin disable and a service restart are separate decisions.

## Product Language

- Call the embedded experience “工作区”.
- Call native preferences “桌面端设置”.
- Say “Harness 引擎更新”, not the ambiguous “应用更新”.
- Lead with current impact and a recommended next step; keep package ranges and dependency names under technical details.

## Visual Direction

An understated macOS operations console: system typography, native materials, compact but breathable spacing, semantic status colors, and DeepSeek blue only for primary actions and selection. The whale mark and Guardian ring are the only branded motifs. Avoid decorative gradients, generic sparkle icons, and repeated card walls.

## Acceptance

- The Web workspace remains intact.
- A resizable native control center exposes Overview, Plugins & Compatibility, Recovery & Versions, and Desktop Settings.
- Plugin findings distinguish current versus candidate engines and confirmed mismatches versus unresolved checks.
- Every plugin finding offers one plain-language recommendation and a route to the existing Harness plugin manager.
- Quick Prompt has a visible success handoff and accessible editor/status semantics.
- Production remains untouched until isolated visual acceptance is complete.
