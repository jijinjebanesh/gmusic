import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/models/track.dart';
import 'package:gmusic/services/audio_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restores the persisted queue and index without starting playback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const first = Track(
        id: 'one',
        name: 'One.mp3',
        streamUrl: 'https://audio.example/one',
      );
      const second = Track(
        id: 'two',
        name: 'Two.mp3',
        streamUrl: 'https://audio.example/two',
      );
      await preferences.setString(
        'playback_queue_v1',
        jsonEncode({
          'queue': [first.toJson(), second.toJson()],
          'orderIndices': [1, 0],
          'index': 0,
          'shuffle': true,
          'repeat': 'all',
        }),
      );

      final handler = GMusicAudioHandler();
      await handler.restoreQueue(preferences);
      final restored = handler.currentUiState;
      expect(restored.queue.map((track) => track.id), ['two', 'one']);
      expect(restored.track?.id, 'two');
      expect(restored.shuffle, isTrue);
      expect(restored.playing, isFalse);
      handler.dispose();
    },
  );

  test(
    'reordering and removing queued rows preserves the active track',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const first = Track(
        id: 'one',
        name: 'One.mp3',
        streamUrl: 'https://audio.example/one',
      );
      const second = Track(
        id: 'two',
        name: 'Two.mp3',
        streamUrl: 'https://audio.example/two',
      );
      const third = Track(
        id: 'three',
        name: 'Three.mp3',
        streamUrl: 'https://audio.example/three',
      );
      await preferences.setString(
        'playback_queue_v1',
        jsonEncode({
          'queue': [first.toJson(), second.toJson(), third.toJson()],
          'orderIndices': [0, 1, 2],
          'index': 1,
          'shuffle': false,
          'repeat': 'none',
        }),
      );

      final handler = GMusicAudioHandler();
      await handler.restoreQueue(preferences);

      handler.reorderQueue(2, 0);
      expect(handler.currentUiState.queue.map((track) => track.id), [
        'three',
        'one',
        'two',
      ]);
      expect(handler.currentUiState.track?.id, 'two');
      expect(handler.currentUiState.index, 2);

      handler.removeAt(0);
      expect(handler.currentUiState.queue.map((track) => track.id), [
        'one',
        'two',
      ]);
      expect(handler.currentUiState.track?.id, 'two');
      expect(handler.currentUiState.index, 1);
      handler.dispose();
    },
  );

  test(
    'refreshes a queued stream URL when its backend origin changes',
    () async {
      final handler = GMusicAudioHandler();
      handler.setBridgeUrl('https://gmusicbackend.vercel.app/');
      var refreshCount = 0;
      handler.refresher = (id) async {
        refreshCount += 1;
        expect(id, 'one');
        return const Track(
          id: 'one',
          name: 'One.mp3',
          streamUrl: 'https://gmusicbackend.vercel.app/stream/new-ticket',
        );
      };

      const savedTrack = Track(
        id: 'one',
        name: 'One.mp3',
        streamUrl: 'http://127.0.0.1:43821/stream/old-ticket',
      );
      final refreshed = await handler.refreshStreamUrlIfNeeded(savedTrack);
      expect(
        refreshed.streamUrl,
        'https://gmusicbackend.vercel.app/stream/new-ticket',
      );
      expect(refreshCount, 1);

      const currentTrack = Track(
        id: 'two',
        name: 'Two.mp3',
        streamUrl: 'https://gmusicbackend.vercel.app/stream/current-ticket',
      );
      expect(
        await handler.refreshStreamUrlIfNeeded(currentTrack),
        same(currentTrack),
      );
      expect(refreshCount, 1);
      handler.dispose();
    },
  );
}
