import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../state/download_controller.dart';
import '../state/library_controller.dart';
import '../widgets/cover_image.dart';
import '../widgets/music_empty_state.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final controller = ref.read(downloadsProvider.notifier);
    final items = downloads.items.values.toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: !controller.supported
          ? const _DownloadsUnavailable()
          : items.isEmpty &&
                downloads.progress.isEmpty &&
                downloads.pausedTracks.isEmpty &&
                downloads.errors.isEmpty
          ? const _DownloadsEmpty()
          : ListView(
              children: [
                for (final entry in items)
                  ListTile(
                    leading: CoverImage(track: entry.track, size: 48),
                    title: Text(
                      entry.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${entry.track.artist ?? 'Unknown artist'} · ${_sizeLabel(entry.size)}',
                    ),
                    onTap: () => ref.read(audioHandlerProvider).playTracks([
                      entry.track,
                    ], 0),
                    trailing: IconButton(
                      tooltip: 'Remove download',
                      icon: const Icon(Icons.download_done_rounded),
                      onPressed: () => controller.remove(entry.track.id),
                    ),
                  ),
                for (final id in downloads.progress.keys)
                  ListTile(
                    leading: SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: downloads.progress[id],
                      ),
                    ),
                    title: Text(
                      controller.activeTrack(id)?.title ?? 'Downloading track',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Downloading…'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Pause download',
                          icon: const Icon(Icons.pause_circle_outline),
                          onPressed: () => controller.pause(id),
                        ),
                        IconButton(
                          tooltip: 'Cancel download',
                          icon: const Icon(Icons.close),
                          onPressed: () => controller.cancel(id),
                        ),
                      ],
                    ),
                  ),
                for (final entry in downloads.pausedTracks.entries)
                  ListTile(
                    leading: const Icon(Icons.pause_circle_outline),
                    title: Text(
                      entry.value.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text('Paused · ready to resume'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Resume download',
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () async {
                            try {
                              final fresh = await ref
                                  .read(libraryProvider.notifier)
                                  .refreshTrack(entry.key);
                              await controller.download(fresh ?? entry.value);
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not refresh the stream URL: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Cancel download',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => controller.cancel(entry.key),
                        ),
                      ],
                    ),
                  ),
                for (final failure in downloads.errors.entries)
                  ListTile(
                    leading: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.orange,
                    ),
                    title: Text(
                      downloads.failedTracks[failure.key]?.title ??
                          'Download failed',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      failure.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Retry download',
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () async {
                            try {
                              final fresh = await ref
                                  .read(libraryProvider.notifier)
                                  .refreshTrack(failure.key);
                              final track =
                                  fresh ?? downloads.failedTracks[failure.key];
                              if (track != null) {
                                await controller.download(track);
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not refresh the stream URL: $error',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Dismiss error',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => controller.clearError(failure.key),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  String _sizeLabel(int size) => size < 1024 * 1024
      ? '${(size / 1024).toStringAsFixed(0)} KB'
      : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DownloadsUnavailable extends StatelessWidget {
  const _DownloadsUnavailable();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Offline downloads are unavailable on this platform.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Use the Android, iOS, Windows, or desktop app to keep music on this device.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _DownloadsEmpty extends StatelessWidget {
  const _DownloadsEmpty();
  @override
  Widget build(BuildContext context) => const MusicEmptyState(
    icon: Icons.download_for_offline_outlined,
    title: 'No downloads yet',
    description: 'Download songs from the menu to play them offline.',
  );
}
