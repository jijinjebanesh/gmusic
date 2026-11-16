import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'services/audio_handler.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final handler = await AudioService.init<GMusicAudioHandler>(
    builder: GMusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelName: 'GMusic playback',
      androidNotificationChannelDescription:
          'Controls for tracks playing from your Google Drive',
      androidNotificationOngoing: true,
    ),
  );
  await handler.configureAudioSession();
  await handler.restoreQueue(prefs);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioHandlerProvider.overrideWithValue(handler),
      ],
      child: const GMusicApp(),
    ),
  );
}
