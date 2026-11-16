import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/models/track.dart';
import 'package:gmusic/services/download_storage.dart';
import 'package:gmusic/state/download_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    supportDirectory = await Directory.systemTemp.createTemp(
      'gmusic-download-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'download writes a local file, persists metadata, and prevents duplicates',
    () async {
      var requests = 0;
      final preferences = await SharedPreferences.getInstance();
      final controller = DownloadController(
        preferences,
        'user-a',
        clientFactory: () => MockClient((request) async {
          requests += 1;
          expect(
            request.url,
            Uri.parse('https://bridge.example/stream/ticket'),
          );
          return http.Response.bytes([1, 2, 3, 4], 200);
        }),
      );
      const track = Track(
        id: 'drive-id',
        name: 'Song.mp3',
        streamUrl: 'https://bridge.example/stream/ticket',
        catalogTitle: 'Song',
        artists: ['Artist'],
      );

      await controller.download(track);
      final entry = controller.state.items['drive-id'];
      expect(entry, isNotNull);
      expect(entry!.track.localPath, entry.path);
      expect(await File(entry.path).readAsBytes(), [1, 2, 3, 4]);
      await controller.download(track);
      expect(requests, 1);

      final restored = DownloadController(preferences, 'user-a');
      expect(restored.state.items['drive-id']?.track.title, 'Song');
      expect(restored.state.items['drive-id']?.track.localPath, entry.path);
      await restored.remove('drive-id');
      expect(await File(entry.path).exists(), isFalse);
      controller.dispose();
      restored.dispose();
    },
  );

  test('download history is isolated by account', () async {
    final preferences = await SharedPreferences.getInstance();
    final first = DownloadController(
      preferences,
      'user-a',
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes([7], 200)),
    );
    const track = Track(
      id: 't',
      name: 'Track.flac',
      streamUrl: 'https://audio.example/t',
    );
    await first.download(track);
    final second = DownloadController(preferences, 'user-b');
    expect(second.state.items, isEmpty);
    expect(preferences.getStringList('downloaded_tracks_user-a'), isNotEmpty);
    expect(
      jsonDecode(preferences.getStringList('downloaded_tracks_user-a')!.single),
      isA<Map>(),
    );
    await first.remove('t');
    first.dispose();
    second.dispose();
  });

  test(
    'recovers a paused partial download with an HTTP range request',
    () async {
      final preferences = await SharedPreferences.getInstance();
      const track = Track(
        id: 'resume-track',
        name: 'Resume.mp3',
        streamUrl: 'https://audio.example/resume',
      );
      final partial = await createDownloadFile('user-a', track.id, track.name);
      await partial.write([1, 2]);
      await partial.pause();
      await preferences.setStringList('downloaded_tracks_user-a_pending', [
        jsonEncode(track.toJson()),
      ]);

      final controller = DownloadController(
        preferences,
        'user-a',
        clientFactory: () => _RangeClient((request) async {
          expect(request.headers['range'], 'bytes=2-');
          return http.StreamedResponse(
            Stream<List<int>>.value([3, 4]),
            206,
            contentLength: 2,
          );
        }),
      );
      expect(controller.state.pausedTracks[track.id]?.id, track.id);
      await controller.download(track);
      final entry = controller.state.items[track.id]!;
      expect(await File(entry.path).readAsBytes(), [1, 2, 3, 4]);
      expect(entry.size, 4);
      expect(controller.state.pausedTracks, isEmpty);
      expect(
        preferences.getStringList('downloaded_tracks_user-a_pending'),
        isEmpty,
      );
      controller.dispose();
    },
  );
}

class _RangeClient extends http.BaseClient {
  _RangeClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}
