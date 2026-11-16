import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/models/playback.dart';
import 'package:gmusic/services/audio_handler.dart';
import 'package:gmusic/services/drive_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'audio handler accepts Socket.IO registration maps in realtime sync',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serverSocketReady = Completer<WebSocket>();
      WebSocket? serverSocket;
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        serverSocket = socket;
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
            socket.add('40{"sid":"socket-session"}');
            return;
          }
          if (!frame.startsWith('42')) return;
          final payloadStart = frame.indexOf('[');
          final acknowledgementId = frame.substring(2, payloadStart);
          socket.add(
            '43$acknowledgementId${jsonEncode([
              {
                'ok': true,
                'crossInstance': true,
                'result': {'session': null, 'devices': [], 'commands': []},
              },
            ])}',
          );
        });
      });

      final client = DriveBridgeClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'session-token',
      );
      final handler = GMusicAudioHandler();
      const identity = PlaybackDeviceIdentity(
        id: '0123456789abcdef',
        name: 'Web player',
        platform: 'web',
      );
      final synced = handler.remoteStateStream.firstWhere(
        (state) => state.deviceId == identity.id && !state.syncing,
      );

      try {
        handler.configureRemoteSync(
          client: client,
          identity: identity,
          userId: 'user-id',
        );
        final state = await synced.timeout(const Duration(seconds: 5));

        expect(state.error, isNull);
        expect(state.devices, isEmpty);
        await serverSocketReady.future;
      } finally {
        handler.disableRemoteSync();
        handler.dispose();
        client.dispose();
        await serverSocket?.close();
        await server.close(force: true);
      }
    },
  );
}
