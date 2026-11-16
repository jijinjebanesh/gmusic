# GMusic implementation checklist

Audit baseline: 2026-11-11. This checklist reflects the code inspected in the
Flutter workspace and `D:\Backend\Gdrive_backend`; “partial” means a real
workflow exists but does not meet the full request.

| Area | Audit status | Evidence / remaining work |
|---|---|---|
| UI/UX | Partial | Home now uses quick access/recent rows and a six-track preview; the full catalog is a separate searchable, paged `CatalogScreen`. Library links to that screen. Profile actions lead to real screens; green/charcoal navigation is consistent. Remaining pages still need a full reference-by-reference pass. |
| Authentication | Partial | Register/login/logout, persistent session and validation are implemented. No forgot/reset password, profile image, account deletion or privacy workflow. |
| Home | Partial | Loads the Drive catalog, recently played items, favorites, sync progress, pull-to-refresh and error/empty states. No personalized recommendations, popular artists, release collections or backend-driven featured playlists. |
| Search | Partial | Debounced server-side song search and artist/album/genre browse pages. Recent searches now load, record, remove, and clear through per-user persistent endpoints. Trending, suggestions, multi-category results and filters remain absent. |
| Artists | Partial | Artist detail lists catalog tracks and now supports persistent follow/unfollow. Backend exposes artist album aggregates, but the detail screen does not yet render full discography/recommendations. |
| Albums | Partial | Album detail lists ordered catalog tracks and now supports persistent save/unsave. Download and rich artwork metadata remain absent. |
| Playlists | Partial | Flutter supports list/create, edit name and description, delete, add/remove tracks, play and reorder. Backend persists ordered IDs and description with validation. Artwork is unsupported because the service has no user image storage/upload path; public/private state is also absent. Atlas-backed restart persistence still requires verification. |
| Library | Partial | Persistent favorites, recent plays, followed artists, saved albums, playlists and local downloads. Saved artists/albums, playlists and downloads have library destinations. Listening statistics and robust library sorting/filtering remain absent. |
| Player | Partial | `just_audio` + `audio_service` use real Drive stream-ticket URLs. A physical Android 13 test confirmed playback, continued progress after Home, the OS media notification, and media-key pause/play. Queue order/index/modes/position restore without autoplay. Lock-screen presentation, focus interruptions and headset/Bluetooth removal remain unverified. |
| Queue | Partial | Audio-service queue supports play next/add last, remove, reorder, clear and local persistence. Queue metadata serialization is covered by a round-trip test; actual plugin restore and device controls still need runtime verification. |
| Lyrics | Not implemented | No lyrics provider, API or screen. |
| Downloads/offline | Partial | Native/desktop builds stream songs into app-private per-account storage, persist metadata, show progress, cancel/retry/remove, detect missing files, and play local files. Pause/resume uses retained partial files and Range requests; pending active-track metadata restores after restart. OS-managed background transfer and future-queue recovery remain absent. |
| Audio settings | Partial | Theme preference exists; volume is supported by audio engine. No quality, equalizer, crossfade, normalization, autoplay or cache controls. |
| History | Partial | Backend persists bounded recently played tracks; no listening duration/statistics or album history. |
| Profile | Partial | Account identity, Drive connection and logout are available. No editable profile/preferences or account deletion. |
| Backend | Partial | Authenticated APIs cover playlists, search history, followed artists, saved albums and recent tracks with per-user scoping. Startup fails closed when Mongo is required but absent or when a configured connection fails. `/health` reports database mode. Lyrics/downloads/preferences/statistics APIs remain absent. |
| Google Drive | Implemented baseline | Read-only Drive auth, bounded metadata indexing, incremental sync, normalized catalog, tickets and artwork routes exist. Downloads reuse ticketed reads without changing the `drive.readonly` authorization. No upload endpoints by design. |
| Integration | Partial | Typed client connects account-backed playlists, search history, followed artists and saved albums. A physical app session restored and displayed recent history after restart. Dedicated authenticated writes and second-user isolation remain unverified. |
| Verification | Partial | Flutter suite covers API contracts, resumable downloads, metadata persistence, account separation, track serialization and queue restore; Node covers backend behavior and required-Mongo startup. Web release and Android debug builds pass; `flutter analyze` is clean. Physical Android playback/background/notification/media-key checks passed. Atlas is configured in backend `.env`; a device session loaded recent history after app restart. Full per-user mutation and isolation journeys remain. |

## Work performed

- Updated the shared dark theme to use charcoal surfaces and a single green
  playback accent aligned with the supplied reference.
- Extended backend integration test startup polling after the initial full run
  exposed an intermittent five-second health-check timeout.
- Added authenticated, user-scoped search-history, followed-artist, and
  saved-album endpoints with compound unique indexes and bounded search history.
- Extended playlists with descriptions, input bounds, deduplicated ordered track
  IDs, and invalid-ID handling.
- Added Flutter playlist management (create, edit, delete, add, remove, reorder,
  play), account-backed search history controls, follow/save actions, and a
  saved-music library screen.
- Added local queue/index/shuffle/repeat restoration, without autoplay, to the
  existing audio-service handler; queue metadata keeps the current audio engine.
- Added per-account native download storage, progress/cancel/retry/remove,
  download UI and local-file playback. Song, album and playlist download entry
  points use the existing read-only Drive stream tickets.
- Added download tests for temporary-file writes, metadata restoration,
  duplicate suppression and account isolation, plus a queue restore test that
  confirms the app does not autoplay.
- Verification run: `flutter test` passed (29 tests); `npm test` passed (14 tests). Web release and Android debug builds passed. `flutter analyze` is clean.

## Known external constraints

- The backend's Google OAuth scope is read-only. Uploads or Drive file deletion
  cannot be added without changing that security and authorization design.
- Atlas, Google Drive credentials and physical Android/iOS runtime access are
  environment-dependent; tests that need them must be reported separately.
- The backend `.env` contains `MONGO_URI`, and the live bridge reports `authMode=user_login`; no credential values are recorded here.

## Remaining implementation work

- Verify account-owned MongoDB mutations and restoration against the configured Atlas; implement playlist artwork only after adding a supported storage path, and finish artist discography presentation.
- Continue queue/lock-screen, focus/interruption, headset/Bluetooth and offline playback verification on physical mobile devices.
- Phase 3 remains partial: pause/resume and partial Range recovery are implemented and automated-tested. OS-managed background transfer, future-queue recovery, storage usage controls, and physical offline playback remain.
- Phase 4 lyrics, synchronized lyric display, quality/equalizer/crossfade and
  cache settings have not been implemented. No lyrics data provider is
  configured, and the current player exposes no equalizer or crossfade API.
- Phase 5 listening duration/statistics, recommendations, and editable user
  profile/preferences remain outstanding.
- Then complete full end-to-end journeys against a configured backend and
  mobile runtimes, including offline and expired-session cases.

## Completion sprint audit — 2026-11-12

The matrix below supersedes broad status labels above for the requested completion sprint. “Verified” means only the specific automated test, build or physical check listed here.

| Requested feature | Classification | Evidence / remaining work |
|---|---|---|
| Android background playback and media notification/lock-screen transport | Implemented but not fully verified | The physical Android 13 device continued playback after Home; the OS posted GMusic media transport actions. APK/service registration and manifest permissions are in place. Lock-screen presentation still needs direct verification. |
| Audio focus, interruptions, headphone/Bluetooth disconnect pause | Implemented but not fully verified | Android/iOS `audio_session` music configuration handles pause/duck events and becoming-noisy events. Other platforms are guarded; physical call/navigation/focus/headset tests remain. |
| Playback recovery | Partial | Queue, index, shuffle, repeat, and current position are persisted; restored queue does not autoplay. Automated test verifies queue and no-autoplay. Source reload/seek recovery and crash recovery require device/runtime verification. |
| Device-level player verification | Partially implemented | Physical Redmi M2101K6P / Android 13: streaming continued after Home; `dumpsys media_session` showed increasing position; Android posted GMusic transport actions; media pause/play keys changed session state. Lock-screen, focus/interruption, physical headset/Bluetooth and offline playback remain. |
| Background download transfers | Missing | Current HTTP streaming runs in the app process; no OS-managed transfer worker/service is configured. |
| Download pause/resume | Implemented but not fully verified | Active transfers can pause; temporary files are retained and resume with an HTTP Range request. The controller test verifies a persisted partial file resumes at the saved byte offset. |
| Persistent download queue | Partially implemented | `downloadAll` processes sequentially. The active transfer is persisted for recovery, but future queued tracks are not restored after process termination. |
| Download recovery after termination | Implemented but not fully verified | Active track metadata is persisted and an interrupted partial transfer is surfaced as paused after restart. The range-resume workflow is automated-tested; process-kill and fresh-ticket behavior are not device-tested. |
| Offline playback | Implemented but not fully verified | Completed files use local `AudioSource.file`; download tests verify file and metadata persistence. Airplane-mode playback was not tested on a device. |
| Download storage management | Partial | Per-account app-private storage, file verification and per-item removal exist. No storage usage summary, bulk clear, or quota policy. |
| Lyrics provider, timed lyrics, sync/highlighting/autoscroll | Missing | No provider or lyric screen is configured. |
| Equalizer, quality selector, crossfade/gapless, normalization, cache controls | Missing | No processing/equalizer or cache configuration is wired into the audio engine. Volume control exists but has no dedicated automated playback test. |
| Listening history | Implemented but not fully verified | Recent tracks are persisted by the backend API; Atlas-backed durability is not verified. |
| Listening duration, top tracks/artists, statistics | Missing | No duration aggregation or statistics screens/API. |
| Personalized recommendations | Missing | Home is not personalized from listening signals. |
| Recently played albums and tracks | Partial | Recent tracks exist; recently played albums are absent. |
| Profile editing and image | Missing | Identity display and logout exist; no edit or image upload/storage path. |
| Account settings/privacy controls | Partial | Login/logout and Drive connection controls exist; account deletion, privacy controls, and recovery flows are absent. |
| Persistent playback preferences | Partial | Queue/order/repeat/shuffle/position and local theme preference persist; no broad audio preference model. |
| Playlist artwork | Missing | Backend/user image storage path is absent. |
| Artist discography and complete artist/album details | Partial | Album aggregates and detail track lists exist; full artist discography presentation and recommendations are absent. |
| Redesigned player, queue, lyrics, downloads, stats, profile screens | Partial | Existing screens and charcoal/green shared styling remain; the requested screen-by-screen visual completeness and missing screens/features are not done. |
| Atlas startup/configuration safety | Implemented but not fully verified | `REQUIRE_MONGO=true` (and Vercel) fail closed when `MONGO_URI` is missing; configured connection failures abort startup rather than downgrade. The backend environment contains a URI and the live bridge reports user-login mode. The running service was not restarted during this session; full mutation/isolation tests remain. |

### Sprint changes and verification

- Added direct `audio_session` integration, audio-focus interruption handling,
  headset-removal pause, and periodic/immediate playback-position persistence.
- Added a separate full-catalog screen and updated Home, Library and Profile to
  follow the supplied Spotify-style charcoal/green, artwork-led reference.\n- Added resumable per-account partial downloads using HTTP Range, pause/resume
  controls, and persisted active-transfer metadata for recovery after restart.
- Added Android foreground media service permissions for foreground service,
  media playback and wake lock.
- Replaced deprecated appearance radio controls with `RadioGroup` and removed
  analyzer context warnings.
- Made a configured-but-unavailable MongoDB connection fail startup; added an
  explicit production/required-database startup check and database mode in
  `/health`. Local token-only mode remains explicit when Atlas is omitted.
- Flutter: `flutter test` passed (29 tests); `flutter analyze` passed with no
  issues; Android debug APK and Web release builds passed.
- Backend: `npm test` passed (14 tests), including required-Mongo startup
  validation. One earlier full test run had a transient health startup timeout;
  isolated and full reruns passed.
- Physical checks confirmed playback, background continuation, notification registration and media-key control. No physical interruption, headset/Bluetooth, lock-screen UI or offline download test is claimed.

### Exact remaining work

1. Continue physical verification with lock-screen UI, audio focus, headset/Bluetooth removal, and local playback with network disabled; fix and retest issues found.
2. Add an OS-managed background download implementation, persist the full
   sequential queue across process termination, and add storage usage controls.
3. Select and integrate a real timestamped lyrics source; build synchronized
   lyrics UI and test against playback positions.
4. Add supported audio processing/settings (quality where source permits,
   equalizer, crossfade/gapless, normalization) and cache controls.
5. Add event aggregation for duration/top tracks/artists, recently played
   albums, and recommendation ranking with backend persistence.
6. Add profile editing/image storage and account/privacy workflows; finish
   playlist artwork and complete artist discography/detail UI.
7. Run authenticated persistence, isolation, restart, logout/re-login, playlist/history/preference workflows against configured Atlas; add integration coverage using a disposable test database.
