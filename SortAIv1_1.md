# SortAI v1.1 Implementation Plan

## Goals
- Evolve the current MVP (no rewrite) into the v1.1 target defined in `spec.md`.
- Add cloud LLM support with graceful degraded mode (local-only) and user choice.
- Harden safety: undoable organizer, movement logging, no-delete invariant.
- Respect user controls: hierarchy depth, stability↔correctness, destination modes.
- Improve resilience: migrations for volatile schema, backpressure, retries, visibility.

## Pillars
1) **LLM routing & degraded mode**
2) **Safety: organizer + logging + undo**
3) **Pipeline correctness: taxonomy depth, merge/split gating, deep analysis orchestration**
4) **Continuous watch reliability**
5) **Schema & migrations**
6) **Preferences & UX surfacing**
7) **Testing & observability**

## 1) LLM Routing & Degraded Mode
- Extend LLM provider abstraction to support cloud providers (auth, timeout, pricing-aware limits, batching/backoff).
- Health/availability detection:
  - Detect unreachable LLMs (local or cloud).
  - Auto-retry with exponential backoff in background; surface status in UI.
- UI flow:
  - Toast/banner: “LLM unavailable. Wait/Retry” and “Use degraded mode (local-only)”.
  - If degraded selected: stick to filename-first/local heuristics; no cloud calls; continue queueing retries; show inline status and “Return to full mode” when healthy.
- Routing:
  - Modes: full (cloud or local), degraded (local heuristics), offline-queued.
  - Preserve user-approved edits; never auto-override on recovery.
- Logging/telemetry: record mode switches, retries, failures, and user choices.

## 2) Safety: Organizer + Logging + Undo
- Introduce command + undo stack for file operations.
- Durable movement log: timestamp, source, destination, reason, confidence; persisted via GRDB.
- macOS-style collision handling; enforce “never delete files” invariant.
- Soft-move/alias-first option wired to preferences.
- Progress UI shows current command and provides cancel where safe.

## 3) Pipeline Correctness
- Taxonomy fast pass:
  - Enforce hierarchy depth slider (3–7) in SemanticThemeClusterer and builders.
  - Keep Phase 1 fast and non-blocking; Phase 2 selective, background, cancelable.
- Merge/split suggestions:
  - Parse LLM suggestions; require explicit approval.
  - Protect human-edited nodes; apply merges/splits with progress and undo.
- Deep analysis orchestration:
  - Background task manager for batches; queueing + cancellation; status surfaced in UI.
  - Guardrail: never override user-approved placements.

## 4) Continuous Watch Reliability
- FSEvents watcher with quiet-period batching, in-use/partial-download detection, large-file safeguards.
- Backpressure: limit concurrent analyses; defer if system load high.
- UI status: watch on/off, degraded/full LLM status, queue depth.

## 5) Schema & Migrations
- Add GRDB migration harness (lightweight, versioned).
- Keep schema minimal while volatile; add fixtures/tests for migrations.
- Log schema version and refuse destructive changes without migration.

## 6) Preferences & UX Surfacing
- Expose: destination modes (centralized/distributed/custom), hierarchy depth, stability↔correctness slider, deep-analysis file-type selection, soft-move toggle, notifications, battery behavior.
- Degraded/full mode status, retry/backoff indicators, “Return to full mode” action.
- Simulation/preview remains fast; background refinement continues with clear status.

## 7) Testing & Observability
- Add integration tests:
  - LLM routing (healthy vs degraded), retries/backoff.
  - Organizer command/undo, collision handling, no-delete invariant.
  - Taxonomy depth enforcement; merge/split approval flow.
  - Watch mode: quiet-period batching, partial-download skip, backpressure.
- Add logging for mode switches, retries, organizer actions, and migrations; ensure logs are single-block and copyable.

## Addendum: Testing & QA Plan
- **Test matrix & entry points**
  - CLI/Xcode: `xcodebuild test -scheme SortAI -destination 'platform=macOS'`
  - Targeted suites (from README structure): TaxonomyTests, LLMProviderTests, OrganizationTests, DeepAnalyzerTests, PersistenceTests, ConfigurationTests, ProtocolTests, SortAITests.
- **Unit tests (core services)**
  - LLM routing: healthy vs degraded paths, timeout/backoff, mode switches, preserving user-approved placements.
  - Organizer: command/undo stack, no-delete invariant, collision rename plans, soft-move/alias-first, dry-run previews.
  - Taxonomy: depth enforcement (advisory), clustering outputs (spherical k-means/HDBSCAN), prototype updates/EMA decay, shared prototypes, merge/split suggestion gating, ≥85% auto-place precision targeting (confidence model).
  - Embeddings/cache: cache hits/misses keyed by filename+parent, persistence across runs, small sentence-transformer encoding smoke tests.
  - Deep analysis: batch orchestration, pause/cancel, per-batch progress, guardrail against overriding approved nodes.
- **Integration tests**
  - End-to-end pipeline (Phase 1 + optional Phase 2) with fixture folders: asserts draft hierarchy, confidence distribution, review bucket population, and logging/undo entries.
  - Watch mode: quiet-period batching, partial-download/in-use skips, large-file gating, backpressure; status surface updates.
  - LLM degraded/full transitions: user prompt path (“Wait/Retry” vs “Use local-only”), auto-retry with backoff, return-to-full when healthy.
  - Organizer E2E: simulate moves with collisions, verify rename plans and undo, verify movement log rows.
- **UI/UX acceptance (manual/automated smoke)**
  - Wizard 1UX: initial hierarchy + exemplars visible, inline edit works (button/context menu/Enter), review bucket present, status indicators for LLM/watch/deep-analysis.
  - Menubar: shows mode (full/degraded), watch on/off, queue depth, last action.
  - Merge/split proposals: diff-like preview, approve/decline, undo.
  - Deep analysis: per-batch progress, pause/cancel, highlights upgraded/downgraded placements.
  - Collision dialogs: macOS-style rename preview (“file (1).pdf”).
- **Performance checks**
  - Filename-only fast path: sub-10s for 5k files on target hardware; streaming tree remains interactive.
  - Concurrency limits respected; no UI blocking during background refinement.
- **Data/logging correctness**
  - Movement log entries durable with IDs (timestamp/source/destination/reason/confidence/mode/provider).
  - Structured logs are single-block/copyable; schema version logged; migrations applied idempotently.
- **Non-functional**
  - Accessibility: keyboard parity for tree ops; VoiceOver labels on hierarchy, status, buttons.
  - Notifications: in-app toasts for routine events; system notifications only for long-running watch actions.
- **Release gates**
  - All unit/integration suites green; performance target met; manual UX acceptance checklist for wizard, watch, merge/split, degraded-mode prompt/return.
## Addendum: Infrastructure Augmentations (aligned with updated spec)
- **LLM routing layer**
  - Routing shim per request: choose provider (local/cloud) with health checks, exponential backoff, per-provider timeouts, and a “degraded/local-only” path that bypasses cloud.
  - Shared context for UI: exposes current LLM mode (full/degraded/offline), backoff state, last error; drives status bars/toasts/menubar.
- **Task orchestration**
  - Background task manager for deep analysis and watch jobs: queueing, prioritization (UI > watch > retries), cancellation, per-batch progress channels.
  - Backpressure: concurrency caps, system load checks, circuit breaker for repeated LLM failures.
- **Organizer safety core**
  - Command/undo framework for file ops with durable move log (GRDB): timestamp, source, destination, reason, confidence, mode (full/degraded), provider/version.
  - Collision resolver: deterministic macOS-style rename plans; simulate and log before execution; dry-run mode for previews.
- **Schema & migrations**
  - GRDB migration harness with versioning + fixtures; keep schema minimal (files, moves, prototypes, clusters) while volatile.
  - Log schema version; block destructive changes without migration.
- **Taxonomy & prototypes**
  - Prototype store with shared prototypes (linked folders) and per-folder scope; EMA decay, version tagging.
  - Clustering module (spherical k-means or HDBSCAN) respecting advisory depth; supports streaming updates; emits exemplars.
  - Confidence service combining prototype similarity, cluster density, heuristics (extension/parent-folder), tuned to ≥85% auto-place precision.
- **Embeddings & caching**
  - Embedding cache keyed by filename + parent path hash; small sentence transformer (~tens of MB) plus char/word n-grams; persisted for watch reuse.
  - Lightweight on-disk index for fast nearest-neighbor lookup for prototypes/clusters.
- **Watch subsystem**
  - FSEvents watcher with quiet-period batching, partial-download/in-use skips, large-file gating.
  - Status surface: watch on/off, mode (full/degraded), queue depth, last action; hooks into task manager and UI (menubar/HUD).
- **Telemetry & observability**
  - Structured, single-block logs for mode switches, retries, organizer actions, migrations, prototype/cluster updates; IDs for moves and LLM calls.
  - Optional metrics: success/fail/timeout, auto-place vs review rates, watch queue depth.
- **Preferences & state surface**
  - Central config service: destination modes, depth, stability↔correctness, soft-move, deep-analysis file types, battery behavior, notifications, current LLM mode/backoff.
  - UI-facing read model to drive status bars/toasts/menubar.
- **Error handling & recovery**
  - Standard retry/backoff for LLM/network; “Retry” + “Details” surfaces for UI.
  - Guardrail: never override user-approved placements on recovery.

## Sequencing (pragmatic order)
1) Migration harness + movement log schema + undo stack skeleton.
2) LLM routing with health detection, UI toast, degraded-mode toggle, and backoff.
3) Organizer safety (collision handling, soft-move option, invariant enforcement).
4) Pipeline fixes: depth enforcement, merge/split gating, guardrails on user edits.
5) Deep-analysis task manager + UI status.
6) Continuous watch hardening + status UI.
7) Preferences panel updates + degraded/full mode surfacing.
8) Tests + telemetry/log polish.

## Risks & Mitigations
- Schema churn: keep schema small; use migrations with fixtures.
- LLM latency/cost: enforce timeouts, batch where safe, expose mode and backoff.
- User trust: require approval for merges/splits; never move without undo; always log moves.
- Performance: throttle background work; respect quiet periods; avoid blocking UI.

## Implementation Tasks (Concrete, incremental)
- LLM routing & degraded mode
  - Add LLMRoutingService with provider registry (Ollama + OpenAI gpt-5.2), per-provider timeouts, exponential backoff, health checks, and mode state (full/degraded/offline) exposed for UI.
  - Extend config to hold OpenAI API key/model gpt-5.2/endpoint; add routing policy (local/cloud, degraded).
  - Wire UI status/toasts/menubar hooks to routing state; log mode switches with IDs.
- Background task manager
  - Introduce TaskManager for deep analysis + watch jobs: priorities (UI > watch > retries), cancellation, per-batch progress, backpressure (concurrency caps + system load), circuit breaker for repeated LLM failures.
  - Integrate DeepAnalyzer calls through TaskManager; emit progress for UI.
- Organizer safety & movement log
  - Add command/undo stack for file ops; enforce no-delete invariant; add soft-move/alias-first path and dry-run preview.
  - Add MovementLog (GRDB) with fields: id, timestamp, source, destination, reason, confidence, mode (full/degraded), provider/version; export/import support; retention 90 days.
  - Implement CollisionResolver for macOS-style rename plans with preview logging.
- Schema & migrations
  - Add GRDB migration harness with versioning and fixtures; log schema version; block destructive changes without migration.
  - Add movement log schema and indexes; keep schema minimal while volatile.
- Taxonomy/confidence path
  - Update SemanticThemeClusterer/Inference to enforce advisory depth; use spherical k-means or HDBSCAN; emit exemplars.
  - Add PrototypeStore with shared prototypes (linked folders), EMA decay, version tagging.
  - Implement ConfidenceService combining prototype similarity, cluster density, heuristics (extension/parent-folder), tuned to ≥85% auto-place precision.
- Embeddings & cache
  - Add embedding cache keyed by filename+parent hash; use `all-MiniLM-L6-v2` + char/word n-grams; persist cache for watch reuse.
  - Add lightweight on-disk NN index for prototype/cluster lookup; ensure sub-10s for 5k filename-only path.
- Watch subsystem
  - Implement FSEvents watcher (start with Downloads) with quiet-period 10s, partial-download/in-use skip, large-file gating (>100 MB), backpressure via TaskManager.
  - Surface status (mode, watch on/off, queue depth, last action) to menubar/HUD.
- Deep analysis guardrails
  - Add pause/cancel, per-batch progress events; guard against overriding user-approved placements; structured logs with IDs for each file/batch.
- UI/UX surfaces
  - Menubar item with mode (full/degraded), watch toggle, queue depth, last action, pause/resume.
  - “Needs Review” bucket view; merge/split diff previews with approve/decline + undo; exemplar lists per category.
  - Status/toasts for LLM/degraded/watch/deep-analysis; collision dialogs with rename preview; maintain keyboard parity and VoiceOver labels (not blocker).
- Preferences/config surface
  - Central config service exposing destination modes, depth, stability↔correctness, soft-move, deep-analysis file types, battery behavior, notifications, current LLM mode/backoff; provide UI read model.
- Telemetry & logging
  - Structured single-block logs with IDs for moves and LLM calls; metrics (success/fail/timeout, auto-place vs review, queue depth); log schema version.
- Testing
  - Add/extend tests per Testing & QA plan: routing modes/backoff, organizer command/undo/collision, clustering depth/exemplar/confidence, watch quiet-period/backpressure/gating, deep-analysis guardrails, logging durability; UI smoke for wizard/menubar/review/merge-split/degraded prompt.
