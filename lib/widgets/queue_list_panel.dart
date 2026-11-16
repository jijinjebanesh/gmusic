import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../state/playback_sync_controller.dart';
import 'cover_image.dart';

class QueueListPanel extends ConsumerStatefulWidget {
  const QueueListPanel({
    super.key,
    this.scrollController,
    this.onTrackSelected,
  });

  final ScrollController? scrollController;
  final ValueChanged<int>? onTrackSelected;

  @override
  ConsumerState<QueueListPanel> createState() => _QueueListPanelState();
}

class _QueueListPanelState extends ConsumerState<QueueListPanel> {
  static const double _rowHeight = 72;
  final ScrollController _ownedController = ScrollController();
  int? _lastScrolledIndex;

  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerUiProvider).valueOrNull;
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final remoteSession = remoteState.remoteTargeted
        ? remoteState.session
        : null;
    final queue = remoteSession == null
        ? ui?.queue ?? const <Track>[]
        : remoteState.remoteQueue;
    final currentIndex = remoteSession?.index ?? ui?.index ?? 0;
    final isPlaying = remoteSession?.playing ?? ui?.playing ?? false;
    final shuffle = remoteSession?.shuffle ?? ui?.shuffle ?? false;
    final repeat = remoteSession == null
        ? ui?.repeat ?? AudioServiceRepeatMode.none
        : switch (remoteSession.repeat) {
            'one' => AudioServiceRepeatMode.one,
            'all' => AudioServiceRepeatMode.all,
            _ => AudioServiceRepeatMode.none,
          };
    final controller = widget.scrollController ?? _ownedController;
    final handler = ref.read(audioHandlerProvider);
    final colors = Theme.of(context).colorScheme;

    if (queue.isNotEmpty && _lastScrolledIndex != currentIndex) {
      _lastScrolledIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !controller.hasClients) return;
        final target = (currentIndex * _rowHeight)
            .clamp(0.0, controller.position.maxScrollExtent)
            .toDouble();
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Up next',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      remoteSession != null && remoteState.remoteQueueLoading
                          ? 'Syncing queue…'
                          : '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: shuffle ? 'Turn shuffle off' : 'Shuffle',
                isSelected: shuffle,
                onPressed: () => handler.setShuffleMode(
                  shuffle
                      ? AudioServiceShuffleMode.none
                      : AudioServiceShuffleMode.all,
                ),
                icon: const Icon(Icons.shuffle_rounded),
              ),
              IconButton(
                tooltip: switch (repeat) {
                  AudioServiceRepeatMode.one => 'Repeat one',
                  AudioServiceRepeatMode.all => 'Repeat all',
                  _ => 'Repeat off',
                },
                isSelected: repeat != AudioServiceRepeatMode.none,
                onPressed: () => handler.setRepeatMode(switch (repeat) {
                  AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
                  AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
                  _ => AudioServiceRepeatMode.none,
                }),
                icon: Icon(
                  repeat == AudioServiceRepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                ),
              ),
            ],
          ),
        ),
        if (queue.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                remoteSession != null && remoteState.remoteQueueLoading
                    ? 'Syncing queue…'
                    : remoteSession != null
                    ? remoteState.remoteQueueError ?? 'Your queue is empty'
                    : 'Your queue is empty',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              scrollController: controller,
              buildDefaultDragHandles: false,
              itemExtent: _rowHeight,
              itemCount: queue.length,
              onReorderItem: handler.reorderQueue,
              itemBuilder: (context, index) {
                final track = queue[index];
                final isCurrent = currentIndex == index;
                final key = ValueKey(_queueEntryKey(queue, index));
                final row = _QueueRow(
                  key: key,
                  track: track,
                  isCurrent: isCurrent,
                  isPlaying: isPlaying,
                  onTap: () {
                    handler.playQueueItem(index);
                    widget.onTrackSelected?.call(index);
                  },
                  onRemove: isCurrent ? null : () => handler.removeAt(index),
                  dragHandle: ReorderableDelayedDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                );
                if (isCurrent) return row;
                return Dismissible(
                  key: ValueKey('dismiss-${key.value}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: colors.errorContainer,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  onDismissed: (_) => handler.removeAt(index),
                  child: row,
                );
              },
            ),
          ),
      ],
    );
  }

  String _queueEntryKey(List<Track> queue, int index) {
    final track = queue[index];
    final occurrence = queue
        .take(index)
        .where((queuedTrack) => queuedTrack.id == track.id)
        .length;
    return '${track.id}:$occurrence';
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onRemove,
    required this.dragHandle,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Stack(
        children: [
          CoverImage(track: track, size: 48, radius: 7),
          if (isCurrent)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? colors.primary : null,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        track.artist?.trim().isNotEmpty == true
            ? track.artist!
            : 'Unknown artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from queue',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: onRemove,
            ),
          dragHandle,
        ],
      ),
    );
  }
}
