import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../services/settings_store.dart';
import '../state/playback_sync_controller.dart';
import '../screens/now_playing_screen.dart';
import 'cover_image.dart';

/// The always-visible bar above the navigation bar: tap or drag opens the full
/// player with play/pause and like actions one tap away.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(playerUiProvider).valueOrNull;
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final remoteSession = remoteState.remoteTargeted
        ? remoteState.session
        : null;
    final track = remoteSession == null
        ? ui?.track
        : remoteState.remoteCurrentTrack ?? remoteSession.trackPlaceholder;
    if (track == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final handler = ref.read(audioHandlerProvider);
    final playing = remoteSession?.playing ?? ui?.playing ?? false;
    final favorite = ref.watch(favoritesControllerProvider).contains(track.id);
    final localPosition =
        ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final localDuration = ref.watch(playbackDurationProvider).valueOrNull;
    final position = remoteSession?.currentPosition ?? localPosition;
    final duration = remoteSession == null
        ? localDuration
        : remoteSession.durationMs > 0
        ? Duration(milliseconds: remoteSession.durationMs)
        : track.duration;
    final progress =
        (duration != null && duration > Duration.zero && position < duration)
        ? position.inMilliseconds / duration.inMilliseconds
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => Navigator.of(context).push(NowPlayingRoute()),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  Hero(
                    tag: 'gmusic-art-${track.id}',
                    child: CoverImage(track: track, size: 42, radius: 7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist ?? 'Unknown artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Favorite',
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                      color: favorite ? scheme.primary : null,
                    ),
                    onPressed: remoteSession != null
                        ? null
                        : () async {
                            final favoriteController = ref.read(
                              favoritesControllerProvider.notifier,
                            );
                            final settingsController = ref.read(
                              settingsControllerProvider.notifier,
                            );
                            final added = !favorite;
                            await favoriteController.toggle(track.id);
                            final synced = await syncFavoriteRemote(
                              favorites: favoriteController,
                              settings: settingsController,
                              added: added,
                              track: track,
                            );
                            if (!synced && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Favorite saved on this device; sync will retry.',
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: playing ? 'Pause' : 'Play',
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    onPressed: handler.togglePlayPause,
                  ),
                ],
              ),
            ),
          ),
          if (progress != null)
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2,
            ),
        ],
      ),
    );
  }
}
