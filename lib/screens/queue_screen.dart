import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../state/playback_sync_controller.dart';
import '../widgets/queue_list_panel.dart';

/// Queue tab: reorderable playback queue with the current track highlighted.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(playerUiProvider).valueOrNull;
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final hasTracks = remoteState.remoteTargeted
        ? remoteState.remoteQueue.isNotEmpty
        : ui?.queue.isNotEmpty ?? false;
    final handler = ref.read(audioHandlerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'QUEUE',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
        actions: [
          if (hasTracks)
            TextButton(
              onPressed: handler.clearQueue,
              child: const Text('Clear'),
            ),
        ],
      ),
      body: const QueueListPanel(),
    );
  }
}
