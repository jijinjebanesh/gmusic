# GMusic Implementation Status

**Baseline date:** 2026-11-09  
**Scope:** Current implementation in `D:\flutter projects\GMusic` plus `D:\Backend\Gdrive_backend`.  
**Current task outcome:** The product uses one common Google Drive library and one shared MongoDB backend for all GMusic accounts by default. User-specific app data remains scoped by authenticated account. Per-user Drive mode remains an optional deployment setting. Live service validation remains pending; the broader specification is still partial.

## Status key

- **Completed / Tested:** present and verified by the stated checks.
- **Partial:** some real behavior exists, but the full specification is not satisfied.
- **Missing:** no implementation found.
- **Broken:** implementation exists but source inspection found a concrete defect.
- **Unverified:** requires a live service, device, or integration test not run here.

## Current baseline

| Module | Current status | Evidence / next action |
|---|---|---|
| App startup and theme | Partial | Riverpod, persisted theme, audio service, Material theme exist; design/content remains limited |
| Navigation shell | Partial | Library, Explore, Queue and Settings tabs share the global mini-player; no dedicated Search/detail route system |
| Register/login | Partial | Real backend endpoints and bcrypt/session creation exist; run DB-backed tests and harden device token storage |
| Session validation | Partial; transient failure fixed | HTTP 401 clears the session; other bridge/database failures preserve it and are surfaced in Settings |
| Backend user separation | Partial | Favorites/recent/playlists use authenticated identity; session/account management APIs are limited |
| Device favorites | Partial; isolation/retry fixed | Account-scoped SharedPreferences keys and durable add/remove outbox; legacy global favorites are not migrated because ownership is ambiguous |
| Shared Drive OAuth | Partial; shared flow preserved, live flow unverified | One backend-wide Drive connection is shared across GMusic users; Settings starts authorization and sync; Google/Mongo configuration must be tested |
| Drive listing | Partial | One shared resumable index/change cursor and catalog are the default; optional `GMUSIC_DRIVE_MODE=per_user` scopes separate Drive accounts |
| Search | Partial | Backend catalog/search APIs and normalized metadata are wired to paginated Flutter track search; suggestions/history/categories remain |
| Track metadata | Partial | Backend extracts bounded audio tags and normalizes artist/album/genre data; source-specific coverage and live index validation remain |
| Artwork | Partial | Embedded cover parsing and Flutter image cache; no persistent derivative/thumbnail management |
| Audio streaming | Partial / unverified | Streaming and Range forwarding exist; no dedicated range/abort tests or live Drive validation |
| Central player | Partial | One just_audio engine/audio handler now publishes playback state and position/duration streams; no queue persistence/device media-session verification |
| Queue | Partial; duplicate occurrences supported | Positional queue occurrence mapping supports duplicate IDs through shuffle, reorder and removal; persistence/history/context and operation tests remain |
| Mini-player/full player | Partial | Mini-player like and Now Playing favorite synchronize remotely; volume controls operate on the shared player; dismiss, full-player options and device validation remain |
| Background playback/notification | Partial / unverified | Handler publishes media-session state; Android notification, audio-focus and physical-device tests absent |
| Favorites/recent history | Partial | Backend endpoints and local optimistic behavior; offline retries and event-level history absent |
| Playlists | Partial | Backend create/list/update/delete only; no Flutter UI/client, item-level operations or revision model |
| Saved albums/followed artists | Missing | No persistence, endpoints, or UI |
| Downloads/offline | Missing | No audio download manager or offline playback catalog |
| Lyrics/audio features | Missing | No lyrics source, sleep timer, equalizer, crossfade, gapless, or normalization |
| Recommendations/statistics | Missing | No real listening-event pipeline or analytics/recommendation APIs |
| Account/profile/preferences | Partial | Basic public identity and local theme only; account/profile and server preference management absent |
| Backend security/configuration | Partially remediated | Optional per-user refresh tokens and OAuth verifiers are AES-GCM encrypted and owner-bound; callback and signed-ticket paths are excluded from request logs; rotate any previously exposed credentials and audit Git history before release |
| Test coverage | Partial | Flutter has 20 passing unit tests across five files; backend has 13 passing tests including shared-default OAuth, optional PKCE/encryption, owner-isolated indexing, revocation failure handling, catalog and sync behavior; Mongo/Drive/device domains remain untested |
| Platform readiness | Partial | Android/web/Windows scaffold; no iOS project; Android release network/signing configuration needs verification |

## Verification baseline

| Check | Result |
|---|---|
| `flutter test` | Passed, 20 unit tests across 5 files |
| `flutter analyze` | 10 info-level diagnostics; nonzero exit; no analyzer errors or warnings |
| `npm test` in `D:\Backend\Gdrive_backend` | Passed, 13 tests (OAuth PKCE/encryption, user isolation, shared-mode route compatibility, revocation failure, HTTP auth, catalog/indexing/sync) |
| MongoDB/Atlas integration | Not run |
| Live Google Drive/OAuth/stream test | Not run |
| Widget/integration tests | Not present / not run |
| Android background/notification/device test | Not run |
| Release build | Not run |

### Shared Drive configuration milestone

- Corrected the deployment default to the intended common library: all signed-in GMusic accounts browse the backend's one shared Google Drive and shared catalog. MongoDB remains a common database, with account-owned favorites, recent history and playlists scoped by user ID.
- Settings reports shared Drive status, opens the common account's Google authorization flow, and runs a bounded shared index batch.
- Retained separately scoped Drive OAuth as an optional `GMUSIC_DRIVE_MODE=per_user` deployment mode. Its one-use PKCE state, encrypted tokens/verifiers, scoped index/catalog/cache/tickets, and disconnect flow remain available.
- Existing shared Drive tokens and catalog records remain usable. Switching storage modes does not automatically copy shared catalog records into per-user namespaces.
- Remaining gate: validate Google OAuth consent/callback, Drive token refresh, MongoDB persistence/indexes, and streaming against the configured common Drive account.

## Ordered implementation checklist

Dependencies follow the specification's Phases 0–10. `Phase 0` is complete: the audit inventory and validation are recorded in the two documents.

### Phase 0 — Audit existing project

**Status: Complete**

- [x] Inspect Flutter screens, models, state, services, tests, and platform configuration.
- [x] Inspect backend auth, Drive, MongoDB, routes, deployment, tests, and utility scripts.
- [x] Map current API contracts and collections/indexes.
- [x] Run baseline Flutter tests, analyzer, and backend test.
- [x] Save and review `IMPLEMENTATION_AUDIT.md` and this checklist.

### Pre-implementation security gate

**Status: In Progress (code-side remediation done; external credential rotation remains)**

- [ ] Rotate any credentials embedded in tracked backend scripts and any corresponding live credential.
- [x] Remove hard-coded database/account credential defaults; require environment configuration and placeholders only.
- [ ] Redact inspection output and ticket-bearing URLs; label destructive scripts and require explicit safeguards.
- [ ] Confirm secrets remain ignored/untracked and audit repository history for prior exposure.
- [ ] Scope local favorites, queue, and future user data to the authenticated account; define merge/delete conflict rules.
- [ ] Verify release INTERNET permission, cleartext policy, and non-debug release signing.

### Phase 1 — Foundation and stability

**Status: Partial**

- [ ] Add regression tests for existing login/register/me/logout and per-user favorites/recent/playlists.
- [ ] Keep local session material in platform secure storage.
- [x] Preserve the session on transient restore failures; clear it only after an explicit HTTP 401.
- [ ] Preserve existing backend session-hash semantics and response shapes; implement refresh/logout-all only with explicit compatibility and rotation behavior.
- [ ] Centralize API timeout, cancellation, error mapping, and protected request handling without changing current endpoint contracts.
- [ ] Add durable local outbox/retry and idempotent reconciliation for recent-history operations; make deletion/tombstones explicit.
- [x] Scope local favorites and their pending mutations to the authenticated account.
- [x] Fix `addNext` order bookkeeping.
- [x] Publish audio_service playback state/metadata/capabilities and subscribe the UI to regular position/duration updates.
- [ ] Test duplicate occurrences, reorder, remove-current, shuffle toggle, repeat, and queue replacement.
- [ ] Verify notification/lock-screen/audio-focus behavior on Android hardware; do not infer it from manifest setup alone.
- [x] Remove no-op player controls and wire volume/favorite actions to the shared player and account synchronization.
- [ ] Resolve baseline analyzer diagnostics in files touched by this phase.

### Phase 2 — Drive indexing and metadata

**Status: Partial (backend code and isolated tests pass; live integrations pending)**

- [x] Introduce persistent Drive-file index keyed by stable file ID; preserve original Drive file metadata separately from user corrections.
- [x] Support paginated initial scan, supported audio extensions/MIME fallback, resumable progress, and explicit error/retry states.
- [x] Support a common shared Drive index by default and optional per-user index/catalog scoping when explicitly configured.
- [x] Extract bounded audio metadata from stream heads; cover-art extraction, broad codec/tag fixtures and real-file validation remain.
- [x] Normalize artists conservatively and group albums with artist/disc/track ordering; compilation and untagged-track behavior needs broader fixtures.
- [ ] Store/cache artwork derivatives and invalidate them when source metadata changes.
- [x] Implement Drive changes token sync, changed/trashed file behavior, expired-token recovery, retry and interrupted scans.
- [x] Retry previously partial metadata extraction during later bounded Drive sync batches.
- [x] Add Mongo indexes and a compatibility plan based on catalog query shapes.
- [x] Expose truthful Drive/index status and progress through versioned APIs.
- [x] Test paginated resume, modified/deleted files, metadata tags and page-token validation with isolated tests; expired-token, duplicate-name and artwork-failure tests remain.

### Phase 3 — Catalog and discovery UI

**Status: Partial (catalog APIs, track search and Explore flows wired; broader discovery remains)**

- [x] Add indexed track/artist/album/genre catalog APIs with pagination and stable IDs.
- [x] Add global indexed search endpoint; suggestions/history/categories and UI ranking behavior remain.
- [x] Wire paginated track search and artist/album/genre Explore pages to indexed backend data.
- [ ] Build separate Home, Search, Explore, artist, album, and track-detail flows using real indexed content.
- [ ] Preserve tab/page state and add consistent navigation/back/deep-link behavior where supported.
- [ ] Use cached results, lazy loading, empty/loading/error states, and avoid repeated tracks across adjacent sections.
- [ ] Test catalog contracts, ranking, pagination, and UI navigation.

### Phase 4 — Playback engine

**Status: Partial (single handler retained; playback-state and timeline publication implemented)**

- [x] Keep one authoritative audio handler/player and refresh stream tickets through the catalog client.
- [x] Publish audio_service state and regular position/duration updates.
- [ ] Complete queue model, history, playback context, autoplay, persistence, restore, and deterministic ordering.
- [ ] Complete play/pause/seek/previous/next/shuffle/repeat and deleted/expired/unavailable-track recovery.
- [ ] Complete mini-player and Now Playing behavior, including progress/buffer, shared actions, accessibility and reduced motion.
- [ ] Verify Range/206/416 semantics and stream cancellation against Drive behavior; do not buffer full audio files.
- [ ] Test audio_service state and Android notification, lock-screen, wired/Bluetooth controls, interruptions, and process recovery on device.
- [ ] Add targeted unit, integration, and device test coverage.

### Phase 5 — Personal library

**Status: Partial (favorites and recent/playlists foundations exist; most library features remain)**

- [ ] Complete Liked Songs with account-scoped persistence, retryable synchronization, search/filter/sort/bulk actions.
- [ ] Add saved albums and followed artists as user relationships.
- [ ] Add playlist Flutter UI/client and create/edit/delete/add/remove/reorder/duplicate/search operations.
- [ ] Keep playlist items as stable track references; enforce ownership, deterministic position, version/conflict handling, and unavailable-item behavior.
- [ ] Expand recent plays into distinct listening events with started/played/completed/skipped semantics.
- [ ] Add Your Library filtering/sorting and persist supported user preferences across devices.
- [ ] Test account separation, offline mutations, idempotency, playlist ordering, and sync conflicts.

### Phase 6 — Downloads and offline

**Status: Not Started**

- [ ] Implement real track/album/playlist downloads with pause/resume/cancel/retry and durable task state.
- [ ] Write to temporary files, validate size/checksum, and atomically finalize only successful downloads.
- [ ] Separate permanent audio downloads, transient stream cache, and artwork cache.
- [ ] Add offline catalog/playback, unavailable-streaming states, sync recovery, and duplicate handling.
- [ ] Add storage usage/cleanup controls that never remove original Drive files or permanent downloads accidentally.
- [ ] Test interruption, insufficient space, partial-file recovery, duplicate download, and offline playback.

### Phase 7 — Advanced audio

**Status: Not Started**

- [ ] Add lyrics abstraction using embedded/authorized sources only; handle static/synchronized/unavailable states.
- [ ] Add background-safe sleep timer with end-of-track/custom options and cancellation.
- [ ] Implement equalizer/balance/normalization/crossfade/gapless only where actual engine/platform support exists.
- [ ] Persist and apply audio preferences; clearly report unsupported device capabilities.
- [ ] Test playback continuity and platform-specific limitations.

### Phase 8 — Recommendations

**Status: Not Started**

- [ ] Build rule-based recommendations from actual indexed tracks and authenticated listening signals.
- [ ] Add similar tracks, radio, genre/mood mixes only when metadata supports them.
- [ ] Add recommendation feedback and avoid repeats/unwanted tracks.
- [ ] Do not fabricate trending content or claim schedule/“Daily Mix” behavior not implemented.
- [ ] Test with sparse/no-history collections and ensure every suggestion is playable.

### Phase 9 — Statistics and personalization

**Status: Not Started**

- [ ] Define meaningful play-count/completion thresholds and exclude invalid sessions.
- [ ] Aggregate time-bounded top tracks/artists/albums, genres, activity, and total listening time from actual events.
- [ ] Add yearly recap only for periods with stored history; disclose unavailable history.
- [ ] Test time zones, repeated plays, skipped tracks, and aggregation correctness.

### Phase 10 — Security and production hardening

**Status: Partial (per-user Drive isolation implemented; broader production gates remain)**

- [x] Review per-user OAuth state, encrypted token ownership, catalog/index/artwork/stream owner scoping, and OAuth callback query-log redaction.
- [ ] Review remaining route authentication, validation, rate limiting, account deletion, and safe logging.
- [ ] Re-review signed tickets, lifetime, CORS/proxy trust, Drive permission checks, range semantics, and client disconnects.
- [ ] Review Mongo query/index plans and behavior at thousands of files/large playlists.
- [ ] Run failure/recovery tests for Mongo, Drive, network, streaming, indexing, offline synchronization, and downloads.
- [ ] Verify release manifests/signing on Android and supported web/Windows deployment modes.
- [ ] Run full relevant suites and actual device validation; record known limitations before marking any module Complete.

## Feature completion policy

Do not mark a module **Complete** when only its screen or endpoint exists. A feature must have the needed UI, state ownership, API/auth, persistence, failure/offline behavior, and relevant tests. In particular:

- Keep Drive catalog synchronization independent of favorites/playlist synchronization.
- Preserve current backend collection names and session hashing unless a concrete migration is approved and tested.
- Do not add a second player, authentication stack, audio catalog, or fake recommendation/download behavior.
- Do not claim physical-device playback or production readiness based only on the current unit tests.
