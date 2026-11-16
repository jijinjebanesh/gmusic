import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/models/playback.dart';
import 'package:gmusic/models/track.dart';

void main() {
  test('an offline remote session remains the selected playback target', () {
    const state = RemotePlaybackState(
      deviceId: 'local-device',
      devices: [
        PlaybackDevice(
          id: 'remote-device',
          name: 'Web player',
          platform: 'web',
          online: false,
        ),
      ],
      remoteQueue: [
        Track(
          id: 'track-one',
          name: 'Track one.flac',
          streamUrl: 'https://example.com/stream/ticket',
        ),
      ],
      session: RemotePlaybackSession(
        activeDeviceId: 'remote-device',
        trackIds: ['track-one'],
        index: 0,
        positionMs: 1200,
        durationMs: 240000,
        playing: true,
        shuffle: false,
        repeat: 'none',
        title: 'Track one',
        artist: 'Artist',
        queueRevision: 1,
      ),
    );

    expect(state.remoteTargeted, isTrue);
    expect(state.remoteActive, isFalse);
    expect(state.remoteCurrentTrack?.id, 'track-one');
  });

  test(
    'remote session exposes its current track while queue metadata loads',
    () {
      const session = RemotePlaybackSession(
        activeDeviceId: 'remote-device',
        trackIds: ['track-one'],
        index: 0,
        positionMs: 1200,
        durationMs: 240000,
        playing: true,
        shuffle: false,
        repeat: 'none',
        title: 'Track one',
        artist: 'Artist',
        queueRevision: 1,
      );

      expect(session.currentTrackId, 'track-one');
      expect(session.trackPlaceholder?.title, 'Track one');
      expect(session.trackPlaceholder?.artist, 'Artist');
    },
  );

  test('remote position uses server time instead of device clock skew', () {
    final serverUpdatedAt = DateTime.utc(2026, 11, 16, 10);
    final monotonicAtReceipt = const Duration(seconds: 20);
    final session = RemotePlaybackSession(
      activeDeviceId: 'remote-device',
      trackIds: const ['track-one'],
      index: 0,
      positionMs: 33000,
      durationMs: 240000,
      playing: true,
      shuffle: false,
      repeat: 'none',
      title: 'Track one',
      artist: 'Artist',
      queueRevision: 1,
      updatedAt: serverUpdatedAt,
      serverTimestamp: serverUpdatedAt.add(const Duration(seconds: 16)),
      serverTimeAtReceipt: serverUpdatedAt.add(const Duration(seconds: 16)),
      monotonicAtReceipt: monotonicAtReceipt,
    );

    expect(
      session.currentPositionAt(
        monotonicAtReceipt + const Duration(seconds: 2),
      ),
      const Duration(seconds: 51),
    );
  });

  test('remote position accounts for request latency and clock offset', () {
    final clientRequestStartedAt = const Duration(seconds: 10);
    final clientResponseReceivedAt =
        clientRequestStartedAt + const Duration(milliseconds: 300);
    final serverRequestTimestamp = DateTime.utc(
      2026,
      11,
      16,
      12,
    ).add(const Duration(hours: 2)).add(const Duration(milliseconds: 100));
    final serverTimestamp = serverRequestTimestamp.add(
      const Duration(milliseconds: 150),
    );
    final result = PlaybackPollResult.fromJson(
      {
        'serverRequestTimestamp': serverRequestTimestamp.toIso8601String(),
        'serverTimestamp': serverTimestamp.toIso8601String(),
        'session': {
          'activeDeviceId': 'remote-device',
          'trackIds': ['track-one'],
          'index': 0,
          'positionMs': 33000,
          'durationMs': 240000,
          'playing': true,
          'shuffle': false,
          'repeat': 'none',
          'title': 'Track one',
          'artist': 'Artist',
          'queueRevision': 1,
          'updatedAt': serverRequestTimestamp
              .subtract(const Duration(seconds: 16, milliseconds: 100))
              .toIso8601String(),
          'serverTimestamp': serverTimestamp.toIso8601String(),
        },
        'devices': [],
        'commands': [],
      },
      clientRequestStartedAtMonotonic: clientRequestStartedAt,
      clientResponseReceivedAtMonotonic: clientResponseReceivedAt,
    );

    expect(
      result.session!.currentPositionAt(
        clientResponseReceivedAt + const Duration(seconds: 2),
      ),
      const Duration(seconds: 51, milliseconds: 325),
    );
  });

  test('remote state ordering requires a newer epoch and state version', () {
    const current = RemotePlaybackSession(
      activeDeviceId: 'remote-device',
      trackIds: ['track-one'],
      index: 0,
      positionMs: 1200,
      durationMs: 240000,
      playing: true,
      shuffle: false,
      repeat: 'none',
      title: 'Track one',
      artist: 'Artist',
      queueRevision: 1,
      playbackEpoch: 4,
      stateVersion: 12,
    );
    const olderEpoch = RemotePlaybackSession(
      activeDeviceId: 'remote-device',
      trackIds: ['track-one'],
      index: 0,
      positionMs: 3000,
      durationMs: 240000,
      playing: true,
      shuffle: false,
      repeat: 'none',
      title: 'Track one',
      artist: 'Artist',
      queueRevision: 1,
      playbackEpoch: 3,
      stateVersion: 13,
    );
    const olderVersion = RemotePlaybackSession(
      activeDeviceId: 'remote-device',
      trackIds: ['track-one'],
      index: 0,
      positionMs: 3000,
      durationMs: 240000,
      playing: true,
      shuffle: false,
      repeat: 'none',
      title: 'Track one',
      artist: 'Artist',
      queueRevision: 1,
      playbackEpoch: 4,
      stateVersion: 11,
    );
    const newer = RemotePlaybackSession(
      activeDeviceId: 'remote-device',
      trackIds: ['track-one'],
      index: 0,
      positionMs: 3000,
      durationMs: 240000,
      playing: true,
      shuffle: false,
      repeat: 'none',
      title: 'Track one',
      artist: 'Artist',
      queueRevision: 1,
      playbackEpoch: 4,
      stateVersion: 13,
    );

    expect(olderEpoch.isNewerThan(current), isFalse);
    expect(olderVersion.isNewerThan(current), isFalse);
    expect(newer.isNewerThan(current), isTrue);
  });

  test('an online peer can fail over from an offline active device', () {
    const state = RemotePlaybackState(
      deviceId: 'online-device',
      devices: [
        PlaybackDevice(
          id: 'offline-device',
          name: 'Offline player',
          platform: 'web',
          online: false,
        ),
        PlaybackDevice(
          id: 'online-device',
          name: 'Phone',
          platform: 'android',
          online: true,
        ),
      ],
      session: RemotePlaybackSession(
        activeDeviceId: 'offline-device',
        trackIds: ['track-one'],
        index: 0,
        positionMs: 1200,
        durationMs: 240000,
        playing: false,
        shuffle: false,
        repeat: 'none',
        title: 'Track one',
        artist: 'Artist',
        queueRevision: 1,
      ),
    );

    expect(state.canFailoverToThisDevice, isTrue);
    expect(state.remoteTargeted, isTrue);
  });
}
