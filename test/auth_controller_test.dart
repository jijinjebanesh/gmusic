import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gmusic/services/settings_store.dart';
import 'package:gmusic/state/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> createContainer(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bridge_url': 'https://bridge.example.test',
      'session_token': 'saved-session-token',
      'user_json': jsonEncode({
        'id': 'account-1',
        'email': 'listener@example.test',
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        apiHttpClientFactoryProvider.overrideWithValue(
          () => MockClient(handler),
        ),
      ],
    );
  }

  test(
    'transient session validation failure keeps the saved session',
    () async {
      final container = await createContainer(
        (_) async => http.Response('{"error":"mongo_unavailable"}', 503),
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).restoreSession();

      expect(
        container.read(settingsControllerProvider).sessionToken,
        'saved-session-token',
      );
      expect(container.read(settingsControllerProvider).user?.id, 'account-1');
      expect(
        container.read(authControllerProvider).error,
        contains('HTTP 503'),
      );
    },
  );

  test('an explicitly rejected session is cleared', () async {
    final container = await createContainer((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response('{"error":"session_expired"}', 401);
      }
      return http.Response('{"ok":true}', 200);
    });
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).restoreSession();

    expect(container.read(settingsControllerProvider).sessionToken, isEmpty);
    expect(container.read(settingsControllerProvider).user, isNull);
  });
}
