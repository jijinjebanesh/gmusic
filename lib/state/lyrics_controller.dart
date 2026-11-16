import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';

final trackLyricsProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  trackId,
) {
  final settings = ref.read(settingsControllerProvider.notifier);
  return settings.client().trackLyrics(trackId);
});
