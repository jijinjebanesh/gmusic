import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/models/track.dart';
import 'package:gmusic/utils/duration_format.dart';

void main() {
  group('filename parsing', () {
    test('splits "Artist - Title" into title and artist', () {
      final track = Track(
        id: '1',
        name: 'Aalaporaan Thamizhan - Sathyaprakash, A. R. Rahman.flac',
        streamUrl: 'http://127.0.0.1:43821/stream/ticket',
      );
      expect(track.title, 'Aalaporaan Thamizhan');
      expect(track.artist, 'Sathyaprakash, A. R. Rahman');
      expect(track.extension, 'FLAC');
    });

    test('keeps the whole stem when there is no separator', () {
      final track = const Track(
        id: '2',
        name: 'Aadungada Enna Suthi.mp3',
        streamUrl: 'u',
      );
      expect(track.title, 'Aadungada Enna Suthi');
      expect(track.artist, isNull);
      expect(track.extension, 'MP3');
    });

    test('treats empty artist as unknown', () {
      final track = const Track(
        id: '3',
        name: 'Song - .m4a',
        streamUrl: 'u',
        mimeType: 'audio/mp4',
      );
      expect(track.title, 'Song');
      expect(track.artist, isNull);
    });

    test('does not split on hyphens without spaces', () {
      final track = const Track(
        id: '4',
        name: 'Well-Known - Someone.m4a',
        streamUrl: 'u',
      );
      expect(track.title, 'Well-Known');
      expect(track.artist, 'Someone');
    });
  });

  group('artwork url', () {
    test('derives the ticket-gated art endpoint from the stream url', () {
      const track = Track(
        id: 'abc',
        name: 'T - A.flac',
        streamUrl: 'http://127.0.0.1:43821/stream/TOKEN123',
      );
      expect(track.artUrl, 'http://127.0.0.1:43821/art/TOKEN123');
    });
  });

  test('track metadata round-trips for persisted playback queues', () {
    final original = Track(
      id: 'saved-track',
      name: 'Song.mp3',
      streamUrl: 'https://music.example/stream/ticket',
      mimeType: 'audio/mpeg',
      duration: const Duration(minutes: 3, seconds: 4),
      catalogTitle: 'Song title',
      artists: const ['Artist'],
      album: 'Album',
      year: 2024,
    );
    final restored = Track.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.artist, original.artist);
    expect(restored.album, original.album);
    expect(restored.duration, original.duration);
    expect(restored.streamUrl, original.streamUrl);
  });

  group('duration formatting', () {
    test('formats mm:ss', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
    });

    test('formats hours', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('renders unknown durations', () {
      expect(formatDuration(null), '--:--');
    });
  });
}
