import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/setup_screen.dart';
import 'state/playback_sync_controller.dart';
import 'services/settings_store.dart';
import 'theme/app_theme.dart';

class GMusicApp extends ConsumerWidget {
  const GMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(playbackSyncControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final Widget home;
    if (settings.bridgeUrl.trim().isEmpty) {
      home = const SetupScreen();
    } else if (!settings.configured) {
      home = const LoginScreen();
    } else {
      home = const AppShell();
    }
    return MaterialApp(
      title: 'GMusic',
      debugShowCheckedModeBanner: false,
      theme: GMusicTheme.light(),
      darkTheme: GMusicTheme.dark(),
      themeMode: settings.themeMode,
      home: home,
    );
  }
}
