# GMusic

Flutter music player for the common Google Drive library served by the GMusic
backend.

## Run locally on Chrome

1. Configure the backend's ignored `.env` file and Google Drive credentials as
   described in the [backend README](../../Backend/Gdrive_backend/README.md).
2. Start the backend in a separate terminal:

   ```powershell
   Set-Location 'D:\Backend\Gdrive_backend'
   npm install
   npm start
   ```

   The backend listens on `http://127.0.0.1:43821` by default, connects to the
   shared MongoDB, and uses the common Drive library.
3. Run the Flutter app in Chrome:

   ```powershell
   Set-Location 'D:\flutter projects\GMusic'
   flutter pub get
   flutter run -d chrome --dart-define=GMUSIC_BRIDGE_URL=http://127.0.0.1:43821
   ```

The app defaults to `https://gmusicbackend.vercel.app/`. The command above
overrides that setting to use the local backend. Sign in with an existing
GMusic account or create one; account and shared-library data are stored by
the configured backend. Keep backend secrets and Google credentials out of
the Flutter app and source control.

## Connected playback

Signed-in GMusic clients share one account playback session. Open the existing
Devices control in Now Playing to see online and recently seen GMusic players,
transfer the current track and queue, and control the active player. The
transfer target must be online and signed in to the same account; the source
continues playing until the target has prepared the queue and acknowledged the
handoff. Remote controls include playback, seek, shuffle, repeat, queue edits,
favorites and target-player volume when supported. Settings provides device
renaming, account visibility and disconnect/forget actions.

If the active device stops heartbeating, an online GMusic client takes over
through the same prepared handoff flow. Playback resumes on the replacement
device if the expired session had been playing.

Device state, commands, command acknowledgments and transfer requests use
authenticated Socket.IO over WebSocket with reconnect and MongoDB state
resynchronization. Socket.IO emits playback commands to the active player and
waits for its execution acknowledgment; command status remains available over
REST for recovery. Repeated acknowledgments are safe to retry. Remote progress
uses the server clock reference, avoiding drift from differences between device
clocks, and track changes are published as soon as the active player stops the
old source. If Socket.IO or cross-instance Redis is unavailable, the app falls
back to HTTP polling. The backend health endpoint reports whether Redis-backed
cross-instance broadcasts are ready.

Playback endpoints are GMusic app instances, not arbitrary Bluetooth
speakers, TVs or receivers. Those require a GMusic player integration on the
endpoint. Discovery uses the account registry, so devices do not need to be on
the same Wi-Fi network. Android's media service can continue playback when its
controller UI is closed; a web player still depends on its browser tab staying
alive. Local mDNS discovery, QR pairing and multi-room playback are not
implemented.
