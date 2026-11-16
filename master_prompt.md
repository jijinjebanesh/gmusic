# MASTER IMPLEMENTATION PROMPT — GMUSIC
## Complete Google Drive-Powered Music Player Transformation

**ROLE:** Senior Flutter Engineer, Node.js Backend Engineer, Database Architect, Audio Systems Engineer, and Product UI/UX Engineer.

**MISSION:** Inspect, improve, and complete the existing GMusic application into a polished, production-quality music player with the functionality and user experience of a modern commercial music application, while retaining Google Drive as its underlying music storage and streaming source.

You are expected to work directly inside the existing repository, understand its current implementation, and implement the required functionality. This is an engineering execution task, not a request to generate a proposal or an illustrative UI prototype.

---

# PART 1 — UNDERSTAND THE EXISTING PRODUCT

## 1.1 What GMusic currently is

GMusic consists of two primary components:

**1. Flutter mobile application**

The mobile app allows users to:

- Register and sign in to a GMusic account.
- Browse audio files available through Google Drive.
- Search tracks.
- Play music.
- Manage favorites.
- Access recently played songs.
- Use background playback.
- Control playback using a persistent mini-player.

**2. Node.js backend**

The backend:

- Handles GMusic authentication.
- Maintains user sessions.
- Connects to Google Drive.
- Retrieves music files and metadata.
- Provides music information to the Flutter application.
- Streams audio to the Flutter application.
- Stores user-specific information.

Google Drive credentials must remain on the backend. Never expose Drive service credentials, private keys, refresh tokens, or administrative credentials to the Flutter application.

Google Drive remains the source of truth for the original audio files.

The application should not become a conventional commercial music-streaming service with a newly created audio catalog.

Instead, GMusic should become an advanced personal music platform built around the user's existing Google Drive music collection.

## 1.2 Existing functionality must be preserved

Before making any changes, identify and verify the implementation of:

- Registration.
- Login.
- Session persistence.
- Authentication middleware.
- User-specific favorites.
- Recently played history.
- Google Drive authentication.
- Drive file listing.
- Track search.
- Audio streaming.
- Background playback.
- Mini-player.
- Audio notification controls.
- Existing API contracts.
- Existing database structure.

Do not replace working features simply because you prefer a different implementation.

Preserve the existing authentication mechanism, token handling, database conventions and API response formats unless you identify a concrete defect that requires modification.

For example, if the existing backend already hashes session tokens before storing them, preserve that security behavior.

Do not introduce another parallel authentication system.

## 1.3 Target architecture

The architecture should evolve into:

```text
GMUSIC
│
├── FLUTTER MOBILE APPLICATION
│   │
│   ├── Application Shell
│   ├── Home
│   ├── Search
│   ├── Explore
│   ├── Your Library
│   ├── Drive Music Library
│   ├── Artists
│   ├── Albums
│   ├── Playlists
│   ├── Favorites
│   ├── Recently Played
│   ├── Downloads
│   ├── Now Playing
│   ├── Queue
│   ├── Lyrics
│   ├── Audio Settings
│   ├── Music Statistics
│   └── Account Settings
│
├── NODE.JS BACKEND
│   │
│   ├── Authentication
│   ├── Session Management
│   ├── Google Drive Integration
│   ├── Drive Indexing Engine
│   ├── Music Metadata Engine
│   ├── Catalog Service
│   ├── Search Service
│   ├── Streaming Engine
│   ├── Playlist Service
│   ├── Favorites Service
│   ├── Listening History
│   ├── Queue Persistence
│   ├── Recommendations
│   ├── Download Authorization
│   ├── User Preferences
│   └── Analytics
│
├── MONGODB
│   ├── Users
│   ├── Sessions
│   ├── Drive File Index
│   ├── Track Metadata
│   ├── Playlists
│   ├── Playlist Items
│   ├── Favorites
│   ├── Listening Events
│   ├── Recent History
│   ├── Preferences
│   └── Synchronization Data
│
└── GOOGLE DRIVE
    └── Original Audio Files
```

Adapt this structure to the existing repository. It is an architectural target, not an instruction to rename every existing file.

---

# PART 2 — EXECUTION RULES

These rules apply throughout the entire implementation.

## 2.1 Inspect before changing

Begin by examining the actual repository.

Inspect:

- Flutter project structure.
- Dart files.
- Existing page implementations.
- State-management implementation.
- Navigation system.
- Audio-player package and initialization.
- Existing audio service.
- Android manifest.
- iOS configuration, if present.
- Backend folder structure.
- API routes.
- Authentication middleware.
- Google Drive integration.
- MongoDB models.
- Existing indexes.
- Environment variables.
- Existing tests.
- Build configuration.

Produce a concise internal implementation map.

Do not assume that features are absent because their screens are not immediately visible.

Search for existing implementations before adding new ones.

## 2.2 Preserve working functionality

Use existing implementations wherever possible.

When replacing a component:

1. Understand what currently depends on it.
2. Identify existing API contracts.
3. Identify database dependencies.
4. Preserve current behavior.
5. Add compatibility or migrations where required.
6. Run regression tests.

Do not delete existing working features to simplify the implementation.

## 2.3 Implement real functionality

Every button, interaction, menu, setting and page must perform a meaningful operation.

Do not create:

- Decorative buttons.
- Fake playback controls.
- Hardcoded music recommendations.
- Static statistics presented as real data.
- Fake download progress.
- Placeholder API implementations presented as finished features.
- UI toggles that do not change actual application behavior.

Development mocks are acceptable only when clearly isolated behind development configuration.

## 2.4 Work incrementally

Complete features vertically.

For example, a Playlist feature is not complete until:

- Playlist UI exists.
- Playlist state exists.
- API operations work.
- Backend authorization works.
- Database persistence works.
- Reordering works.
- Error handling works.
- Offline behavior is defined.
- Tests pass.

Do not implement every page visually before connecting the application.

## 2.5 Do not overengineer

Use clean modular architecture, but avoid unnecessary abstractions.

Do not introduce Redis, Elasticsearch, Kafka, Kubernetes, microservices or additional databases unless the actual project requirements justify them.

MongoDB and the existing Node.js application should remain the primary backend foundation.

Do not change the backend language or replace Flutter.

---

# PART 3 — COMPLETE PRODUCT FEATURES TO IMPLEMENT

The following modules define the target functionality.

## 3.1 Application shell and navigation

Implement a persistent application shell.

Primary navigation:

1. Home.
2. Search.
3. Explore.
4. Your Library.

Provide a persistent mini-player above the bottom navigation whenever a track is active.

The application should also provide access to:

- Profile.
- Notifications, if supported.
- Settings.
- Device/output controls.

Requirements:

- Preserve scroll positions when switching tabs.
- Preserve page state.
- Preserve search queries.
- Preserve playback state.
- Avoid recreating the audio player on every page navigation.
- Support deep links to albums, artists and playlists where appropriate.
- Support Android back navigation consistently.
- Provide appropriate loading and error states.

Use a consistent routing strategy.

Do not implement independent navigation logic inside every feature.

## 3.2 Home

Create a complete personalized Home page.

### Header

Display:

- Greeting.
- User avatar.
- Profile shortcut.
- Notifications shortcut, if implemented.
- Current listening context where appropriate.

### Quick access

Display:

- Liked Songs.
- Recently Played.
- Your Playlists.
- Recently Added.
- Last Played.
- Most Played.
- Downloads.

### Main sections

Implement the following sections using actual collection metadata and user activity:

1. Continue Listening.
2. Recently Played.
3. Made for You.
4. Recently Added.
5. Your Heavy Rotation.
6. Most Played.
7. Your Favorite Artists.
8. Your Favorite Albums.
9. Recently Discovered.
10. Quick Mixes.
11. Recommended Albums.
12. Recommended Songs.
13. Similar to Your Favorites.
14. Genre Collections.
15. Mood Collections.
16. Random Discovery.
17. Recently Updated Playlists.

Not all sections have to appear for every user.

Generate sections based on the size and quality of available data.

### Home behavior

- Pull-to-refresh.
- Lazy-load content.
- Cache successful results.
- Use skeleton loading.
- Avoid repeated tracks across adjacent recommendation sections.
- Update sections when the user's library changes.
- Handle empty collections.
- Handle unavailable or deleted Drive files.

A new user with little listening history should still see useful collection-based sections.

Do not invent trending music from outside the user's actual collection.

## 3.3 Search

Implement a complete global music search.

Search should operate against the backend's indexed music metadata rather than repeatedly scanning Google Drive for every keystroke.

### Search categories

- All.
- Songs.
- Artists.
- Albums.
- Playlists.
- Folders, where useful.

### Searchable fields

Search:

- Song title.
- Artist.
- Featured artist.
- Album.
- Album artist.
- Genre.
- Release year.
- Filename.
- Drive folder name.
- Playlist name.

### Search features

- Debounced queries.
- Search suggestions.
- Recent searches.
- Search history.
- Clear history.
- Search result pagination.
- Search result sorting.
- Case-insensitive matching.
- Partial matches.
- Multiple artist matching.
- Special-character handling.
- Empty query handling.
- No-results state.
- Network failure handling.

### Search relevance

Use a reasonable relevance hierarchy:

1. Exact track title.
2. Exact artist.
3. Exact album.
4. Prefix match.
5. Word match.
6. Partial match.
7. Other metadata match.

Do not return hundreds of weak results before highly relevant matches.

### Local search integration

If the application already stores cached music metadata on the device, merge local searchable results with server results where appropriate.

Avoid duplicates.

## 3.4 Explore

Build a discovery page based entirely on the indexed Drive collection.

### Genre collections

Extract genres from metadata and create collections.

Examples:

- Pop.
- Rock.
- Electronic.
- Hip-hop.
- Classical.
- Jazz.
- Indie.
- R&B.
- Ambient.
- Regional music.

Only display categories that actually have music.

### Mood collections

Where possible, support curated or manually configured mood categories.

Examples:

- Chill.
- Energetic.
- Workout.
- Relax.
- Focus.
- Sleep.
- Party.
- Romantic.
- Nostalgic.

Mood classification can be based on user-defined tags or an optional metadata-classification service.

Do not make unsupported claims about the mood of a song.

### Explore collections

Include:

- All Artists.
- All Albums.
- Recently Added.
- Random Selection.
- Popular Songs.
- Genre-Based Mixes.
- Similar Artists.
- Recently Updated Music.

## 3.5 Artist pages

Build artist pages from the indexed music collection.

Display:

- Artist artwork.
- Artist name.
- Number of tracks.
- Albums.
- Singles.
- Total duration.
- Popular songs.
- Discography.
- Appears On, if identifiable.

Actions:

- Play Artist.
- Shuffle Artist.
- Add Artist to Favorites.
- Start Artist Radio.
- View Albums.
- Share Artist collection.

Do not create duplicate artist pages because of different capitalization or spelling when they can be normalized reliably.

Preserve aliases and featured-artist distinctions.

## 3.6 Album pages

Display:

- Artwork.
- Album title.
- Artist.
- Album artist.
- Release year.
- Track count.
- Total duration.
- Genre.
- Tracklist.
- Disc information.

Actions:

- Play Album.
- Shuffle Album.
- Add to Library.
- Add All to Playlist.
- Download Album.
- Share.
- Open Artist.

Correctly support:

- Multi-disc albums.
- Compilation albums.
- Various Artists.
- Missing track numbers.
- Duplicate album titles.
- Remastered editions.
- Different audio versions.

Sort tracks by disc number and track number.

Do not alphabetically sort an album unless the user requests that sorting mode.

---

# PART 4 — GOOGLE DRIVE INDEXING AND MUSIC METADATA ENGINE

This is one of the most important backend improvements.

The current application must not repeatedly fetch and process the entire Google Drive collection whenever a user opens the application.

Build a persistent Drive indexing system.

## 4.1 Drive indexing service

Create a dedicated service responsible for maintaining a searchable index of music files.

The indexing pipeline should:

1. Authenticate using the existing backend Drive credentials.
2. Retrieve Drive files using pagination.
3. Identify supported audio files.
4. Collect relevant Drive metadata.
5. Match files using stable Google Drive file IDs.
6. Inspect audio metadata when needed.
7. Normalize metadata.
8. Persist indexed records.
9. Identify deleted files.
10. Identify modified files.
11. Update the index incrementally.

Support:

- Initial indexing.
- Manual full rescan.
- Incremental synchronization.
- Background scheduled synchronization, where the deployment supports it.
- Synchronization after Drive changes.
- Interrupted indexing recovery.
- Retry after failed indexing.

Never assume that one Drive API response contains the complete collection.

## 4.2 Drive file identification

Use the stable Google Drive file ID as the canonical identity of a music file.

Store useful metadata including:

- Drive file ID.
- Filename.
- MIME type.
- File extension.
- File size.
- Modified time.
- Created time.
- Checksum, when available.
- Parent folder IDs.
- Drive ownership or source context.
- Indexing status.
- Last indexed timestamp.

Do not use filenames as unique identifiers.

Two files may have identical filenames.

## 4.3 Identify supported audio files

Use MIME types and file extensions together.

At minimum, evaluate:

- MP3.
- FLAC.
- WAV.
- M4A.
- AAC.
- OGG.
- Opus.
- ALAC, where supported.

Handle unknown audio MIME types through cautious extension-based identification.

Do not index arbitrary document files as songs.

## 4.4 Extract audio metadata

Create a metadata extraction module.

Extract:

- Title.
- Artist.
- Album.
- Album Artist.
- Featured Artists.
- Composer.
- Genre.
- Release Year.
- Release Date.
- Track Number.
- Total Tracks.
- Disc Number.
- Total Discs.
- Duration.
- Bitrate, when available.
- Sample Rate.
- Bit Depth, when available.
- Embedded Artwork.

Support relevant metadata formats for MP3, FLAC, OGG and MP4-based audio.

### Metadata fallback rules

When tags are unavailable:

1. Use existing user corrections, if available.
2. Parse reasonable information from the filename.
3. Use parent folder names as weak fallback metadata.
4. Display an Unknown value where information is genuinely unavailable.

Never invent track titles, artists or album information.

Preserve the original filename and raw metadata alongside normalized metadata.

Allow metadata corrections to be stored separately from the original audio file.

Do not modify original Drive files automatically.

## 4.5 Embedded artwork

Artwork should be extracted and cached separately where possible.

Requirements:

- Support embedded artwork.
- Cache extracted artwork.
- Generate thumbnails.
- Avoid repeatedly downloading original audio files just to retrieve artwork.
- Avoid embedding very large artwork payloads in frequently queried MongoDB records.
- Store a reference to the cached artwork.
- Provide a fallback when artwork is missing.
- Detect artwork changes when the associated audio metadata changes.

If metadata extraction requires downloading part or all of a file, do it through a controlled processing pipeline.

Do not attempt unreliable partial metadata parsing and silently present corrupted results as valid metadata.

## 4.6 Incremental synchronization

Use the Google Drive changes mechanism where supported by the existing Drive integration.

Maintain the appropriate change token or page token.

The intended workflow:

```text
Drive Changes Detected
        |
        v
Read Change Page
        |
        v
Identify Changed Files
        |
        v
Identify Deleted Files
        |
        v
Update Only Affected Records
        |
        v
Re-extract Changed Metadata
        |
        v
Update Search Index
        |
        v
Persist New Sync Token
```

Do not perform a complete library rescan for every synchronization request.

Handle:

- Expired page tokens.
- Interrupted pagination.
- API rate limits.
- Transient connection failures.
- Files moved between folders.
- Files renamed.
- Files replaced.
- Trashed files.
- Permission changes.

If a change token expires, recover using a controlled full scan.

## 4.7 Scan status

Expose index state to the application.

Possible states:

- Not Started.
- Initializing.
- Scanning.
- Extracting Metadata.
- Updating Index.
- Completed.
- Partially Completed.
- Failed.
- Synchronizing.

Show meaningful progress where reliable progress information is available.

Do not report fabricated percentage completion.

---

# PART 5 — BACKEND MUSIC CATALOG

Create a catalog abstraction on top of Google Drive.

The rest of the application should communicate with catalog services rather than querying Google Drive directly.

## 5.1 Catalog services

Implement independently:

- Track Catalog.
- Artist Catalog.
- Album Catalog.
- Genre Catalog.
- Playlist Catalog.
- Music Search.
- Collection Statistics.

The catalog should build logical music entities from the underlying file collection.

## 5.2 Track identity

A remote track should be identified using its Drive file ID.

Keep application track metadata separate from the original Drive file metadata.

Do not rely on an unstable filename or array index as track identity.

## 5.3 Artist normalization

Normalize artist names carefully.

Handle:

- Uppercase/lowercase differences.
- Leading and trailing whitespace.
- Common punctuation differences.
- Featured artists.
- Collaborations.
- Multiple primary artists.

Do not incorrectly merge unrelated artists with similar names.

Where matching is uncertain, preserve separate records.

## 5.4 Album grouping

Group music by normalized album and album artist, using the best available metadata.

Handle identical album names by different artists.

Handle compilation albums.

Handle missing album metadata without placing every untagged song into one misleading album.

## 5.5 Catalog updates

When a Drive file changes:

- Update its track record.
- Update the associated album.
- Update relevant artist collections.
- Refresh artwork.
- Update search indexing.
- Invalidate stale cached Home sections.

When a Drive file disappears:

- Mark the associated track unavailable.
- Preserve references in user playlists and listening history.
- Display an unavailable-track state.
- Do not silently delete the user's playlist item or listening history.

---

# PART 6 — AUDIO STREAMING ENGINE

Playback quality and reliability are critical.

Improve the existing streaming implementation rather than creating a second unrelated audio pipeline.

## 6.1 Streaming architecture

```text
Flutter Player
      |
      v
GMusic Playback API
      |
      v
Authentication and Access Validation
      |
      v
Track Resolver
      |
      v
Google Drive Audio Stream
      |
      v
Backend Stream Adapter
      |
      v
Flutter Audio Engine
```

## 6.2 Streaming requirements

Implement or verify:

- Authenticated access.
- Audio MIME type handling.
- Correct content length when available.
- HTTP Range requests.
- Partial content responses.
- Seeking.
- Streaming without loading the full file into backend memory.
- Stream cancellation.
- Connection interruption handling.
- Retry where appropriate.
- Error propagation.

For byte-range requests, implement correct HTTP behavior including:

- `Accept-Ranges`.
- `Content-Range`.
- `Content-Length`, where known.
- Appropriate `206 Partial Content` responses.
- `416 Range Not Satisfiable` for invalid ranges.

Verify that the Google Drive upstream operation supports the required range behavior.

If it does not, implement a safe alternative rather than falsely advertising range support.

Never buffer large audio files entirely in Node.js memory.

Use streaming pipelines and handle client disconnects.

## 6.3 Authorization

Every playback request must validate:

- User authentication.
- Track availability.
- Resource permissions.
- Any existing catalog access rules.

Do not expose unrestricted Google Drive download URLs.

Do not expose backend service-account credentials.

Use authenticated server-mediated playback or short-lived authorized playback links according to the current deployment architecture.

## 6.4 Track source abstraction

In Flutter, provide a consistent track representation regardless of where the audio comes from.

The UI should not need to understand Google Drive API details.

The playback service should receive:

- Track metadata.
- Playback source resolver.
- Duration.
- Artwork.
- Source type.

Keep Drive-specific implementation outside the player UI.

## 6.5 Playback recovery

Handle:

- Missing Drive file.
- File deleted during playback.
- Expired authentication.
- Backend unavailable.
- Range request failure.
- Network interruption.
- Decoder error.
- Unsupported format.
- Empty stream.
- Invalid audio metadata.

Provide meaningful recovery and a way to skip a broken track.

---

# PART 7 — CENTRAL PLAYBACK SYSTEM

There must be one authoritative playback controller.

Do not create separate audio players in Home, Album, Playlist, Search or Artist pages.

## 7.1 Playback state

Define a clear playback state machine.

```text
Idle
  |
  v
Loading
  |
  v
Buffering
  |
  v
Playing <--------> Paused
  |
  v
Completed
  |
  v
Next Track

Any State
  |
  v
Error
  |
  v
Recovery / Skip / Stop
```

Expose state in a way that can be consumed by every page.

## 7.2 Playback controller operations

Implement:

- Play Track.
- Pause.
- Resume.
- Toggle Play/Pause.
- Next.
- Previous.
- Seek.
- Set Shuffle.
- Set Repeat.
- Set Volume/Gain, where supported.
- Play Queue.
- Play Album.
- Play Artist Collection.
- Play Playlist.
- Add to Queue.
- Play Next.
- Stop Playback.

All operations must update the same player state.

## 7.3 Mini-player

The mini-player should remain visible above the bottom navigation when appropriate.

Display:

- Artwork.
- Track title.
- Artist.
- Playback progress.
- Play/Pause.
- Like button.

Interactions:

- Tap to open Now Playing.
- Play/Pause immediately.
- Like/unlike.
- Expand through a smooth transition.
- Dismiss the visible mini-player without unexpectedly destroying the active audio session.

The mini-player must listen to the authoritative playback state.

## 7.4 Full player

Design a complete Now Playing screen.

### Header

- Minimize.
- Playback context.
- Audio output information.
- Overflow menu.

### Artwork

- High-quality album image.
- Consistent aspect ratio.
- Smooth artwork transition.
- Loading placeholder.
- Fallback image.

### Metadata

- Track title.
- Artist name.
- Album information.
- Favorite button.

### Timeline

- Seek slider.
- Current duration.
- Total duration.
- Buffered position when available.

### Controls

- Shuffle.
- Previous.
- Play/Pause.
- Next.
- Repeat.
- Queue.
- Lyrics.
- More options.

### More options

- Add to Playlist.
- Share.
- View Album.
- View Artist.
- Track Information.
- Audio Quality.
- Sleep Timer.

## 7.5 Playback behavior

Implement predictable previous/next behavior.

Previous:

- Restart current track when appropriate.
- Otherwise navigate to the previous track.

Next:

- Follow queue order.
- Respect shuffle.
- Respect repeat modes.
- Skip unavailable tracks when necessary.
- Continue with autoplay only when enabled.

Repeat:

- Off.
- All.
- One.

Shuffle must not produce repeated tracks prematurely.

When shuffle is disabled, restore predictable playback ordering.

## 7.6 Background playback

Verify and complete:

- Android background playback.
- Android media notification.
- Lock-screen controls.
- Bluetooth controls.
- Wired headphone controls.
- iOS background audio, if iOS is targeted.
- Audio focus.
- Audio interruptions.
- Headphone disconnection handling.
- Playback resumption.
- Process recreation recovery.

Audio playback must not depend on Flutter widget lifecycle.

Do not create a new audio engine whenever the current page changes.

## 7.7 Media session integration

The operating system's media session must always reflect:

- Current track.
- Artwork.
- Play/Pause state.
- Position.
- Duration.
- Previous/Next capabilities.

Notification controls and physical headphone controls must invoke the same central playback controller.

## 7.8 Queue persistence

Persist:

- Current track.
- Queue contents.
- Queue position.
- Shuffle mode.
- Repeat mode.
- Current track position.
- Playback context.

Restore the previous queue after application restart where possible.

Do not assume operating systems will always permit resuming an audio stream from exactly the previous position after a process kill.

---

# PART 8 — ADVANCED QUEUE MANAGEMENT

Create a dedicated Queue page.

## 8.1 Queue structure

Sections:

- Now Playing.
- Up Next.
- Optional Recommended Next.

Each entry should show:

- Artwork.
- Song title.
- Artist.
- Duration.
- Context menu.

## 8.2 Queue operations

Implement:

- Play Now.
- Play Next.
- Add to End.
- Remove.
- Reorder.
- Clear.
- Save as Playlist.
- View Album.
- View Artist.

## 8.3 Drag and drop

Users should be able to reorder upcoming songs using drag and drop.

Updates must be reflected immediately in:

- Queue UI.
- Playback controller.
- Persisted queue state.

## 8.4 Queue history

Maintain recently played queue entries.

Allow users to return to previously played tracks where the queue context permits it.

Do not confuse listening history with the active queue.

## 8.5 Playback context

Track where playback started.

Examples:

- Album.
- Artist.
- Playlist.
- Search result.
- Liked Songs.
- Recently Played.
- Explore collection.

Retain this context so that queue behavior and navigation remain sensible.

## 8.6 Autoplay

When the queue ends and autoplay is enabled:

- Find related tracks from the indexed collection.
- Prefer tracks matching the current listening context.
- Avoid recently played duplicates.
- Avoid tracks the user explicitly marked as unwanted.
- Append recommendations instead of suddenly replacing the entire queue.

Allow users to toggle autoplay.

---

# PART 9 — FAVORITES AND PERSONAL LIBRARY

Expand the existing favorites implementation into a complete music library.

## 9.1 Liked Songs

Features:

- Like.
- Unlike.
- Play All.
- Shuffle.
- Search within Liked Songs.
- Sort.
- Filter.
- Add Multiple to Playlist.
- Bulk Remove.
- Download where supported.

Use immediate UI updates with persistent server synchronization.

Do not lose favorites if the network request fails.

Use retryable synchronization.

## 9.2 Your Library

Include:

- Liked Songs.
- Playlists.
- Saved Albums.
- Followed Artists.
- Recently Played.
- Most Played.
- Downloads.
- Recently Added.
- User collections.

Implement library filtering:

- All.
- Playlists.
- Artists.
- Albums.
- Tracks.

Sorting:

- Recently Added.
- Recently Played.
- Alphabetical.
- Custom.

Allow pinned or frequently accessed collections if appropriate.

## 9.3 Saved albums

Support:

- Save Album.
- Remove Saved Album.
- Browse Saved Albums.
- Search Saved Albums.
- Play Album.
- Sort by Date Added.

Saved albums are user-level relationships and must not modify Drive files.

## 9.4 Followed artists

Support:

- Follow.
- Unfollow.
- Browse Followed Artists.
- View artist discography.
- View related releases.

Do not confuse following an artist with liking an individual song.

---

# PART 10 — PLAYLIST MANAGEMENT

Implement complete playlist functionality.

## 10.1 Playlist creation

Allow users to:

- Create Playlist.
- Name Playlist.
- Add Description.
- Select Cover Artwork.
- Add Songs.
- Reorder Songs.
- Delete Playlist.

Generate default covers when users do not provide artwork.

## 10.2 Playlist operations

Support:

- Add one song.
- Add multiple songs.
- Remove one song.
- Remove multiple songs.
- Move songs.
- Reorder.
- Duplicate Playlist.
- Rename.
- Edit Description.
- Change Cover.
- Delete.
- Search inside Playlist.
- Sort tracks.

## 10.3 Playlist model

A playlist should belong to a GMusic user.

A playlist item should reference the underlying Drive file ID or the application's canonical track ID.

Do not duplicate the complete track metadata inside every playlist item.

Retrieve canonical track metadata when rendering playlist contents.

## 10.4 Playlist behavior

Important rules:

- Removing a song from a playlist must not delete the original Drive file.
- Deleting a playlist must not delete Drive files.
- Removing a favorite must not remove the track from other playlists.
- Missing tracks should display as unavailable.
- Duplicate entries should be supported only if the product intentionally permits them.
- Track ordering must remain deterministic.

Use a stable position or ordering strategy.

For concurrent modifications, use playlist versions or revision checking.

## 10.5 Context menus

Provide a consistent track context menu everywhere:

- Play.
- Play Next.
- Add to Queue.
- Add to Playlist.
- Like/Unlike.
- View Album.
- View Artist.
- Track Information.
- Share, where supported.

The same menu behavior should be reused throughout the application.

---

# PART 11 — DOWNLOADS AND OFFLINE EXPERIENCE

Build an actual download manager.

Do not create a download screen that merely displays cached playback tracks.

## 11.1 Download types

Distinguish:

1. User-requested permanent offline copies of their Drive music.
2. Temporary streaming cache.
3. Artwork cache.

These must have separate lifecycle and deletion behavior.

## 11.2 Download manager functionality

Implement:

- Download Track.
- Download Album.
- Download Playlist.
- Pause.
- Resume.
- Cancel.
- Retry.
- Remove Download.
- Download Queue.
- Progress Tracking.
- Download Size.
- Storage Usage.
- Duplicate Detection.

## 11.3 Download integrity

Use temporary destination files.

After successful download:

- Validate the file.
- Verify size or checksum where available.
- Finalize the file.
- Persist the download record.

Do not leave corrupt partial files marked as downloaded.

## 11.4 Offline mode

When disconnected:

- Show downloaded tracks.
- Play available offline music.
- Show unavailable streaming-only tracks.
- Preserve playlists.
- Preserve favorites.
- Preserve queue data.
- Preserve listening events locally where appropriate.

Handle expired or changed Drive access without crashing.

## 11.5 Storage management

Provide settings:

- Total GMusic storage.
- Audio cache usage.
- Artwork cache usage.
- Downloaded music usage.
- Clear Temporary Cache.
- Remove Selected Downloads.
- Clear All Downloads.

Never delete a user's original Drive files through a cache-cleanup operation.

Never delete permanent user downloads when clearing temporary cache.

## 11.6 Background downloading

Implement background downloading where the target platforms and existing dependencies allow it.

Persist progress correctly.

Do not assume background tasks run indefinitely on mobile platforms.

Provide recovery when the operating system terminates a download.

---

# PART 12 — LYRICS SYSTEM

Implement a provider-independent lyrics feature.

## 12.1 Lyrics capabilities

Support:

- Static lyrics.
- Time-synchronized lyrics.
- Manual scrolling.
- Current-line highlighting.
- Smooth auto-scrolling.
- Full-screen lyrics.

## 12.2 Lyrics source

First inspect whether the existing music collection has:

- Embedded lyrics.
- `.lrc` sidecar files.
- Lyrics metadata.
- An existing authorized lyrics provider integration.

Use those sources where available.

Create a provider abstraction for future integrations.

Do not scrape websites without authorization.

Do not display fabricated lyrics.

## 12.3 Lyrics states

Support:

- Loading.
- Lyrics available.
- Lyrics unavailable.
- Unsupported track.
- Provider unavailable.
- Unsynchronized lyrics.
- Manual scrolling.

Keep playback running when opening and closing lyrics.

---

# PART 13 — AUDIO SETTINGS AND PLAYER ENHANCEMENTS

Create a dedicated settings area for audio.

## 13.1 Equalizer

Support:

- Enable/Disable.
- Presets.
- Custom presets.
- Frequency bands.
- Bass Boost.
- Balance.
- Virtualizer, where supported.

Presets:

- Flat.
- Pop.
- Rock.
- Jazz.
- Classical.
- Electronic.
- Vocal.
- Bass Boost.
- Treble Boost.
- Custom.

Use the capabilities of the actual audio engine.

If processing is not supported on a particular device, explain the limitation.

Do not build controls that do nothing.

## 13.2 Gapless playback

Support gapless playback where the decoder and audio engine permit it.

Test consecutive tracks from the same album.

## 13.3 Crossfade

Allow users to enable or disable crossfade and select its duration.

Ensure it does not break seeking, track completion or queue transitions.

## 13.4 Audio normalization

Where supported, normalize volume between tracks using available metadata or a properly implemented processing mechanism.

Do not arbitrarily modify source audio files.

## 13.5 Playback preferences

Settings should include:

- Autoplay.
- Shuffle.
- Repeat.
- Crossfade.
- Gapless.
- Audio normalization.
- Default output behavior.
- Playback resumption preferences.

## 13.6 Sleep timer

Support:

- 5 minutes.
- 10 minutes.
- 15 minutes.
- 30 minutes.
- 45 minutes.
- 60 minutes.
- End of Track.
- Custom Time.

At expiration:

- Stop playback.
- Preserve queue.
- Optionally fade out.
- Allow cancellation.

The timer must work when the application is in the background.

## 13.7 Track information

Show:

- Filename.
- Artist.
- Album.
- Drive file ID where appropriate for debugging, not necessarily regular UI.
- File size.
- File format.
- Duration.
- Bitrate.
- Sample rate.
- Bit depth where available.
- Source.
- Download status.

---

# PART 14 — PERSONALIZED DISCOVERY AND RECOMMENDATIONS

All recommendations should derive from the actual user's Google Drive music collection.

Do not introduce fake catalog content.

## 14.1 Listening signals

Collect useful signals:

- Track started.
- Track completed.
- Track skipped.
- Repeated listening.
- Listening duration.
- Favorite added.
- Favorite removed.
- Album saved.
- Artist followed.
- Playlist creation.
- Playlist additions.
- Recently played.
- Explicit recommendation feedback.

Distinguish between listening events and UI interactions.

Opening a track page does not mean listening to the track.

## 14.2 Recommendation engine

Start with understandable rule-based recommendations.

Use signals such as:

- Similar artist.
- Shared album.
- Shared genre.
- Frequently played artists.
- Repeatedly played songs.
- Recently added songs.
- User-created playlist patterns.
- Related metadata.

## 14.3 Recommendation features

Implement:

- Daily Mix.
- Similar Songs.
- Artist Radio.
- Album Radio.
- Recently Discovered.
- Your Heavy Rotation.
- Forgotten Favorites.
- Most Played.
- Random Discovery.
- Genre Mix.
- Mood Mix.

Not every section must be generated on a daily schedule.

Do not label something "Daily Mix" unless its contents are actually generated according to that behavior.

## 14.4 Recommendation feedback

Allow:

- More Like This.
- Less Like This.
- Hide Track.
- Not Interested.
- Remove from Recommendation.

Store feedback and incorporate it into future ranking.

## 14.5 Radio

Generate a continuous playback sequence from the available Drive collection.

Allow radio creation from:

- Track.
- Artist.
- Album.
- Genre.
- Playlist.

Avoid duplicates and excessive repetition.

Radio should work with actual playable Drive tracks.

---

# PART 15 — MUSIC STATISTICS AND HISTORY

## 15.1 Listening history

Preserve the existing recently played implementation and expand it.

Store:

- Track ID.
- User ID.
- Started time.
- Played duration.
- Completion state.
- Playback source.
- Device identifier, if available.

Handle repeated plays as separate listening events.

Maintain a convenient recent-history representation.

## 15.2 Listening statistics

Implement:

- Total listening time.
- Most Played Songs.
- Top Artists.
- Top Albums.
- Genre Distribution.
- Recently Discovered Songs.
- Listening Activity.
- Longest Sessions.
- Repeat Favorites.

Time filters:

- Last 7 Days.
- Last 30 Days.
- Last 6 Months.
- All Time.

## 15.3 Counting rules

Define meaningful listening thresholds.

For example:

- Count a play when a reasonable minimum duration or fraction of the song has been heard.
- Track skipped songs separately.
- Do not count repeated progress updates as repeated plays.
- Exclude invalid playback sessions.

Use consistent aggregation logic.

## 15.4 Yearly recap

Generate a yearly summary from actual listening events.

Include:

- Top Songs.
- Top Artists.
- Total Listening Time.
- Most Played Albums.
- Favorite Genres.
- New Artists Discovered.

Do not fabricate missing historical data.

---

# PART 16 — USER ACCOUNT AND PROFILE

Implement a proper account area.

## 16.1 Profile

Display:

- Avatar.
- Display Name.
- Username.
- Email.
- Account Created Date.
- Optional biography.

Allow editing supported fields.

## 16.2 Account settings

Implement:

- Change Password.
- Change Email, if existing authentication supports it.
- Session Information.
- Logout.
- Logout All Devices.
- Delete Account.
- Data Export, where supported.

## 16.3 Preferences

Store:

- Theme.
- Home layout preferences.
- Audio preferences.
- Playback settings.
- Notification settings.
- Library sorting.
- Cache preferences.

Preferences should persist across sessions and devices where appropriate.

## 16.4 Session security

Preserve the existing secure session implementation.

Ensure:

- Token hashes are not exposed.
- Expired sessions are rejected.
- Refresh/session rotation follows existing security rules.
- Logout revokes the appropriate session.
- Sensitive credentials are never returned by account APIs.

---

# PART 17 — DESIGN AND USER EXPERIENCE

The application should feel like a premium, modern music product.

Do not copy Spotify's exact branding or proprietary visual assets.

Develop a coherent GMusic visual language.

## 17.1 Design direction

Use:

- Dark-first theme.
- Minimal interface.
- High-quality artwork.
- Clean typography.
- Consistent spacing.
- Subtle borders.
- Refined card layouts.
- Smooth transitions.
- Compact controls.
- Clear hierarchy.

Avoid:

- Excessive gradients.
- Oversized controls.
- Too many decorative elements.
- Crowded headers.
- Randomly different card styles.
- Large unnecessary empty spaces.
- Inconsistent corner radii.
- Excessive animation.

## 17.2 Design tokens

Centralize:

- Background colors.
- Surface colors.
- Elevated surfaces.
- Text colors.
- Secondary text.
- Accent color.
- Borders.
- Spacing.
- Radii.
- Typography.
- Icon sizing.

Do not hardcode different design values across individual widgets.

## 17.3 Shared components

Create reusable components for:

- Mini-player.
- Song row.
- Song card.
- Artist card.
- Album card.
- Playlist card.
- Section header.
- Artwork widget.
- Context menu.
- Loading placeholder.
- Empty state.
- Error state.
- Search bar.
- Bottom sheet.
- Confirmation dialog.
- Playback controls.

Maintain visual and behavioral consistency throughout the application.

## 17.4 Song row requirements

Each song row should have:

- Artwork.
- Song title.
- Artist.
- Optional duration.
- Optional download indicator.
- Optional favorite indicator.
- Overflow menu.

Interactions:

- Tap to play.
- Long press for context menu.
- Overflow button for actions.
- Visual indication for the currently playing track.

Do not put too many controls into every row.

## 17.5 Artwork system

Implement:

- Image caching.
- Progressive loading.
- Error fallback.
- Placeholder.
- Consistent sizes.
- Thumbnail selection.
- Cache invalidation when artwork changes.

Avoid loading full-resolution album artwork in every small list item.

## 17.6 Transitions

Add subtle animations for:

- Opening Now Playing.
- Minimizing Now Playing.
- Changing artwork.
- Like/unlike.
- Queue reordering.
- Page transitions.
- Sheet expansion.
- Play/Pause changes.

Animations must not delay playback operations.

Respect reduced-motion preferences.

## 17.7 Responsive layout

Support:

- Small Android phones.
- Large Android phones.
- Tablets.
- Different display densities.
- Variable aspect ratios.
- iOS layouts, if supported.

Do not use hardcoded screen dimensions.

---

# PART 18 — FLUTTER IMPLEMENTATION REQUIREMENTS

Preserve the current Flutter project structure where practical.

Use feature modules rather than one enormous application file.

Suggested target organization:

```text
lib/
│
├── main.dart
├── app.dart
│
├── core/
│   ├── config/
│   ├── constants/
│   ├── errors/
│   ├── network/
│   ├── routing/
│   ├── theme/
│   ├── storage/
│   ├── utils/
│   └── widgets/
│
├── features/
│   ├── authentication/
│   ├── home/
│   ├── search/
│   ├── explore/
│   ├── library/
│   ├── artists/
│   ├── albums/
│   ├── playlists/
│   ├── favorites/
│   ├── history/
│   ├── playback/
│   ├── queue/
│   ├── downloads/
│   ├── lyrics/
│   ├── equalizer/
│   ├── analytics/
│   ├── profile/
│   └── settings/
│
├── playback_engine/
│   ├── audio_engine.dart
│   ├── playback_service.dart
│   ├── playback_controller.dart
│   ├── queue_manager.dart
│   ├── playback_state.dart
│   ├── playback_persistence.dart
│   └── audio_session_manager.dart
│
├── local_database/
│
├── synchronization/
│
└── services/
```

The final structure should respect existing project conventions.

## 18.1 State management

Use one consistent state-management approach across the application.

Before introducing a new library, inspect the current approach.

Avoid duplicating application state between:

- Page controllers.
- Global state.
- Audio service.
- Database.
- Backend.

Define the authoritative owner of each state.

Playback state must have one source of truth.

## 18.2 Networking

Use a centralized API client.

Requirements:

- Authentication headers.
- Token refresh.
- Request timeout.
- Cancellation.
- Error mapping.
- Response parsing.
- Pagination.
- Retry where appropriate.
- Offline detection.

Do not implement raw HTTP calls independently inside every page.

## 18.3 Local persistence

Use a structured local database if one already exists.

Persist:

- Cached track metadata.
- Cached artist information.
- Cached album information.
- Queue state.
- Preferences.
- Search history.
- Pending synchronization operations.
- Download metadata.

Do not store private authentication credentials in ordinary preferences or unprotected database tables.

## 18.4 Flutter performance

Avoid:

- Full widget tree rebuilds for every playback position update.
- Loading thousands of tracks at once.
- Synchronous audio metadata parsing on the UI thread.
- Repeated artwork downloads.
- Unbounded caches.
- Excessive API calls.
- Reinitializing the audio engine during navigation.

Use pagination and lazy rendering.

---

# PART 19 — NODE.JS BACKEND IMPLEMENTATION

Keep the existing Express application.

Refactor only where necessary to improve maintainability.

Suggested logical modules:

```text
server/
│
├── src/
│   ├── config/
│   │   ├── database.js
│   │   ├── environment.js
│   │   └── drive.js
│   │
│   ├── modules/
│   │   ├── auth/
│   │   ├── sessions/
│   │   ├── users/
│   │   ├── drive/
│   │   ├── indexing/
│   │   ├── metadata/
│   │   ├── tracks/
│   │   ├── artists/
│   │   ├── albums/
│   │   ├── search/
│   │   ├── favorites/
│   │   ├── playlists/
│   │   ├── history/
│   │   ├── playback/
│   │   ├── downloads/
│   │   ├── recommendations/
│   │   ├── analytics/
│   │   └── preferences/
│   │
│   ├── middleware/
│   ├── services/
│   ├── repositories/
│   ├── jobs/
│   ├── utilities/
│   ├── routes/
│   └── app.js
│
├── tests/
├── package.json
└── server.js
```

## 19.1 Architectural separation

Routes should not contain substantial business logic.

Use the flow:

```text
Route
  |
  v
Authentication / Validation
  |
  v
Controller
  |
  v
Service
  |
  v
Repository
  |
  v
MongoDB / Google Drive
```

Keep Drive integration behind a dedicated service.

Do not allow every feature module to implement its own Google Drive API calls.

## 19.2 Logging

Use structured logs.

Log:

- API errors.
- Drive API errors.
- Indexing errors.
- Playback failures.
- Database failures.
- Synchronization problems.
- Authentication failures.

Never log passwords, tokens, private keys or unrestricted playback URLs.

## 19.3 Environment configuration

Keep configuration in environment variables.

Use an example environment file containing names and placeholders only.

Do not commit real secrets.

Validate required configuration on startup.

---

# PART 20 — DATABASE DESIGN

Inspect the existing collections first.

Modify existing models when possible rather than duplicating them.

The following collections are logical targets.

## 20.1 Users

Store:

- User ID.
- Username.
- Email.
- Password hash.
- Profile.
- Preferences.
- Created time.
- Updated time.

## 20.2 Sessions

Store:

- User ID.
- Token hash.
- Device information.
- Created time.
- Expiry time.
- Last activity.
- Revocation status.

Preserve existing session implementation and security semantics.

## 20.3 Drive file index

Suggested fields:

```json
{
  "_id": "internal_track_id",
  "driveFileId": "google_drive_file_id",
  "name": "original_filename.flac",
  "mimeType": "audio/flac",
  "extension": "flac",
  "size": 25000000,
  "modifiedTime": "timestamp",
  "md5Checksum": "checksum",
  "parentIds": [],
  "metadataStatus": "indexed",
  "lastIndexedAt": "timestamp",
  "availability": "available"
}
```

## 20.4 Track metadata

```json
{
  "_id": "track_id",
  "driveFileId": "google_drive_file_id",
  "title": "Track Name",
  "artists": ["Artist One"],
  "album": "Album Name",
  "albumArtist": "Artist One",
  "genre": ["Rock"],
  "year": 2024,
  "trackNumber": 1,
  "discNumber": 1,
  "durationMs": 245000,
  "artworkRef": "artwork_reference",
  "format": "flac",
  "sampleRate": 44100,
  "bitDepth": 16,
  "updatedAt": "timestamp"
}
```

Adapt the representation to the current models.

Avoid storing the same information unnecessarily in multiple documents.

## 20.5 Playlists

Store:

- Owner ID.
- Name.
- Description.
- Artwork reference.
- Visibility.
- Track count.
- Created time.
- Updated time.
- Version.

## 20.6 Playlist items

Store:

- Playlist ID.
- Canonical track ID.
- Drive file ID where useful.
- Position.
- Added time.
- Added by user.

Use a stable ordering strategy.

## 20.7 Favorites

Use:

- User ID.
- Track ID.
- Created time.

Create a unique compound index to prevent duplicate likes.

## 20.8 Listening history

Store:

- User ID.
- Track ID.
- Start time.
- Played duration.
- Completion.
- Playback context.
- Device ID where available.

## 20.9 Search history

Store:

- User ID.
- Query.
- Timestamp.

Apply retention limits and respect user preferences.

## 20.10 Preferences

Store:

- User ID.
- Theme.
- Player settings.
- Audio settings.
- Library sorting.
- Home layout.
- Notification preferences.

## 20.11 Queue snapshots

Where server-side queue persistence is required, store:

- User ID.
- Queue entries.
- Current index.
- Current track.
- Shuffle state.
- Repeat state.
- Updated time.
- Device context.

Do not let simultaneous device sessions unexpectedly overwrite each other's active playback state.

## 20.12 Indexes

Create indexes based on actual query requirements.

At minimum, consider:

- Unique user email.
- Unique Drive file ID in the relevant catalog scope.
- Track title search.
- Artist search.
- Album search.
- Unique user/track favorite pair.
- Playlist owner.
- Playlist ID/position.
- User/history timestamp.
- Session token hash.
- User/preference lookup.

Validate query plans for large collections.

---

# PART 21 — API CONTRACTS

Preserve existing endpoint compatibility.

Add or improve versioned endpoints using the existing conventions.

The following represents the target API functionality, not a requirement to duplicate endpoints that already exist.

## Authentication

```http
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
POST   /api/v1/auth/logout
POST   /api/v1/auth/logout-all
GET    /api/v1/auth/me
```

## Home

```http
GET    /api/v1/home
GET    /api/v1/home/sections
GET    /api/v1/home/recently-played
GET    /api/v1/home/recently-added
```

## Drive Library

```http
GET    /api/v1/drive/status
GET    /api/v1/drive/sync/status
POST   /api/v1/drive/sync
GET    /api/v1/drive/files
GET    /api/v1/drive/folders
```

The file-list endpoint should use indexed records, not perform a full Drive scan on every request.

## Catalog

```http
GET    /api/v1/tracks
GET    /api/v1/tracks/:id
GET    /api/v1/artists
GET    /api/v1/artists/:id
GET    /api/v1/artists/:id/tracks
GET    /api/v1/artists/:id/albums
GET    /api/v1/albums
GET    /api/v1/albums/:id
GET    /api/v1/albums/:id/tracks
GET    /api/v1/genres
```

## Search

```http
GET    /api/v1/search?q=
GET    /api/v1/search/suggestions?q=
GET    /api/v1/search/history
DELETE /api/v1/search/history
```

## Playback

```http
POST   /api/v1/playback/:trackId/resolve
GET    /api/v1/playback/:trackId/stream
POST   /api/v1/playback/events
```

The stream route must support the required authorization and byte-range semantics.

## Favorites

```http
GET    /api/v1/favorites
PUT    /api/v1/favorites/:trackId
DELETE /api/v1/favorites/:trackId
```

## Playlists

```http
GET    /api/v1/playlists
POST   /api/v1/playlists
GET    /api/v1/playlists/:id
PATCH  /api/v1/playlists/:id
DELETE /api/v1/playlists/:id

POST   /api/v1/playlists/:id/tracks
DELETE /api/v1/playlists/:id/tracks/:itemId
PATCH  /api/v1/playlists/:id/tracks/reorder
```

## Library

```http
GET    /api/v1/library
GET    /api/v1/library/albums
GET    /api/v1/library/artists
GET    /api/v1/library/playlists
GET    /api/v1/library/liked
```

## History

```http
GET    /api/v1/history
POST   /api/v1/history/events
DELETE /api/v1/history
```

## Downloads

```http
GET    /api/v1/downloads
GET    /api/v1/downloads/:trackId
GET    /api/v1/downloads/authorization/:trackId
```

Actual download bytes should be delivered through a supported authenticated file-transfer mechanism.

## Recommendations

```http
GET    /api/v1/recommendations
GET    /api/v1/recommendations/daily-mix
GET    /api/v1/recommendations/similar/:trackId
POST   /api/v1/recommendations/feedback
```

## Statistics

```http
GET    /api/v1/analytics/overview
GET    /api/v1/analytics/top-tracks
GET    /api/v1/analytics/top-artists
GET    /api/v1/analytics/top-albums
GET    /api/v1/analytics/genres
```

Every endpoint must:

- Validate input.
- Authenticate protected requests.
- Check user ownership.
- Return consistent errors.
- Handle empty results.
- Support pagination where applicable.

---

# PART 22 — DATA SYNCHRONIZATION

Implement reliable synchronization between mobile and backend.

## 22.1 User-level data

Synchronize:

- Favorites.
- Playlists.
- Saved albums.
- Followed artists.
- Preferences.
- Listening history.
- Search history where enabled.

## 22.2 Offline changes

When offline:

- Update local UI immediately.
- Persist changes locally.
- Add a synchronization operation to the local pending queue.
- Retry when connectivity returns.

Do not lose user changes when API requests fail.

## 22.3 Conflict resolution

Handle concurrent changes.

Examples:

- User adds a song to a playlist from two devices.
- User removes a favorite on one device while another device adds it.
- User reorders the same playlist simultaneously.

Use version checking and clear conflict policies.

Do not blindly overwrite newer server state.

## 22.4 Idempotency

Repeated network requests should not create duplicate favorites or duplicate synchronization effects.

Use stable identifiers or idempotency strategies where appropriate.

## 22.5 Drive catalog synchronization is separate

Drive catalog synchronization and user library synchronization are different processes.

Do not unnecessarily trigger full Drive reindexing whenever a user likes a song or edits a playlist.

---

# PART 23 — SETTINGS AND ACCOUNT EXPERIENCE

Create a complete settings interface.

### Account

- Profile.
- Email.
- Password.
- Session Management.
- Logout.
- Logout All Devices.
- Delete Account.

### Playback

- Autoplay.
- Shuffle.
- Repeat.
- Crossfade.
- Gapless.
- Playback Resumption.

### Audio

- Equalizer.
- Presets.
- Balance.
- Normalization.
- Audio Information.

### Library

- Default Sorting.
- Grid/List View.
- Pinned Sections.
- Recently Played Visibility.

### Storage

- Cache Usage.
- Download Usage.
- Clear Temporary Cache.
- Manage Downloads.
- Maximum Storage.

### Appearance

- Dark.
- Light.
- System.
- Dynamic Artwork Colors.
- Reduced Motion.

### Privacy

- Private Session.
- Listening Statistics.
- Search History.
- Data Export.
- Data Deletion.

### Support

- About.
- App Version.
- Privacy Policy.
- Terms.
- Report a Bug.
- Feedback.

Settings must persist and actually affect application behavior.

---

# PART 24 — ERROR HANDLING

Every critical operation must have proper error handling.

## Drive errors

Handle:

- Authentication failure.
- Permission denied.
- Quota exceeded.
- File deleted.
- File unavailable.
- Rate limit.
- Expired change token.
- Temporary upstream failure.

## Playback errors

Handle:

- Invalid stream.
- Expired authorization.
- Network disconnected.
- Decoder failure.
- Unsupported file.
- Missing track.
- Seeking failure.

## Database errors

Handle:

- Connection failure.
- Duplicate records.
- Missing records.
- Invalid model.
- Migration failure.

## Mobile errors

Handle:

- Storage permission denied.
- Download interrupted.
- Insufficient storage.
- Audio focus loss.
- Background execution restrictions.

## User experience

Show useful messages and recovery options.

Do not show raw stack traces.

Do not silently ignore failures.

A temporary failure must not erase valid user data.

---

# PART 25 — SECURITY

Implement and verify:

- Existing secure authentication.
- Secure session persistence.
- User-level authorization.
- Input validation.
- Rate limiting.
- Protected API routes.
- Safe file streaming.
- Drive credentials only on the backend.
- Secure environment configuration.
- File size validation where relevant.
- Request size limits.
- Safe MongoDB queries.
- Protection against path traversal.
- Safe logging.
- Session revocation.
- Account deletion handling.

Do not trust client-provided user IDs for ownership checks.

Use the authenticated server-side identity.

Do not expose the Google Drive service account or credentials through API responses, logs or build files.

---

# PART 26 — PERFORMANCE REQUIREMENTS

The application must remain responsive with a large Drive collection.

Optimize for:

- Thousands of songs.
- Hundreds of albums.
- Large playlists.
- Large artwork libraries.
- Slow network connections.
- Intermittent connectivity.

## Backend

- Use pagination.
- Use database indexes.
- Avoid repeated full Drive scans.
- Avoid N+1 database operations.
- Avoid buffering audio in memory.
- Cache expensive catalog queries.
- Process metadata outside latency-sensitive requests.
- Avoid repeatedly querying Drive for the same unchanged file.

## Flutter

- Use lazy loading.
- Use image caching.
- Avoid excessive widget rebuilds.
- Avoid parsing entire libraries on the main isolate.
- Avoid repeated audio engine initialization.
- Avoid unnecessary network requests.
- Use efficient search.
- Avoid loading all playlist entries into memory when not necessary.

Measure performance instead of assuming it is fast.

---

# PART 27 — TESTING AND VALIDATION

Testing is mandatory.

## 27.1 Authentication tests

Test:

- Registration.
- Login.
- Invalid credentials.
- Session restoration.
- Session expiration.
- Refresh.
- Logout.
- Logout all devices.
- User data separation.

## 27.2 Drive tests

Test:

- Initial indexing.
- Pagination.
- Large collections.
- Modified files.
- Deleted files.
- Renamed files.
- Incremental synchronization.
- Expired change tokens.
- Retry.
- Unsupported files.
- Duplicate filenames.

## 27.3 Metadata tests

Test:

- MP3 tags.
- FLAC metadata.
- M4A metadata.
- Missing title.
- Missing artist.
- Missing artwork.
- Multiple artists.
- Compilation albums.
- Multi-disc albums.
- Duplicate album names.

## 27.4 Playback tests

Test:

- Start playback.
- Pause.
- Resume.
- Seek.
- Previous.
- Next.
- Repeat One.
- Repeat All.
- Shuffle.
- Add to Queue.
- Play Next.
- Remove from Queue.
- Queue reordering.
- Queue restoration.
- Background playback.
- Lock-screen controls.
- Bluetooth controls.
- Network interruption.
- Deleted Drive file.

## 27.5 Library tests

Test:

- Favorite.
- Unfavorite.
- Save Album.
- Follow Artist.
- Create Playlist.
- Add Track.
- Remove Track.
- Reorder.
- Rename.
- Delete.
- Offline update.
- Sync recovery.

## 27.6 Download tests

Test:

- Start.
- Pause.
- Resume.
- Cancel.
- Retry.
- Insufficient storage.
- Duplicate download.
- Partial file recovery.
- Offline playback.
- Cache cleanup.

## 27.7 UI tests

Test:

- Navigation.
- Home sections.
- Search.
- Search filters.
- Artist screen.
- Album screen.
- Playlist screen.
- Mini-player.
- Full player.
- Queue.
- Favorites.
- Downloads.
- Settings.
- Empty states.
- Error states.

## 27.8 Physical device validation

Validate on an actual Android device:

- Background audio.
- Notification controls.
- Lock-screen playback.
- Bluetooth.
- Audio focus.
- Large file seeking.
- FLAC playback.
- Network interruptions.
- Download interruptions.
- Battery and memory behavior.

Do not claim device-level audio functionality is complete based solely on unit tests or emulator tests.

---

# PART 28 — IMPLEMENTATION PHASES AND EXECUTION ORDER

Build the system in the following sequence.

The phases should be completed in order where dependencies require it. Independent work can be parallelized when safe.

## PHASE 0 — AUDIT EXISTING PROJECT

Tasks:

- Inspect all source files.
- Identify completed features.
- Identify incomplete features.
- Map the backend.
- Map database collections.
- Map Drive integration.
- Map playback architecture.
- Identify UI inconsistencies.
- Identify bugs.
- Identify duplicated implementations.

Deliverable:

`IMPLEMENTATION_AUDIT.md`

This must describe the real project, not an imagined architecture.

## PHASE 1 — FOUNDATION AND STABILITY

Tasks:

- Fix existing critical defects.
- Consolidate playback state.
- Consolidate API handling.
- Verify authentication.
- Verify navigation.
- Verify current data persistence.
- Establish common UI components.

Deliverable:

Stable existing foundation with no regression.

## PHASE 2 — DRIVE INDEXING AND METADATA

Tasks:

- Implement persistent index.
- Implement audio file filtering.
- Implement metadata extraction.
- Implement artist normalization.
- Implement album grouping.
- Implement artwork caching.
- Implement incremental synchronization.
- Implement indexing status.

Deliverable:

A complete searchable music catalog derived from Drive.

## PHASE 3 — CATALOG AND DISCOVERY UI

Tasks:

- Home.
- Search.
- Explore.
- Artist pages.
- Album pages.
- Track details.

Deliverable:

Users can navigate their entire Drive music collection through a polished interface.

## PHASE 4 — PLAYBACK ENGINE

Tasks:

- Central controller.
- Queue manager.
- Mini-player.
- Full player.
- Seeking.
- Shuffle.
- Repeat.
- Background playback.
- Media session.
- Queue persistence.
- Playback recovery.

Deliverable:

Reliable, uninterrupted music playback across navigation and background states.

## PHASE 5 — PERSONAL LIBRARY

Tasks:

- Liked Songs.
- Saved Albums.
- Followed Artists.
- Your Library.
- Recently Played.
- Most Played.
- Playlist management.
- User preferences.

Deliverable:

A complete account-specific music library.

## PHASE 6 — DOWNLOADS AND OFFLINE

Tasks:

- Download manager.
- Persistent offline files.
- Retry.
- Resume.
- Storage management.
- Offline browsing.
- Offline playback.
- Synchronization recovery.

Deliverable:

Usable music playback without an internet connection for locally available content.

## PHASE 7 — ADVANCED AUDIO

Tasks:

- Lyrics.
- Sleep timer.
- Equalizer.
- Audio controls.
- Crossfade.
- Gapless playback.
- Volume normalization.

Deliverable:

Complete advanced player experience.

## PHASE 8 — RECOMMENDATIONS

Tasks:

- Listening analytics.
- Similar Songs.
- Radio.
- Daily Mix.
- Genre Mix.
- Mood Mix.
- Personalized Home.
- Recommendation feedback.

Deliverable:

A discovery system that intelligently uses the user's actual music collection and listening activity.

## PHASE 9 — STATISTICS AND PERSONALIZATION

Tasks:

- Listening analytics.
- Top tracks.
- Top artists.
- Top albums.
- Listening trends.
- User-specific dashboard.
- Yearly recap.

Deliverable:

Complete music statistics and listening insights.

## PHASE 10 — SECURITY AND PRODUCTION HARDENING

Tasks:

- Review authorization.
- Review database queries.
- Review Drive access.
- Review session handling.
- Review streaming.
- Optimize queries.
- Add monitoring.
- Test network failures.
- Test large collections.
- Verify release configuration.

Deliverable:

A stable release candidate.

---

# PART 29 — REQUIRED PROJECT DOCUMENTATION

Maintain the following documentation.

## IMPLEMENTATION_STATUS.md

Track every module using:

- Not Started.
- In Progress.
- Implemented.
- Integrated.
- Tested.
- Complete.
- Blocked.

## IMPLEMENTATION_AUDIT.md

Describe the existing architecture and current feature status.

## ARCHITECTURE.md

Document:

- Flutter architecture.
- Backend architecture.
- Database structure.
- Drive integration.
- Playback engine.
- Synchronization.
- Data flows.

## API_DOCUMENTATION.md

Document:

- Endpoint.
- Method.
- Authentication.
- Input.
- Output.
- Errors.
- Pagination.

## DATABASE_SCHEMA.md

Document:

- Collections.
- Fields.
- Relationships.
- Indexes.
- Migrations.

## SETUP.md

Document:

- Flutter setup.
- Backend setup.
- MongoDB setup.
- Google Drive configuration.
- Environment variables.
- Build instructions.
- Deployment.

## CHANGELOG.md

Record significant changes.

---

# PART 30 — DEFINITION OF COMPLETE

The project is not finished because all the screens have been created.

The application is complete only when all of the following are true.

### Core Application

- [ ] Existing login and registration work.
- [ ] Sessions persist correctly.
- [ ] User data is isolated.
- [ ] Navigation works.
- [ ] Existing functionality has not regressed.

### Google Drive

- [ ] Drive files are indexed.
- [ ] Indexing supports pagination.
- [ ] Metadata extraction works.
- [ ] Artist and album grouping works.
- [ ] Artwork is cached.
- [ ] Incremental synchronization works.
- [ ] Deleted and modified files are handled.
- [ ] Search operates against the index.

### Discovery

- [ ] Personalized Home works.
- [ ] Search works.
- [ ] Explore works.
- [ ] Artist pages work.
- [ ] Album pages work.
- [ ] Recommendations use real collection data.

### Playback

- [ ] One central audio engine exists.
- [ ] Mini-player works.
- [ ] Full player works.
- [ ] Seeking works.
- [ ] Shuffle works.
- [ ] Repeat works.
- [ ] Queue works.
- [ ] Queue persists.
- [ ] Background playback works.
- [ ] Notification controls work.
- [ ] Audio interruptions are handled.

### Library

- [ ] Favorites persist.
- [ ] Albums can be saved.
- [ ] Artists can be followed.
- [ ] Playlists can be created.
- [ ] Songs can be added.
- [ ] Songs can be removed.
- [ ] Songs can be reordered.
- [ ] History updates correctly.
- [ ] Statistics use real events.

### Offline

- [ ] Downloads actually save files.
- [ ] Downloads can resume.
- [ ] Failed downloads can retry.
- [ ] Offline playback works.
- [ ] Cache cleanup preserves permanent files.
- [ ] Missing files are handled.

### Advanced Experience

- [ ] Lyrics integrate with a real source.
- [ ] Sleep timer works.
- [ ] Equalizer works where supported.
- [ ] Crossfade works where supported.
- [ ] Recommendations work.
- [ ] Settings persist.

### Quality

- [ ] No critical analyzer errors.
- [ ] No critical backend errors.
- [ ] Unit tests pass.
- [ ] Relevant widget tests pass.
- [ ] Integration tests pass.
- [ ] Actual device playback is validated.
- [ ] No major navigation regressions.
- [ ] No critical security issues.

---

# PART 31 — HOW YOU MUST WORK AS THE CODING AGENT

This section is particularly important.

You are expected to implement the application, not simply describe how someone else could implement it.

Follow this workflow:

### Step 1 — Explore the repository

Read the project structure and all important existing files.

Do not immediately start generating code.

Identify existing implementations and dependencies.

### Step 2 — Produce the audit

Create `IMPLEMENTATION_AUDIT.md`.

Identify:

- What already works.
- What partially works.
- What is missing.
- What needs refactoring.
- What must not be changed.

### Step 3 — Establish an implementation checklist

Create `IMPLEMENTATION_STATUS.md`.

Break every major requirement into specific tasks.

### Step 4 — Implement the actual features

Modify existing source files where appropriate.

Create new files only where needed.

Implement backend and Flutter changes together when a feature requires both.

Do not stop after designing a page.

### Step 5 — Validate every feature

After each major implementation:

- Run Dart analysis.
- Run available Flutter tests.
- Run backend tests.
- Check database integration.
- Verify API responses.
- Verify playback.
- Check for regressions.

### Step 6 — Keep documentation updated

Update implementation status and technical documentation after meaningful changes.

### Step 7 — Perform a complete final review

Check:

- Dead code.
- Duplicate services.
- Duplicate API calls.
- Unused dependencies.
- Incomplete functionality.
- Hardcoded data.
- Security issues.
- Unhandled exceptions.
- Performance bottlenecks.

### Step 8 — Report accurately

At the end, provide:

1. Implemented features.
2. Modified files.
3. New files.
4. Backend changes.
5. Database changes.
6. New dependencies.
7. Commands executed.
8. Tests passed.
9. Tests not run.
10. Remaining incomplete features.
11. Known limitations.
12. Build/run instructions.

Never claim that something works unless it has actually been implemented and validated.

If a particular feature is blocked by a missing API, external service, platform limitation or unavailable credential, implement the appropriate abstraction and clearly report the blocker.

Do not silently replace it with fake functionality.

---

# FINAL PRODUCT GOAL

Transform GMusic from its current Google Drive music playback application into a complete, polished personal music platform.

The final product must have:

- A sophisticated personalized Home.
- A complete searchable music library.
- Automatic music organization.
- Artist and album navigation.
- Advanced playlists.
- A reliable global audio player.
- A persistent and intelligent queue.
- Background playback.
- Favorites and listening history.
- Offline downloads.
- Lyrics integration.
- Advanced audio settings.
- Personalized music discovery.
- Listening analytics.
- Excellent application performance.
- Reliable Google Drive synchronization.
- Secure account management.

**Google Drive must remain the underlying music storage source.**

**The existing Flutter application and Node.js backend must remain the foundation.**

**The central playback engine and Google Drive indexing system must be treated as two of the most critical engineering components.**

Build the application as one cohesive product. Every page must integrate with the same catalog, the same user library and the same playback system.

Do not build disconnected features.

Do not build a new application alongside the existing one.

Do not remove working functionality.

Do not stop at a plan.

**Inspect the existing repository, make the required changes, integrate the features, test the implementation and deliver a working GMusic application.**