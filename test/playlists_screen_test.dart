import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gmusic/screens/playlists_screen.dart';
import 'package:gmusic/services/settings_store.dart';

void main() {
  testWidgets('creating a playlist closes the dialog and refreshes the list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bridge_url': 'https://example.com',
      'session_token': 'session-token',
    });
    final preferences = await SharedPreferences.getInstance();
    final playlists = <Map<String, dynamic>>[];
    final apiClient = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/v1/playlists') {
        return http.Response(jsonEncode({'playlists': playlists}), 200);
      }
      if (request.method == 'POST' && request.url.path == '/api/v1/playlists') {
        final playlist = {
          'id': 'playlist-1',
          'name': (jsonDecode(request.body) as Map<String, dynamic>)['name'],
          'description': '',
          'trackIds': <String>[],
        };
        playlists.add(playlist);
        return http.Response(jsonEncode({'playlist': playlist}), 201);
      }
      return http.Response('{}', 404);
    });
    addTearDown(apiClient.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          apiHttpClientFactoryProvider.overrideWithValue(() => apiClient),
        ],
        child: const MaterialApp(home: PlaylistsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Road trip');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(playlists, hasLength(1));
    expect(find.text('Road trip'), findsOneWidget);
  });
}
