# GMusic Implementation Audit

**Audit date:** 2026-11-09  
**Scope:** Flutter workspace at `D:\flutter projects\GMusic` and separate Node.js backend at `D:\Backend\Gdrive_backend`.  
**Audit boundary:** This document records the pre-implementation baseline. Subsequent implementation progress is summarized below and tracked in `IMPLEMENTATION_STATUS.md`.

## Executive summary

At the time of the audit, GMusic had a usable but small end-to-end slice: account registration/login against MongoDB, a single backend-linked Google Drive account, paginated Drive file listing, filename-derived track labels, signed stream/art tickets, one `just_audio` engine hosted by an `audio_service` handler, and a basic Flutter library/queue/settings UI. The backend preserves useful security properties: session tokens are hashed in MongoDB, passwords are bcrypt-hashed, protected routes derive the user from the session, and Drive credentials remain on the backend.

The implementation was **not yet the specification's indexed personal music platform** at audit time. The backend has since gained a persistent Drive-track index, bounded audio tag extraction, normalized catalog APIs, resumable initial indexing, and incremental Drive change-token sync. Flutter now consumes normalized track metadata and paginated catalog pages, exposes index status/manual sync, and publishes player position and audio-service playback state. MongoDB/Drive integration, remaining UI areas, and broader playback/device behaviors are still unverified or incomplete.

The latest source review fixed the account-isolation and session-loss defects, made favorite updates retryable, connected Now Playing favorite and volume controls, modeled queue entries by occurrence rather than track ID, and corrected partial-metadata retry and MongoDB `_id` update behavior. Remaining risks include:

1. **Tracked credential exposure risk:** helper scripts were hardened to require environment-only inputs and avoid account/session deletion or data disclosure. Treat any previously committed credentials as exposed: rotate them and audit repository history before distributing or deploying the backend.
2. **Legacy local favorites:** pre-existing values in the old device-wide key are not migrated to an account because ownership cannot be established safely. They remain isolated from signed-in account state; recover or assign them only through an explicit user-controlled migration.
3. **Session security:** the session token is still stored in ordinary SharedPreferences, not platform secure storage. Refresh, logout-all-devices, profile editing and account deletion are absent.
4. **Recent history:** local recent state is memory-only and remote writes have no durable retry queue. The backend stores one latest timestamp per track, not separate listening events.
5. **Queue and player validation:** occurrence-level duplicate handling is implemented, but shuffle/reorder/remove-current behavior has no dedicated unit tests. Queue persistence, playback context, autoplay, and physical-device media-session behavior remain incomplete or unverified.

The current backend suite passes 13 tests, and Flutter unit tests pass 20 tests across five files. `flutter analyze` reports 10 informational diagnostics and exits nonzero; there are no analyzer errors or warnings. The available tests do not establish MongoDB integration, live Drive behavior, device background playback, or media-notification correctness.

## Implementation checkpoint after backend/catalog milestone

- Added `drive_tracks` and `drive_sync_state` persistence with stable Drive-file IDs, resumable full scans, metadata normalization, availability tracking, and incremental change-token sync.
- Added authenticated `/api/v1/drive/status`, `/api/v1/drive/sync/status`, `/api/v1/drive/sync`, `/api/v1/catalog/*`, `/api/v1/artists`, `/api/v1/albums`, `/api/v1/genres`, and `/api/v1/search` routes. Existing `/api/v1/tracks` remains the live Drive listing contract.
- Added cached embedded artwork records with a size cap and TTL; generated thumbnails are not implemented.
- Added Flutter catalog metadata parsing, paginated catalog/legacy listing, index status/manual sync UI, and bounded load-more behavior.
- Added an Explore tab for indexed artists, albums and genres, with paginated playable collection pages.
- Fixed the queue `addNext` backing-list insertion and connected player position/duration streams to the UI and audio-service playback-state stream.
- Backend tests use an isolated in-memory collection adapter for indexer state transitions; this does not replace real MongoDB/Drive integration testing.

## Full-specification review updates

- Session restoration now clears local credentials only after an explicit HTTP 401. Transient bridge/database failures preserve the session and appear in Settings with a retry action.
- Favorites now use an account-specific preference key, persist pending add/remove mutations before the network request, retry those mutations during session restoration, and reconcile from the remote set only after pending changes succeed. Home, mini-player and Now Playing actions use the same synchronization path.
- Now Playing volume buttons and slider now control the shared audio engine. Queue ordering uses positional entry identity so two occurrences of the same Drive track can be shuffled, reordered, and removed independently.
- API clients created by library and Drive-status controllers now use the cached settings client rather than allocating unclosed HTTP clients.
- A partial metadata parse is retried in bounded batches during later Drive syncs. Catalog upserts no longer attempt to write MongoDB's immutable `_id` field.
- Confirmed and set the intended data model as the default: all GMusic accounts use one common Google Drive library and one shared MongoDB backend; favorites, recent history and playlists remain separated by GMusic account.
- Kept a shared Drive OAuth flow in Settings for the common library. The backend also supports optional per-user Drive OAuth with one-use Mongo-backed PKCE state, AES-256-GCM token/verifier encryption, callback log redaction and revoke/disconnect.
- The default shared catalog/index/cache is common to all GMusic accounts. Optional `GMUSIC_DRIVE_MODE=per_user` scopes index cursors, catalog records, artwork cache and tickets to each account.
- Added isolated tests for shared-mode OAuth, encrypted tokens, PKCE/replay rejection, owner isolation in optional per-user mode, and revocation failure handling. Live Google/Mongo integration is still unverified.
- A source search found no remaining empty `onPressed`/`onTap` callbacks, `TODO`/`FIXME` markers, or hardcoded sample-track/recommendation data in the inspected Flutter/backend source.
- Confirmed remaining gaps include: personalized Home, categorized/debounced search and history, complete artist/album details, playlists in Flutter and item-level playlist operations, saved albums/followed artists, durable recent-event history, downloads/offline playback, lyrics, advanced audio processing/timers, recommendations, statistics, and full profile/preferences/account management.

## Current architecture

```text
Flutter app (Riverpod, SharedPreferences)
  ├─ Account/session client ── bearer session ──┐
  ├─ catalog/listing client ─────────────────────┤
  └─ just_audio in one audio_service handler     │
                                                 v
Express bridge (local Node 22 or Vercel) ── MongoDB Atlas
  ├─ auth, favorites, recent plays, playlists
  ├─ Common Drive OAuth, live listing, shared indexed catalog and incremental sync
  └─ signed 8-hour tickets -> streaming/art handlers
                                                 │
                                                 v
                             One common Google Drive library
```

Flutter launches Google's consent page in the system browser; the common Drive credential remains on the backend, and all signed-in GMusic accounts use the same Drive catalog. The backend's MongoDB is also common, while user-owned app records remain account-scoped. Optional `GMUSIC_DRIVE_MODE=per_user` enables separate Google connections; those refresh tokens and temporary PKCE verifiers are AES-256-GCM encrypted with an environment-supplied key.

## Feature status against Parts 1–2 and the target architecture

| Area | Audit status | Evidence and consequence |
|---|---|---|
| Flutter shell and navigation | **Partial** | `IndexedStack` preserves the Library, Explore, Queue and Settings tabs, with `MiniPlayer` above navigation. There is no separate Search/Your Library route, deep linking, or centralized router. |
| Registration and login | **Partial / implemented slice** | Flutter forms call real backend routes. Registration and login create sessions; password is bcrypt-hashed and API session token is SHA-256 hashed server-side. No refresh, logout-all-devices, profile editing, account deletion, or secure device token storage is implemented. |
| Session persistence | **Partial; transient restore fixed** | Restore clears the session only after HTTP 401 and preserves it on transient failure. The token remains in ordinary SharedPreferences rather than platform secure storage. |
| User isolation | **Partial; Drive/catalog scope implemented** | User data, Drive connections, indexes, catalog results, cache keys, and tickets are owner-scoped. The legacy global favorite list is intentionally not migrated because its account owner is ambiguous. |
| Google Drive auth | **Partial; implementation wired, live flow unverified** | Flutter Settings starts OAuth in the system browser, refreshes status and can disconnect/revoke. The backend binds one-use PKCE state to the initiating user and encrypts tokens; live configuration and consent remain unverified. |
| Drive listing | **Partial** | The default is one common Drive client and shared resumable index/change sync for all GMusic accounts. Optional per-user mode scopes separate clients and catalogs. Live Mongo/Drive validation remains pending. |
| Music metadata/catalog | **Partial** | Backend extracts bounded stream-head tags and normalizes track/artist/album/genre fields. Flutter consumes normalized track fields; broad codec coverage, source-specific parsing and metadata corrections are incomplete. |
| Search | **Partial** | Flutter submits paginated track search against the indexed catalog when available, with legacy filename listing as fallback. Explore browses real indexed artists/albums/genres; there is no debounce, suggestions/history, or relevance ranking. |
| Audio streaming | **Partial / needs validation** | The backend streams Drive response streams and forwards a `Range` header and upstream response headers. Signed tickets are valid for eight hours. There is no explicit client-disconnect cancellation or dedicated 416/range validation; tests do not exercise streaming/range behavior. |
| Artwork | **Partial** | Backend extracts embedded ID3v2/FLAC/MP4 art from an initial range and Flutter caches the ticket-backed image. Extraction is not persisted as a thumbnail cache; a 1 MiB head read can miss later/large MP4 metadata. |
| Central playback | **Partial** | One `AudioPlayer` is owned by one `GMusicAudioHandler`; the mini-player, full player, and queue use it. Position/duration streams and audio-service playback state are now published. Queue persistence, playback context/history, error recovery coverage and device validation are incomplete. |
| Queue operations | **Partial; duplicate occurrences supported** | Add/remove/reorder/clear/shuffle/repeat/next/previous are present. Queue entry ordering is positional so same-track occurrences remain distinct. Queue persistence/history/autoplay and targeted operation tests remain. |
| Background playback and notifications | **Partial / unverified** | `AudioService.init`, Android media playback service declaration, handler transport overrides and playback-state publication are present. No integration/device test verifies notification metadata, Bluetooth, audio focus, or process recovery. |
| Favorites | **Partial; device isolation and retry fixed** | Favorites are account-scoped locally; adds/removals enter a persistent retry queue before remote requests. Home, mini-player and Now Playing use the same sync flow. Legacy global favorites are not migrated automatically; full Liked Songs/library features remain absent. |
| Recently played/history | **Partial** | A play tap is recorded remotely and the backend keeps a capped, per-track latest timestamp. Local optimistic history is not persisted and failed writes are not retried. There are no separate listening events, played durations, completion/skip events, or statistics. |
| Playlists | **Partial backend only** | MongoDB playlist records can be listed, created, renamed/replaced by ID array, and deleted. No Flutter playlist client/screens; no item-specific mutations, ordering API, description/artwork, revision, or track resolution. |
| Personal library (saved albums/artists) | **Missing** | No saved-album or followed-artist collections, endpoints, or UI. |
| Downloads/offline | **Missing** | No download manager, permanent audio files, offline playback catalog, storage accounting, or cache policy. Artwork caching is not an audio download feature. |
| Lyrics/audio enhancements | **Missing** | No lyrics source, sleep timer, equalizer, crossfade, gapless setting, normalization, or persistent playback preferences. Player volume works but is currently in-memory. |
| Recommendations/analytics/profile | **Missing** | No recommendation engine, listening-event analytics, statistics, profile, account management, or user-level preferences APIs. |
| Error handling | **Partial** | Backend centralizes Drive/API errors and the Flutter API client now preserves backend status/error codes. Session restoration, offline mutations and several account-state paths still lack explicit retry/reconciliation behavior. |
| Tests | **Partial** | Flutter unit tests cover OAuth URL validation, parsing, request/auth basics, catalog pages and metadata; backend tests cover shared-default OAuth, optional PKCE/encryption/replay, owner isolation, catalog and fake-store indexing. No live DB/Drive, playlist, range-stream, playback, widget, integration, or device tests. |
| Platform support | **Partial** | Android, web, and Windows project scaffolds exist. No iOS project is present. Android main manifest enables cleartext traffic; INTERNET appears in debug/profile manifests but not the checked-in main manifest, so the merged release manifest should be verified before release. Release Gradle signing uses the debug key. |

## Remaining verified defects and release risks

### Data and behavior

- **Favorites:** current storage and pending add/remove mutations are account-scoped and retried. Legacy global favorites remain intentionally unmigrated because their owner is ambiguous.
- **Recent-history durability:** `RecentController.record()` updates only in-memory state before a best-effort API call. It does not enqueue a failed request or persist the local event. Server-side recent is a per-track upsert, not an event log.
- **Queue duplicates:** occurrence identity now distinguishes repeated track IDs for shuffle/reorder/remove, but the full queue-operation matrix is not unit-tested.
- **Session recovery:** transient restore failures preserve the session; session credentials remain in ordinary SharedPreferences, not platform secure storage.
- **Catalog behavior:** [`library_controller.dart`](lib/state/library_controller.dart) now pages on demand rather than loading up to 2,000 tracks at startup; catalog continuation and error paths still need widget-level coverage.

### Security and operational risk

- Backend secrets/config files are present locally but [`.env`](../../Backend/Gdrive_backend/.env), [`credentials.json`](../../Backend/Gdrive_backend/credentials.json), and [`data/token.json`](../../Backend/Gdrive_backend/data/token.json) are ignored and were not listed as tracked files in the backend checkout. Their contents were not read or reproduced.
- Tracked helper scripts `scripts/try_mongo.js` and `scripts/seed_phone_session.js` now require explicit environment configuration; rotate credentials that appeared in prior history and audit repository history before release.
- `scripts/reset_sessions.js` deletes matching session documents; `scripts/seed_phone_session.js` writes account/session data; `scripts/inspect_atlas.js` inspects a real database; the stream probes can retrieve real Drive content. These were **not run**.
- Express uses Helmet, a JSON size limit, and redacts authorization headers. OAuth callback and signed-ticket request logging is disabled to keep codes/state and bearer tickets out of logs. There is no configured rate limiter. Review owner-token fallback, ticket lifetime, CORS, remaining error logging, and stream-abort behavior before release.
- Android `usesCleartextTraffic="true"` permits cleartext app traffic; release should prefer HTTPS and limit local HTTP use to development as appropriate.

## MongoDB collections and indexes observed

There are no separate Mongo model/schema files. Collections are accessed directly through `col()` in [`src/auth.js`](../../Backend/Gdrive_backend/src/auth.js) and [`src/drive.js`](../../Backend/Gdrive_backend/src/drive.js).

| Collection | Current use | Indexes created in [`src/db.js`](../../Backend/Gdrive_backend/src/db.js) |
|---|---|---|
| `Users` | Registration/login, public profile projection, password hash | Partial unique `email`, partial unique `username` |
| `sessions` | Token-hash lookup, expiry and sliding renewal | Unique `tokenHash`; TTL `expiresAt`; `userId, createdAt` |
| `favorites` | Per-user track IDs plus client-supplied title/artist snapshot | Unique `userId, trackId` |
| `recent_plays` | Per-user, one latest row per track | `userId, playedAt` |
| `playlists` | Per-user name and embedded `trackIds` | Partial unique `userId, name` |
| `gdrive_tokens` | Common Drive OAuth token document (`_id: primary`); used by default shared mode and ignored in optional per-user mode | No explicit index beyond `_id` |
| `drive_connections` | Per-user AES-256-GCM encrypted token envelope and timestamps | Unique `userId` |
| `drive_oauth_states` | Hashed one-use OAuth state, encrypted PKCE verifier, user binding and expiry | Unique `stateHash`; TTL `expiresAt`; `userId` |
| `drive_tracks` | Owner-scoped normalized metadata and availability, keyed by owner plus Drive file ID | Unique `(ownerId, driveFileId)`; owner-prefixed title/artist/album/genre query indexes |
| `drive_sync_state` | Resumable owner-specific scan/change token and truthful sync counters; legacy shared state `_id: primary` | `_id` per owner |
| `artwork_cache` | Size-limited owner-keyed embedded artwork bytes with expiration | TTL `expiresAt` |

There are no separate artist/album collections; catalog groups are derived from indexed track metadata. Listening-event history, saved albums, followed artists, search history, preferences, downloads, and queue snapshots remain absent. Existing collection names and session-token hashing are compatibility constraints; do not create parallel auth or duplicate existing user data.

## Existing API map

Protected `/api/v1` routes use `attachUser`: a valid session token is hashed and looked up, renewed with a sliding 30-day expiry, then mapped to a server-side user. The owner API-token fallback is retained for bridge tooling. Public health is separate. Exact existing route contracts should be preserved or evolved compatibly.

| Method and path | Auth | Current behavior |
|---|---|---|
| `GET /health` | Public | Liveness, runtime, auth mode, Drive configuration/authorization state |
| `POST /api/v1/auth/register` | Public | Validates email and minimum password length, bcrypt-hashes password, creates user and session |
| `POST /api/v1/auth/login` | Public | Checks email/password, creates session |
| `POST /api/v1/auth/logout` | Session credential when supplied | Deletes matching session hash; route is mounted with public auth routes |
| `GET /api/v1/auth/me` | Protected | Returns the authenticated public user |
| `POST /api/v1/drive/oauth/start` | Protected | Starts common Drive authorization by default, or user-bound one-use PKCE when optional per-user mode is configured |
| `GET /api/v1/drive/oauth/callback` | Public, state-bound | Exchanges the authorization code for the initiating user's encrypted tokens |
| `POST /api/v1/drive/oauth/disconnect` | Protected | Attempts Google token revocation and removes local user connection |
| `POST /api/v1/auth/url` | Protected | Compatibility endpoint for common Drive OAuth |
| `GET /` | Shared-Drive callback | Completes common Drive OAuth after validating signed state |
| `GET /api/v1/status` | Protected | Backend/Drive status and minimal user identity |
| `GET /api/v1/tracks?q=&pageSize=&pageToken=` | Protected | Live paginated Drive listing; each returned file gets an 8-hour signed stream ticket |
| `GET /api/v1/drive/status` | Protected | Current user's Drive authorization, catalog availability and scoped index status |
| `GET /api/v1/drive/sync/status` | Protected | Current user's persistent full/incremental index state |
| `POST /api/v1/drive/sync` | Protected | Runs one bounded batch against the current user's Drive |
| `GET /api/v1/catalog/tracks?q=&pageSize=&pageToken=` | Protected | Paginated indexed tracks with normalized metadata and signed stream tickets |
| `GET /api/v1/catalog/tracks/:id` | Protected | One indexed track and fresh stream ticket |
| `GET /api/v1/artists`, `/api/v1/artists/:id`, `/api/v1/artists/:id/tracks`, `/api/v1/artists/:id/albums` | Protected | Indexed artist aggregates and pages |
| `GET /api/v1/albums`, `/api/v1/albums/:id`, `/api/v1/albums/:id/tracks` | Protected | Indexed album aggregates and ordered tracks |
| `GET /api/v1/genres` | Protected | Distinct indexed genres |
| `GET /api/v1/genres/:id/tracks` | Protected | Paginated tracks for one normalized genre |
| `GET /api/v1/search?q=&pageSize=&pageToken=` | Protected | Indexed track, artist and album search results |
| `GET /stream/:ticket` | Owner-bound signed ticket | Streams one user-authorized Drive file; forwards incoming Range request and upstream status/headers |
| `GET /art/:ticket` | Owner-bound signed ticket | Extracts embedded cover art from that user's Drive |
| `GET /api/v1/tracks/:id/stream` | Protected | Direct authenticated Drive stream by ID |
| `GET /api/v1/art/:id` | Protected | Embedded cover art by Drive ID |
| `GET /api/v1/favorites` | Protected | Lists current-user favorites |
| `PUT /api/v1/favorites/:trackId` | Protected | Upserts a favorite and title/artist snapshot |
| `DELETE /api/v1/favorites/:trackId` | Protected | Removes current-user favorite |
| `GET /api/v1/recent?limit=` | Protected | Lists recent per-track rows |
| `POST /api/v1/recent` | Protected | Upserts latest recent play for track; caps history at 200 |
| `GET /api/v1/playlists` | Protected | Lists current-user playlist documents |
| `POST /api/v1/playlists` | Protected | Creates an empty named playlist |
| `PUT /api/v1/playlists/:id` | Protected | Replaces name and/or entire ordered `trackIds` array |
| `DELETE /api/v1/playlists/:id` | Protected | Deletes a playlist owned by the user |

The target API in Part 21 is still partial: indexed catalog/sync/search endpoints now exist, but search history, playback resolve/events, library collections, granular playlist item/reorder operations, downloads, recommendations, analytics, and preferences remain absent.

## File and responsibility map

Generated build trees, Dart/Gradle caches, installed `node_modules`, and local secrets are not treated as source features. The following source/config/test files affect implementation or verification.

### Flutter workspace

| File(s) | Responsibility |
|---|---|
| [`pubspec.yaml`](pubspec.yaml), [`pubspec.lock`](pubspec.lock) | Flutter/Dart SDK and declared dependencies; Riverpod, HTTP, URL launcher, SharedPreferences, just_audio, audio_service, artwork cache |
| [`analysis_options.yaml`](analysis_options.yaml) | Dart lint/analyzer settings |
| [`README.md`](README.md) | Still the generated Flutter starter README; not a usable GMusic setup guide |
| [`master_prompt.md`](master_prompt.md) | Complete product/implementation specification audited for this task |
| [`lib/main.dart`](lib/main.dart), [`lib/app.dart`](lib/app.dart) | Initializes SharedPreferences/audio service and chooses setup/login/app shell; app theme |
| [`lib/models/track.dart`](lib/models/track.dart) | Drive/catalog response model, normalized metadata, filename fallback parsing and art URL derivation |
| [`lib/models/user.dart`](lib/models/user.dart) | Auth user/session, favorite and recent DTOs |
| [`lib/screens/app_shell.dart`](lib/screens/app_shell.dart) | Four-tab `IndexedStack`, library/auth startup, mini-player placement |
| [`lib/screens/home_tab.dart`](lib/screens/home_tab.dart) | Paginated catalog/live listing, track search, favorites filter/toggle, sync status, recent strip and queue actions |
| [`lib/screens/explore_tab.dart`](lib/screens/explore_tab.dart) | Indexed artists/albums/genres and paginated playable collection pages |
| [`lib/screens/login_screen.dart`](lib/screens/login_screen.dart), [`lib/screens/setup_screen.dart`](lib/screens/setup_screen.dart) | Register/login and backend URL configuration |
| [`lib/screens/now_playing_screen.dart`](lib/screens/now_playing_screen.dart), [`lib/screens/queue_screen.dart`](lib/screens/queue_screen.dart) | Full player and editable queue UI |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Bridge URL, session sign-out, system-browser Drive OAuth/connect/disconnect/sync, local theme choice |
| [`lib/services/audio_handler.dart`](lib/services/audio_handler.dart) | Single `AudioPlayer`, queue/order, transport operations, UI streams, audio_service handler |
| [`lib/services/drive_bridge_client.dart`](lib/services/drive_bridge_client.dart) | Backend HTTP/API client for auth, user data, user Drive OAuth, live/catalog track pages, status and sync |
| [`lib/services/drive_auth.dart`](lib/services/drive_auth.dart) | Reads user Drive status and manages OAuth start, disconnect and bounded sync state |
| [`lib/services/settings_store.dart`](lib/services/settings_store.dart) | Bridge/session/theme, cached HTTP client, account-scoped favorite cache and durable favorite outbox |
| [`lib/state/auth_controller.dart`](lib/state/auth_controller.dart) | Login/register, session restore/logout, transient-failure handling and favorite reconciliation |
| [`lib/state/library_controller.dart`](lib/state/library_controller.dart) | Drive/index status, catalog/live pagination, track search, load-more, sync action and ticket refresh |
| [`lib/state/recent_controller.dart`](lib/state/recent_controller.dart) | In-memory optimistic recent list and backend calls; no durable history outbox |
| [`lib/theme/app_theme.dart`](lib/theme/app_theme.dart), [`lib/theme/app_tokens.dart`](lib/theme/app_tokens.dart) | Material theme and design tokens |
| [`lib/widgets/mini_player.dart`](lib/widgets/mini_player.dart), [`lib/widgets/player_controls.dart`](lib/widgets/player_controls.dart) | Persistent mini-player and seek/play-pause controls |
| [`lib/widgets/track_tile.dart`](lib/widgets/track_tile.dart), [`lib/widgets/cover_image.dart`](lib/widgets/cover_image.dart) | Track row and cached cover/fallback |
| [`lib/utils/duration_format.dart`](lib/utils/duration_format.dart) | Duration formatting |
| [`test/drive_bridge_client_test.dart`](test/drive_bridge_client_test.dart) | Login/register request bodies and public auth headers |
| [`test/drive_client_test.dart`](test/drive_client_test.dart) | Legacy/catalog track-page parsing, normalized metadata and non-2xx handling |
| [`test/auth_controller_test.dart`](test/auth_controller_test.dart), [`test/settings_store_test.dart`](test/settings_store_test.dart) | Session restore failure behavior, account favorite isolation and retryable favorite mutations |
| [`test/track_test.dart`](test/track_test.dart) | Filename parser, artwork URL, duration formatter |
| [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml), [`android/app/src/debug/AndroidManifest.xml`](android/app/src/debug/AndroidManifest.xml), [`android/app/src/profile/AndroidManifest.xml`](android/app/src/profile/AndroidManifest.xml), [`android/app/build.gradle.kts`](android/app/build.gradle.kts) | Android app/service declaration, development network permission overlays, build/signing config |
| [`android/`](android/), [`android/build.gradle.kts`](android/build.gradle.kts), [`android/settings.gradle.kts`](android/settings.gradle.kts), [`android/gradle.properties`](android/gradle.properties), [`android/local.properties`](android/local.properties), [`android/gradlew`](android/gradlew), [`android/gradlew.bat`](android/gradlew.bat), [`android/gradle/wrapper/gradle-wrapper.properties`](android/gradle/wrapper/gradle-wrapper.properties) | Android build/SDK scaffolding; `local.properties` is machine-specific |
| [`android/app/src/main/kotlin/com/gmusic/gmusic/MainActivity.kt`](android/app/src/main/kotlin/com/gmusic/gmusic/MainActivity.kt), [`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`](android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java), [`android/app/src/main/res/`](android/app/src/main/res/) | Android host entry, generated plugin registration, app icon and splash resources |
| [`web/index.html`](web/index.html), [`web/manifest.json`](web/manifest.json), [`web/favicon.png`](web/favicon.png), [`web/icons/Icon-192.png`](web/icons/Icon-192.png), [`web/icons/Icon-512.png`](web/icons/Icon-512.png), [`web/icons/Icon-maskable-192.png`](web/icons/Icon-maskable-192.png), [`web/icons/Icon-maskable-512.png`](web/icons/Icon-maskable-512.png) | Web shell, PWA metadata and generated icons; description remains starter text |
| [`windows/`](windows/), [`windows/CMakeLists.txt`](windows/CMakeLists.txt), [`windows/flutter/CMakeLists.txt`](windows/flutter/CMakeLists.txt), [`windows/flutter/generated_plugins.cmake`](windows/flutter/generated_plugins.cmake), [`windows/flutter/generated_plugin_registrant.cc`](windows/flutter/generated_plugin_registrant.cc), [`windows/flutter/generated_plugin_registrant.h`](windows/flutter/generated_plugin_registrant.h), [`windows/runner/`](windows/runner/) | Windows Flutter/CMake/plugin/runner scaffold; no GMusic-specific backend or catalog logic |
| [`assets/icon.png`](assets/icon.png), [`.gitignore`](.gitignore), [`.metadata`](.metadata), [`.vscode/settings.json`](.vscode/settings.json), [`gmusic.iml`](gmusic.iml) | App asset, ignore/build metadata, editor/project config |

No `ios/` directory, Flutter database package, secure-storage package, router, generated localization, or widget/integration test suite was found.

### Node.js backend (`D:\Backend\Gdrive_backend`)

| File(s) | Responsibility |
|---|---|
| [`../../Backend/Gdrive_backend/package.json`](../../Backend/Gdrive_backend/package.json), [`../../Backend/Gdrive_backend/package-lock.json`](../../Backend/Gdrive_backend/package-lock.json) | Node 22 / Express 5 package, MongoDB, Google APIs, bcrypt, Helmet, Pino, music-metadata; Node test command |
| [`../../Backend/Gdrive_backend/README.md`](../../Backend/Gdrive_backend/README.md) | Local bridge/Vercel setup and current API/env documentation; project naming is Mornye rather than GMusic |
| [`../../Backend/Gdrive_backend/src/server.js`](../../Backend/Gdrive_backend/src/server.js) | Express configuration, auth and owner-scoped Drive/catalog routes, ticket signing, callbacks, safe error responses, local server |
| [`../../Backend/Gdrive_backend/src/drive_connections.js`](../../Backend/Gdrive_backend/src/drive_connections.js), [`../../Backend/Gdrive_backend/src/token_crypto.js`](../../Backend/Gdrive_backend/src/token_crypto.js) | Per-user PKCE OAuth lifecycle, encrypted token/verifier persistence, disconnect/revocation |
| [`../../Backend/Gdrive_backend/src/auth.js`](../../Backend/Gdrive_backend/src/auth.js) | Register/login, session token hash/renewal, authentication middleware, favorites/recent/playlist routes |
| [`../../Backend/Gdrive_backend/src/db.js`](../../Backend/Gdrive_backend/src/db.js) | Optional Mongo connection, owner-aware indexes, OAuth state/connection indexes |
| [`../../Backend/Gdrive_backend/src/drive.js`](../../Backend/Gdrive_backend/src/drive.js) | Credential loading, legacy shared token persistence, injectable Drive sessions, file listing/change tokens, stream/range and embedded-art parsers |
| [`../../Backend/Gdrive_backend/src/catalog.js`](../../Backend/Gdrive_backend/src/catalog.js) | Audio-file detection, metadata normalization, owner-filtered track/artist/album/genre/search queries and pagination |
| [`../../Backend/Gdrive_backend/src/indexer.js`](../../Backend/Gdrive_backend/src/indexer.js) | Owner-scoped resumable full scans/change cursors, bounded metadata extraction, retry of partial metadata and status |
| [`../../Backend/Gdrive_backend/api/index.js`](../../Backend/Gdrive_backend/api/index.js), [`../../Backend/Gdrive_backend/vercel.json`](../../Backend/Gdrive_backend/vercel.json) | Vercel Express entry/rewrite and 60-second function limit |
| [`../../Backend/Gdrive_backend/test/server.test.js`](../../Backend/Gdrive_backend/test/server.test.js), [`../../Backend/Gdrive_backend/test/drive_connections.test.js`](../../Backend/Gdrive_backend/test/drive_connections.test.js), [`../../Backend/Gdrive_backend/test/catalog.test.js`](../../Backend/Gdrive_backend/test/catalog.test.js), [`../../Backend/Gdrive_backend/test/indexer.test.js`](../../Backend/Gdrive_backend/test/indexer.test.js) | Twelve HTTP, OAuth/encryption/PKCE, catalog, parser and fake-store indexer tests; no MongoDB/real Drive connection |
| [`../../Backend/Gdrive_backend/scripts/check_drive.js`](../../Backend/Gdrive_backend/scripts/check_drive.js) | Local bridge health/status and track listing inspection; may print ticket URLs |
| [`../../Backend/Gdrive_backend/scripts/inspect_atlas.js`](../../Backend/Gdrive_backend/scripts/inspect_atlas.js) | Lists Atlas collections/count/sample user document; potentially sensitive output |
| [`../../Backend/Gdrive_backend/scripts/play_one_drive_track.js`](../../Backend/Gdrive_backend/scripts/play_one_drive_track.js), [`../../Backend/Gdrive_backend/scripts/probe_stream.js`](../../Backend/Gdrive_backend/scripts/probe_stream.js), [`../../Backend/Gdrive_backend/scripts/test_authenticated_stream.js`](../../Backend/Gdrive_backend/scripts/test_authenticated_stream.js) | Manual live Drive stream/playback probes |
| [`../../Backend/Gdrive_backend/scripts/reset_sessions.js`](../../Backend/Gdrive_backend/scripts/reset_sessions.js) | Destructive session cleanup plus user-shape inspection |
| [`../../Backend/Gdrive_backend/scripts/seed_phone_session.js`](../../Backend/Gdrive_backend/scripts/seed_phone_session.js) | Explicit-env-only test helper that creates a session without deleting prior sessions; writes output only to an explicit path |
| [`../../Backend/Gdrive_backend/scripts/setup.js`](../../Backend/Gdrive_backend/scripts/setup.js) | Local configuration bootstrap; creates `.env` when absent |
| [`../../Backend/Gdrive_backend/scripts/try_mongo.js`](../../Backend/Gdrive_backend/scripts/try_mongo.js) | Read-only Atlas connection probe requiring `MONGO_URI` |
| [`../../Backend/Gdrive_backend/.gitignore`](../../Backend/Gdrive_backend/.gitignore) | Excludes `.env`, OAuth credentials, Drive token, logs, Vercel state, and `node_modules` |
| Local [`.env`](../../Backend/Gdrive_backend/.env), [`credentials.json`](../../Backend/Gdrive_backend/credentials.json), [`data/token.json`](../../Backend/Gdrive_backend/data/token.json) | Present but ignored/untracked in this checkout; values deliberately not read |

The backend Git checkout was clean during the initial audit; implementation changes since then are uncommitted. The frontend workspace is not recognized as a Git repository in the provided environment.

## Validation performed

| Command | Result | Scope limitation |
|---|---|---|
| `flutter test` | **Passed: 20 tests** | Unit tests only; includes OAuth URL validation, account-scoped favorites, pending favorite sync, and transient/expired session restore; no widget/integration/device playback |
| `flutter analyze` | **10 info-level diagnostics; nonzero exit** | No errors or warnings; remaining diagnostics are deprecations, existing async-context/style infos |
| `npm test` from `D:\Backend\Gdrive_backend` | **Passed: 13 tests** | Shared-default OAuth, optional PKCE/encryption/replay, owner isolation, revocation failure, catalog and fake-store indexing/sync; no real database/Drive |

No live database/Drive was queried, no operational script was run, and no release build or physical-device validation was performed. The backend HTTP test launches an isolated local process with dummy OAuth configuration.

## Preservation constraints

- Retain the single existing Express service and auth/session model; use one common Drive and MongoDB deployment by default, with account-scoped user data. Per-user Drive is optional.
- Preserve `Users`, `sessions`, `favorites`, `recent_plays`, and `playlists` collection conventions and the existing hashed-session behavior.
- Keep Google OAuth credentials and token material on the backend. Never move them into Flutter or build-time defines.
- Preserve existing route and response compatibility while adding versioned routes. Existing playlist update is `PUT`, not the target-spec `PATCH`.
- Continue using the existing Riverpod/audio_service/just_audio foundation unless a tested replacement is justified; capture baseline behavior before changing queue semantics.
- Keep original Drive files read-only; user favorites/playlists/downloads must never mutate or delete the Drive source.

## Exact proposed implementation sequence

The sequence follows Part 28, with an explicit security gate before feature work. Each phase should be completed and tested vertically; do not create a set of disconnected screens.

0. **Close exposure and establish a baseline (pre-Phase 1 gate).** Rotate any credentials exposed in tracked helper scripts; replace literals with required environment inputs, make inspection output redacted, and isolate destructive tooling. Namespace local user data, define favorite conflict/retry semantics, and add regression tests before refactoring. Verify Android release network permissions/signing config.
1. **Phase 1 — Foundation and stability.** Preserve and test auth/session contracts; change session restoration to distinguish 401/expired from network errors; add secure device token storage and account-scoped local persistence; centralize HTTP timeout/error handling and a durable pending sync queue; fix queue ordering and position updates; publish audio_service playback state; verify navigation and current behavior.
2. **Phase 2 — Drive indexing and metadata.** Use the common backend Drive by default and share its index/catalog across accounts while keeping user-owned records separated. Keep encrypted-token PKCE OAuth and owner-scoped indexes only for optional per-user deployments. Validate indexing, metadata, change sync, migration/index behavior, and Google callback configuration against test services.
3. **Phase 3 — Catalog and discovery UI.** Build indexed catalog APIs, search/relevance/pagination, then Home/Search/Explore and track/artist/album detail surfaces backed only by the user's actual Drive collection. Add empty/loading/error states and response/cache tests.
4. **Phase 4 — Playback engine.** Complete one central handler/controller, queue/history/context/autoplay model, mini/full player, deterministic shuffle/repeat/previous-next, seeking/range recovery, media-session state, background controls, and queue persistence. Validate on Android hardware before claiming background playback.
5. **Phase 5 — Personal library.** Complete account-scoped favorites and retry sync first; add saved albums/followed artists, playlists with ownership/version/order semantics, user library, real listening-event history, preferences, and the corresponding Flutter features.
6. **Phase 6 — Downloads and offline.** Implement authenticated downloads with temp files/integrity checks, resumable task state, permanent-download versus cache separation, local catalog/offline playback, storage accounting, and conflict recovery.
7. **Phase 7 — Advanced audio.** Add provider-independent lyrics only from authorized/embedded sources; then sleep timer and only the equalizer/crossfade/gapless/normalization controls supported by the actual engine/platform.
8. **Phase 8 — Recommendations.** Build recommendations/radio from indexed user-owned Drive content and real listening signals; include feedback and avoid fabricated/trending external catalog data.
9. **Phase 9 — Statistics and personalization.** Define play-count thresholds; build real aggregations, trends, filters, and yearly recap from listening events without inventing historical records.
10. **Phase 10 — Security and production hardening.** Review auth/ownership, input validation/rate limits, tickets/ranges/stream disconnects, secrets/logging, Mongo indexes/query plans, large catalogs, offline/network failure, release configuration, monitoring, and regression/performance. Only then mark release readiness.

**Target assumption:** Android is the first device-validation target because the current host and background media-service declaration are Android-specific. Web and Windows remain supported where current app behavior permits; iOS requires a separate explicit platform setup and validation.
