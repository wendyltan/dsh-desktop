# Engine next channel implementation plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation with one independent final review. Steps use checkbox syntax.

**Goal:** Discover and explicitly select `next` releases without changing the user's current channel or installing an engine automatically.

**Architecture:** Read all supported dist-tags in one registry request. Keep the selected channel as the sole installation target; report newer alternatives as information. Extend the existing alpha retention and recovery policy to next, preserving session-format rollback guards and legacy metadata.

**Tech Stack:** SwiftUI/AppKit (macOS 13+), Foundation, Node.js, existing assert-based tests; no new dependencies.

**Spec:** This document's accepted requirements below implement the user's approved diagnosis and proposal.

## Global constraints / accepted requirements

- Support `latest`, `next`, `alpha`; default remains `latest`, unknown persisted channels retain the existing fallback.
- Describe `next` as 候选版本（next） and require explicit channel selection and explicit update confirmation.
- Check once per request, show selected/current/target versions and newer alternate channels, with no claim that an unselected preview is stable.
- Missing/invalid selected tag or failed request remains an error; absent/invalid alternate tags do not prevent checking a valid selection.
- Manual checks bypass registry caches; do not change unrelated HTTP callers or machine proxy/npm configuration.
- Both preview channels retain the previous engine and any available latest baseline; protect these from deletion while preview is active. Preserve at most two old versions.
- Startup failure may return to a retained latest engine only through existing session-compatibility checks. A blocked rollback must preserve data and report failure.
- Persist explicit channel provenance; old rc records without channel remain latest (rc alone does not prove next).
- CLI must name the selected channel and show alternate newer channels as well.
- Preserve existing configuration, in-flight work and engine version. Desktop/Guardian installation is separate from actually upgrading the engine.

## Review focus

- Latest unchanged while next is newer: inform user, never auto-select next.
- Missing/malformed selected tag: explicit error, no installation from another tag.
- Preview history already contains two entries: retain immediate predecessor and latest baseline; do not silently drop predecessor.
- Explicit next vs historical rc metadata: next stays next; old rc remains latest.
- Preview rollback with V4 sessions and a V3 baseline: block destructive downgrade.

## Task 1: Channel discovery and safe preview execution

**Files:** Sources/UpdateChecker.swift, AppStore.swift, AppSettings.swift, GuardianPanel.swift, dshctl.swift; Guardian/guardian.mjs and verify.mjs; Tests/UpdateCheckerTests.swift (and narrowly scoped settings tests if needed).

**Interfaces:** `EngineUpdateChannel` gains `.next` and shared preview policy; one registry result provides supported channel versions. `AppStore.checkUpdate` and CLI consume that result. Guardian accepts `--channel next` and extends its existing preview retention/recovery predicates.

- [x] Write and run failing tests for next tag extraction, cross-channel messages, malformed/missing tags, next Codable/config compatibility, preview history protection and existing session downgrade guard.
- [x] Implement the smallest shared discovery/message/policy helpers and wire callers; keep selected tag separate from alternatives.
- [x] Run focused Swift tests plus `node Guardian/verify.mjs`; expect all assertions passing.
- [x] Commit coherent implementation after full verification.

## Task 2: Documentation, release verification and handoff

**Files:** README.md, Guardian/README.md, this checklist and traceability ledger.

**Interfaces:** Consume Task 1 channel names and safety behavior; no new runtime behavior.

- [x] Document all three channels, alternate-version messages and preview recovery limits.
- [x] Run `Scripts/verify.sh --installed-engines`, `build.sh --test`, macOS 13 typecheck, `git diff --check`; record exact outcomes.
- [x] Independent review; fix material findings with regression evidence.
- [x] Verify test-app selected latest/next UI using real registry reads without installing an engine.
- [x] Commit/tag; integrate and install the desktop build under existing task authorization, preserving the running engine and checking installed hashes/signature/runtime.
- [x] Report engine-install acceptance NOT RUN and human acceptance pending.
