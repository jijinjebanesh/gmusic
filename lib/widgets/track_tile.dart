import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/settings_store.dart';
import 'cover_image.dart';

/// One row of the library. Highlights the playing track, exposes favorite and
/// queue actions, and starts playback from the tapped row onward.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    this.trailing,
    this.onTap,
    this.showArtwork = true,
    this.showFavorite = true,
    this.showQueueActions = true,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArtwork;
  final bool showFavorite;
  final bool showQueueActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final favorite =
        showFavorite &&
        ref.watch(favoritesControllerProvider).contains(track.id);
    final artist = track.artist;
    final details = [
      if (artist?.isNotEmpty == true) artist!,
      if (track.album?.trim().isNotEmpty == true) track.album!.trim(),
    ];
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 1),
      leading: showArtwork
          ? Stack(
              children: [
                CoverImage(track: track, size: 50, radius: 8),
                if (isCurrent)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isPlaying ? Icons.graphic_eq : Icons.pause,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            )
          : null,
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: isCurrent ? scheme.primary : null,
        ),
      ),
      subtitle: Text(
        details.isEmpty ? 'In your collection' : details.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: showFavorite || showQueueActions || trailing != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showFavorite)
                  IconButton(
                    tooltip: favorite
                        ? 'Remove from liked songs'
                        : 'Add to liked songs',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                      color: favorite
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      size: 21,
                    ),
                    onPressed: () async {
                      final favorites = ref.read(
                        favoritesControllerProvider.notifier,
                      );
                      final settings = ref.read(
                        settingsControllerProvider.notifier,
                      );
                      final added = !favorite;
                      await favorites.toggle(track.id);
                      final synced = await syncFavoriteRemote(
                        favorites: favorites,
                        settings: settings,
                        added: added,
                        track: track,
                      );
                      if (!synced && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Favorite saved on this device. Sync will retry.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                if (showQueueActions)
                  PopupMenuButton<String>(
                    tooltip: 'Queue options',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      final handler = ref.read(audioHandlerProvider);
                      final wasEmpty =
                          ref
                              .read(playerUiProvider)
                              .valueOrNull
                              ?.queue
                              .isEmpty ??
                          true;
                      if (action == 'next') {
                        handler.addNext(track);
                      } else {
                        handler.addLast(track);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              wasEmpty
                                  ? 'Playing now'
                                  : action == 'next'
                                  ? 'Added to play next'
                                  : 'Added to queue',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'next',
                        child: ListTile(
                          leading: Icon(Icons.playlist_play_rounded),
                          title: Text('Play next'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'queue',
                        child: ListTile(
                          leading: Icon(Icons.queue_music_rounded),
                          title: Text('Add to queue'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ?trailing,
              ],
            )
          : null,
    );
  }
}
