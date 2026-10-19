# Progress — 2026-10-19 engine next channel

Base: `6eaecac`; branch: `feature/engine-next-channel`; isolated checkout: `/Users/wuwendi/.dsh/worktrees/dsh-desktop-next-channel`.
Routing: Jev HIGH (confidence 0.73), Luna High implementation; primary agent integration/verification; independent final review.
Pre-flight: Swift release catalog feeds AppStore and CLI; preview policy must agree across AppStore, Guardian, and version-management UI. Legacy rc channel provenance must not be inferred from version naming.
Scope: User approved next channel, alternate channel discovery and preview protection. Existing install/merge authorization continues for desktop software; actual engine upgrade requires explicit UI confirmation.
Task 1: implemented. RED: Swift failed on missing next/catalog APIs; actual Guardian update CLI rejected next before reaching the V4 downgrade guard. GREEN: focused Swift assertions and Guardian integration passed after implementing explicit next metadata, alternate messages, protected predecessor/baseline, and preview recovery target selection. A test fixture temporarily retained next state before an existing alpha assertion; fixture reset corrected that test sequencing issue.
Task 2: in progress. Whole-suite `Scripts/verify.sh --installed-engines` and `build.sh --test` PASS in the isolated checkout. Logs: ignored `bin/next-channel-verification.log`, `bin/next-channel-build.log`. Production remains engine 0.2.0-rc.2 / Guardian 0.6.0; no engine installation performed.
