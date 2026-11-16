import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../models/user.dart';
import '../services/settings_store.dart';

/// Recently played tracks per user (Atlas `recent_plays`), newest first.
/// The list is optimistic: a play appears immediately and is mirrored to the
/// bridge in the background.
class RecentController extends StateNotifier<List<RecentEntry>> {
  RecentController(this._ref) : super(const []);

  final Ref _ref; // ignore: avoid_dynamic_calls

  Future<void> load() async {
    try {
      final entries = await _ref.read(settingsControllerProvider.notifier).client().recent();
      state = entries;
    } on Object {
      // Keep whatever is already shown.
    }
  }

  Future<void> record(Track track) async {
    final entry = RecentEntry(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      playedAt: DateTime.now(),
    );
    state = [entry, ...state.where((e) => e.trackId != track.id)];
    try {
      await _ref.read(settingsControllerProvider.notifier).client().recordRecent(track);
    } on Object {
      // Played while the bridge was unreachable; it re-syncs next time.
    }
  }
}

final recentControllerProvider = StateNotifierProvider<RecentController, List<RecentEntry>>(RecentController.new);
