# Native UI refinement — 2026-10-20

## Approval and scope

User approved **A + 1** from the [UI review](../../../.impeccable/critique/2026-10-20T08-27-16Z__sources.md): all five bounded refinements, retaining native macOS styling. Existing flows and ownership remain intact; no new subsystem or dependencies. Work stays on the existing `master` per the user's preference for small fixes, with an isolated Test app for acceptance.

- Plugin check/retry, explicit progress/error/history, and actionable recommendations; no desktop-side plugin mutations.
- Engine channel/check and retained-version management together in Recovery & Versions, not duplicated in Desktop Settings.
- Compact overview with genuine engine/check/impact context; keep the whale and full ring.
- Lighter Quick Prompt with visible destination, expandable secondary parameters, and searchable existing sessions.
- Accessible threshold/selection/action names and readable local operation timestamps.

Do not change engine update/rollback/session-format policy or the Web workspace. Formal installation, production restart and engine updates are not part of this acceptance build.

## Evidence

- Base: `69201be`; initial tracked worktree clean. The untracked review belongs to this task.
- Initial formal app PID `24070`; installed and local pre-change GUI SHA256 matched. No formal app or service was stopped.
- Baseline `./Scripts/verify.sh`: **PASS**, exit 0. Log: ignored `bin/ui-review-20261020/baseline-verification.log`.
- Baseline covered Swift assertions, bridge/installer checks, WKWebView navigation, shortcuts, lifecycle and Guardian integration. Real engine installation/crash rollback: **NOT RUN**.
- Test app not running and port 13080 unused before acceptance preparation; existing `.test-home` will be preserved.

## Current state

Implementation and review fixes complete, pending human acceptance. Parent reran `./Scripts/verify.sh`, `./build.sh --test` and whole-GUI `swiftc -typecheck -target arm64-apple-macosx13.0` on the final source: **PASS**, exit 0. Strict Test app signature verification passed; formal GUI and engine-selection fingerprints remained unchanged. Logs are in ignored `bin/ui-review-20261020/`.

First batched visual inspection: overview, current-plugin check/loading, recovery/version controls, desktop settings, and Quick Prompt existing/new/expanded options. Existing-session filtering retained the selected nonmatching session; expanded new-session options left Send reachable. The threshold's native accessibility tree now exposes its name and yuan unit. No message was sent.

Independent review found two Important issues: invalid new plugin results could replace old valid results while being labeled historical; a later deep refresh could be dropped while another was in flight. Both were fixed with behavioral regressions. Subsequent scoped review also caught an obsolete error surviving a successful automatic deep check; this and the ordinary-light freshness marker are covered by refresh-state assertions. Final independent review: no remaining blocking findings. Minor fixes: consistent Quick Prompt icon in settings and a single primary plugin-page action.

The same confirmed-engine guard now also retains engine-history and recovery-snapshot lists across light updates; changed or unknown engines do not reuse them. This prevents the version/recovery UI losing its loaded lists on a timer tick without altering recovery policy.

Final runtime check: made only the isolated checker temporarily unavailable, with a 60-second automatic restoration guard. The UI retained the old valid result, labeled it historical, showed a concise retry action, then cleared the old error and historical notice after successful checking. The checker was restored and its SHA256 matched the pre-test file; no engine restart or configuration recovery was performed. Current dark plugin-state rendering was inspected in addition to the initial light screens; no system appearance setting was changed. Snapshot preview exposes the selected snapshot in the native accessibility tree; the preview was cancelled without restoring anything.

Mechanical Impeccable scan of changed SwiftUI files returned no findings, but its markup scanner does not establish SwiftUI coverage; this is not an automated native-design PASS. Native screenshots and accessibility-tree checks are the actual UI evidence.

The test environment retains prior V3/V4 samples plus nine newly created local search samples. Their official session-format validation runs before writing; an initial helper attempt rejected a nonempty user-title reference list before any file was written, then passed with the correct empty list. No existing sessions, keys or production data were copied or overwritten. The ignored helper and samples remain for human acceptance.

Complete VoiceOver/keyboard traversal, every screen in dark appearance, live engine update/crash rollback and human acceptance: **NOT RUN**. The isolated app's first launch reported notification permission unavailable; no permissions were changed and notification delivery is outside this visual acceptance pass.

## Handoff

The separate Test app and its local test service remain available for human acceptance. No formal app installation, production service restart, engine update, remote push or publication was performed. The formal GUI and selected-engine files are guarded by recorded hashes. Local scoped commit and immutable tag `feature/native-ui-refinement-20261020` record this candidate; human visual approval is still required before formal installation. Screenshots and fixture helpers remain ignored, inside the project.
