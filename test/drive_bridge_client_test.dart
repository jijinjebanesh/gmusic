import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gmusic/models/playback.dart';
import 'package:gmusic/services/drive_bridge_client.dart';

const _sessionResponse = {
  'token': 'session-token',
  'user': {
    'id': 'user-id',
    'email': 'user@example.com',
    'displayName': 'User',
    'role': 'user',
  },
};

void main() {
  test('register sends JSON without a session authorization header', () async {
    late http.Request request;
    final client = DriveBridgeClient(
      baseUrl: 'https://example.com',
      token: 'stale-session-token',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_sessionResponse), 201);
      }),
    );

    final session = await client.register(
      email: 'user@example.com',
      password: 'password123',
      displayName: 'User',
    );

    expect(request.headers['content-type'], startsWith('application/json'));
    expect(request.headers['authorization'], isNull);
    expect(jsonDecode(request.body), {
      'email': 'user@example.com',
      'password': 'password123',
      'username': 'User',
    });
    expect(session.token, 'session-token');
    client.dispose();
  });

  test('login sends JSON without a session authorization header', () async {
    late http.Request request;
    final client = DriveBridgeClient(
      baseUrl: 'https://example.com',
      token: 'stale-session-token',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(jsonEncode(_sessionResponse), 200);
      }),
    );

    final session = await client.login(
      email: 'user@example.com',
      password: 'password123',
    );

    expect(request.headers['content-type'], startsWith('application/json'));
    expect(request.headers['authorization'], isNull);
    expect(jsonDecode(request.body), {
      'email': 'user@example.com',
      'password': 'password123',
    });
    expect(session.token, 'session-token');
    client.dispose();
  });

  test('track lyrics use the authenticated catalog endpoint', () async {
    late http.Request request;
    final client = DriveBridgeClient(
      baseUrl: 'https://example.com',
      token: 'session-token',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({'lyrics': '  First line\nSecond line  '}),
          200,
        );
      }),
    );

    final lyrics = await client.trackLyrics('drive-id');

    expect(request.url.path, '/api/v1/catalog/tracks/drive-id/lyrics');
    expect(request.headers['authorization'], 'Bearer session-token');
    expect(lyrics, 'First line\nSecond line');
    client.dispose();
  });

  test(
    'track lyrics treat the explicit no-lyrics response as an empty result',
    () async {
      final client = DriveBridgeClient(
        baseUrl: 'https://example.com',
        token: 'session-token',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'lyrics_not_found'}), 404),
        ),
      );

      expect(await client.trackLyrics('drive-id'), isNull);
      client.dispose();
    },
  );

  test(
    'reuses recently resolved track metadata during a playback handoff',
    () async {
      var catalogRequests = 0;
      final client = DriveBridgeClient(
        baseUrl: 'https://example.com',
        token: 'session-token',
        client: MockClient((incoming) async {
          catalogRequests += 1;
          expect(incoming.url.path, '/api/v1/catalog/tracks/resolve');
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'track-one',
                  'name': 'Track one.flac',
                  'streamUrl': 'https://example.com/stream/ticket',
                },
              ],
            }),
            200,
          );
        }),
      );

      final initialQueue = await client.catalogTracksByIds(['track-one']);
      final handoffTrack = await client.catalogTrack('track-one');
      final updatedQueue = await client.catalogTracksByIds([
        'track-one',
        'track-one',
      ]);

      expect(catalogRequests, 1);
      expect(handoffTrack?.streamUrl, initialQueue.single.streamUrl);
      expect(updatedQueue.map((track) => track.id), ['track-one', 'track-one']);
      client.dispose();
    },
  );

  test(
    'playback Socket.IO authenticates and reconciles device state',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final registerFrame = Completer<Map<String, dynamic>>();
      final heartbeatFrame = Completer<Map<String, dynamic>>();
      final handoffCheckpointFrame = Completer<Map<String, dynamic>>();
      final serverSocketReady = Completer<WebSocket>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        serverSocketReady.complete(socket);
        socket.add(
          '0{"sid":"engine-session","upgrades":[],"pingInterval":25000,'
          '"pingTimeout":20000,"maxPayload":65536}',
        );
        socket.listen((data) {
          final frame = data.toString();
          if (frame == '2' || frame == '2probe') {
            socket.add(frame == '2probe' ? '3probe' : '3');
            return;
          }
          if (frame.startsWith('40')) {
            final auth = jsonDecode(frame.substring(2)) as Map<String, dynamic>;
            expect(auth['token'], 'session-token');
            socket.add('40{"sid":"socket-session"}');
            return;
          }
          if (!frame.startsWith('42')) return;
          final payloadStart = frame.indexOf('[');
          final acknowledgementId = frame.substring(2, payloadStart);
          final packet = jsonDecode(frame.substring(payloadStart)) as List;
          final event = packet.first as String;
          final payload = Map<String, dynamic>.from(packet[1] as Map);
          final response = {
            'ok': true,
            if (event == 'device:register') ...{
              'crossInstance': true,
              'result': {'session': null, 'devices': [], 'commands': []},
            },
            if (event == 'device:heartbeat')
              'result': {'session': null, 'devices': [], 'commands': []},
            if (event == 'playback:command:ack') ...{
              'commandId': 'handoff-command',
              'status': 'ok',
              'transferStatus': 'completed',
            },
          };
          if (event == 'device:register') registerFrame.complete(payload);
          if (event == 'device:heartbeat') {
            if (!heartbeatFrame.isCompleted) {
              heartbeatFrame.complete(payload);
            } else {
              handoffCheckpointFrame.complete(payload);
            }
          }
          socket.add('43$acknowledgementId${jsonEncode([response])}');
        });
      });
      final client = DriveBridgeClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'session-token',
      );
      PlaybackSocketConnection? connection;
      StreamSubscription<dynamic>? subscription;
      WebSocket? serverSocket;
      final syncMessage = Completer<Map<String, dynamic>>();
      final stateMessage = Completer<Map<String, dynamic>>();
      try {
        final socketConnection = await client.connectPlaybackSocket(
          device: const PlaybackDeviceIdentity(
            id: '0123456789abcdef',
            name: 'Web player',
            platform: 'web',
          ),
          snapshot: null,
          claim: false,
        );
        connection = socketConnection;
        subscription = socketConnection.stream.listen((event) {
          final message = Map<String, dynamic>.from(event as Map);
          if (message['type'] == 'sync' && !syncMessage.isCompleted) {
            syncMessage.complete(message);
          }
          if (message['type'] == 'state' && !stateMessage.isCompleted) {
            stateMessage.complete(message);
          }
        });
        serverSocket = await serverSocketReady.future;
        expect(await registerFrame.future, {
          'device': {
            'deviceId': '0123456789abcdef',
            'name': 'Web player',
            'platform': 'web',
            'capabilities': const PlaybackCapabilities().toJson(),
            'visible': true,
          },
          'snapshot': null,
          'claim': false,
        });
        expect(socketConnection.initialMessage['crossInstance'], true);
        serverSocket.add(
          '42${jsonEncode([
            'playback:changed',
            {
              'serverTimestamp': DateTime.utc(2026).toIso8601String(),
              'positionMs': 1200,
              'isPlaying': true,
              'playbackEpoch': 3,
              'stateVersion': 8,
              'session': {
                'activeDeviceId': '0123456789abcdef',
                'trackIds': ['track-one'],
                'index': 0,
                'positionMs': 1200,
                'durationMs': 180000,
                'playing': true,
                'shuffle': false,
                'repeat': 'none',
                'title': 'Track one',
                'artist': 'Artist',
                'queueRevision': 1,
                'revision': 8,
                'stateVersion': 8,
                'playbackEpoch': 3,
                'updatedAt': DateTime.utc(2026).toIso8601String(),
              },
            },
          ])}',
        );
        final stateMessageValue = await stateMessage.future;
        expect(stateMessageValue['type'], 'state');
        expect(
          (stateMessageValue['result'] as Map)['session']['playbackEpoch'],
          3,
        );
        expect(
          stateMessageValue['clientResponseReceivedAtMonotonicMicros'],
          isA<int>(),
        );

        socketConnection.sendHeartbeat(
          const PlaybackSnapshot(
            trackIds: ['track-one'],
            index: 0,
            positionMs: 1200,
            durationMs: 180000,
            playing: true,
            shuffle: false,
            repeat: 'none',
            title: 'Track one',
            artist: 'Artist',
          ),
        );
        expect((await heartbeatFrame.future)['snapshot'], {
          'trackIds': ['track-one'],
          'index': 0,
          'positionMs': 1200,
          'durationMs': 180000,
          'playing': true,
          'shuffle': false,
          'repeat': 'none',
          'title': 'Track one',
          'artist': 'Artist',
          'volume': 1,
        });
        expect((await syncMessage.future)['type'], 'sync');
        await socketConnection.sendHeartbeatAndWait(
          const PlaybackSnapshot(
            trackIds: ['track-one'],
            index: 0,
            positionMs: 45000,
            durationMs: 180000,
            playing: false,
            shuffle: false,
            repeat: 'none',
            title: 'Track one',
            artist: 'Artist',
          ),
        );
        expect((await handoffCheckpointFrame.future)['snapshot'], {
          'trackIds': ['track-one'],
          'index': 0,
          'positionMs': 45000,
          'durationMs': 180000,
          'playing': false,
          'shuffle': false,
          'repeat': 'none',
          'title': 'Track one',
          'artist': 'Artist',
          'volume': 1,
        });
        final acknowledgment = await socketConnection
            .acknowledgePlaybackCommand(
              commandId: 'handoff-command',
              succeeded: true,
            );
        expect(acknowledgment['transferStatus'], 'completed');
      } finally {
        await subscription?.cancel();
        await connection?.close();
        await serverSocket?.close();
        await server.close(force: true);
        client.dispose();
      }
    },
  );

  test('playback poll sends device identity and a complete snapshot', () async {
    late http.Request request;
    final client = DriveBridgeClient(
      baseUrl: 'https://example.com',
      token: 'session-token',
      client: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'session': {
              'activeDeviceId': '0123456789abcdef',
              'trackIds': ['track-one'],
              'index': 0,
              'positionMs': 1200,
              'durationMs': 240000,
              'playing': true,
              'shuffle': false,
              'repeat': 'none',
              'title': 'Track one',
              'artist': 'Artist',
              'queueRevision': 1,
            },
            'devices': [
              {
                'deviceId': '0123456789abcdef',
                'name': 'Android device',
                'platform': 'android',
                'online': true,
              },
            ],
            'commands': [],
          }),
          200,
        );
      }),
    );

    final result = await client.pollPlayback(
      device: const PlaybackDeviceIdentity(
        id: '0123456789abcdef',
        name: 'Android device',
        platform: 'android',
      ),
      snapshot: const PlaybackSnapshot(
        trackIds: ['track-one'],
        index: 0,
        positionMs: 1200,
        durationMs: 240000,
        playing: true,
        shuffle: false,
        repeat: 'none',
        title: 'Track one',
        artist: 'Artist',
      ),
      claim: true,
    );

    expect(request.url.path, '/api/v1/playback/poll');
    expect(request.headers['authorization'], 'Bearer session-token');
    expect(jsonDecode(request.body), {
      'deviceId': '0123456789abcdef',
      'name': 'Android device',
      'platform': 'android',
      'capabilities': {
        'playback': true,
        'pause': true,
        'seek': true,
        'volume': true,
        'queue': true,
      },
      'visible': true,
      'claim': true,
      'snapshot': {
        'trackIds': ['track-one'],
        'index': 0,
        'positionMs': 1200,
        'durationMs': 240000,
        'playing': true,
        'shuffle': false,
        'repeat': 'none',
        'title': 'Track one',
        'artist': 'Artist',
        'volume': 1,
      },
    });
    expect(result.session?.activeDeviceId, '0123456789abcdef');
    expect(result.session?.currentPosition, const Duration(milliseconds: 1200));
    expect(result.devices.single.online, isTrue);
    client.dispose();
  });

  test(
    'playback poll can heartbeat without a snapshot during remote work',
    () async {
      late http.Request request;
      final client = DriveBridgeClient(
        baseUrl: 'https://example.com',
        token: 'session-token',
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            jsonEncode({'session': null, 'devices': [], 'commands': []}),
            200,
          );
        }),
      );

      await client.pollPlayback(
        device: const PlaybackDeviceIdentity(
          id: '0123456789abcdef',
          name: 'Android device',
          platform: 'android',
        ),
        snapshot: null,
        claim: false,
      );

      expect(jsonDecode(request.body)['snapshot'], isNull);
      client.dispose();
    },
  );

  test(
    'handoff commands and track resolution use playback API contracts',
    () async {
      final requests = <http.Request>[];
      final client = DriveBridgeClient(
        baseUrl: 'https://example.com',
        token: 'session-token',
        client: MockClient((incoming) async {
          requests.add(incoming);
          if (incoming.url.path == '/api/v1/catalog/tracks/resolve') {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 'track-one',
                    'name': 'Track one.flac',
                    'streamUrl': 'https://example.com/stream/ticket',
                  },
                ],
              }),
              200,
            );
          }
          if (incoming.url.path == '/api/v1/playback/handoff') {
            return http.Response(
              jsonEncode({'transferId': 'transfer-id', 'status': 'pending'}),
              202,
            );
          }
          if (incoming.url.path == '/api/v1/playback/transfers/transfer-id') {
            return http.Response(
              jsonEncode({'transferId': 'transfer-id', 'status': 'completed'}),
              200,
            );
          }
          if (incoming.url.path == '/api/v1/playback/commands' &&
              incoming.method == 'POST') {
            return http.Response(jsonEncode({'commandId': 'command-id'}), 202);
          }
          if (incoming.url.path == '/api/v1/playback/commands/command-id' &&
              incoming.method == 'GET') {
            return http.Response(
              jsonEncode({'commandId': 'command-id', 'status': 'ok'}),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      final transfer = await client.handoffPlayback('0123456789abcdef');
      final transferStatus = await client.playbackTransfer(transfer.id!);
      final commandId = await client.sendPlaybackCommand(
        'seek',
        payload: {'positionMs': 9000},
      );
      final commandStatus = await client.playbackCommandStatus(commandId);
      await client.cancelPlaybackCommand(commandId);
      await client.renamePlaybackDevice('0123456789abcdef', 'Office PC');
      await client.setPlaybackDeviceVisibility(
        '0123456789abcdef',
        visible: false,
      );
      await client.disconnectPlaybackDevice('0123456789abcdef');
      await client.forgetPlaybackDevice('0123456789abcdef');
      final tracks = await client.catalogTracksByIds(['track-one']);

      expect(requests.map((request) => request.url.path), [
        '/api/v1/playback/handoff',
        '/api/v1/playback/transfers/transfer-id',
        '/api/v1/playback/commands',
        '/api/v1/playback/commands/command-id',
        '/api/v1/playback/commands/command-id',
        '/api/v1/playback/devices/0123456789abcdef',
        '/api/v1/playback/devices/0123456789abcdef',
        '/api/v1/playback/devices/0123456789abcdef/disconnect',
        '/api/v1/playback/devices/0123456789abcdef',
        '/api/v1/catalog/tracks/resolve',
      ]);
      expect(transfer.status, 'pending');
      expect(transferStatus.status, 'completed');
      expect(commandStatus.status, 'ok');
      expect(jsonDecode(requests[0].body), {'deviceId': '0123456789abcdef'});
      expect(jsonDecode(requests[2].body), {
        'action': 'seek',
        'payload': {'positionMs': 9000},
      });
      expect(jsonDecode(requests[5].body), {'name': 'Office PC'});
      expect(jsonDecode(requests[6].body), {'visible': false});
      expect(jsonDecode(requests[7].body), {'deviceId': '0123456789abcdef'});
      expect(jsonDecode(requests[9].body), {
        'trackIds': ['track-one'],
      });
      expect(tracks.single.id, 'track-one');
      client.dispose();
    },
  );
}
