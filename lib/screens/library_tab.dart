import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/settings_store.dart';
import '../state/library_controller.dart';
import '../state/download_controller.dart';
import '../widgets/track_tile.dart';
import '../widgets/music_empty_state.dart';
import 'catalog_screen.dart';
import 'downloads_screen.dart';
import 'playlists_screen.dart';
import 'saved_collections_screen.dart';

class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogTracks =
        ref.watch(visibleTracksProvider).valueOrNull ?? const <Track>[];
    final downloads = ref.watch(downloadsProvider).items;
    final tracks = catalogTracks
        .map((track) => downloads[track.id]?.track ?? track)
        .toList();
    final recentTracks = tracks.take(10).toList();
    final favorites = ref.watch(favoritesControllerProvider);
    final ui = ref.watch(playerUiProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your library'),
        actions: [
          IconButton(
            tooltip: 'All songs',
            icon: const Icon(Icons.music_note_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CatalogScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Downloads',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Saved music',
            icon: const Icon(Icons.bookmark_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SavedCollectionsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Playlists',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PlaylistsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(
              context: context,
              delegate: _TrackSearch(tracks, handler),
            ),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? MusicEmptyState(
              icon: Icons.library_music_outlined,
              title: 'Your library is waiting for music',
              description: 'Browse the full catalog to find a song to play.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CatalogScreen(),
                  ),
                ),
                child: const Text('Browse all songs'),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _collection(
                            context,
                            'Liked songs',
                            '${favorites.length} tracks',
                            Icons.favorite_rounded,
                            const Color(0xFF596CC0),
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const LikedSongsScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _collection(
                            context,
                            'All tracks',
                            '${tracks.length}${ref.watch(libraryProvider).valueOrNull?.nextPageToken == null ? '' : '+'} tracks loaded',
                            Icons.library_music_rounded,
                            Theme.of(context).colorScheme.primary,
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const CatalogScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Recently added',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: recentTracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: recentTracks[i],
                    isCurrent: ui?.track?.id == recentTracks[i].id,
                    isPlaying: ui?.playing ?? false,
                    onTap: () => handler.playTracks(tracks, i),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CatalogScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text('Browse the full catalog'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static Widget _collection(
    BuildContext context,
    String title,
    String detail,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 82,
        child: Row(
          children: [
            Container(
              width: 56,
              height: 82,
              color: color.withValues(alpha: .28),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(favoritesControllerProvider);
    final catalogTracks =
        ref
            .watch(libraryProvider)
            .valueOrNull
            ?.tracks
            .where((t) => ids.contains(t.id))
            .toList() ??
        const <Track>[];
    final downloads = ref.watch(downloadsProvider).items;
    final tracks = catalogTracks
        .map((track) => downloads[track.id]?.track ?? track)
        .toList();
    final handler = ref.read(audioHandlerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Liked songs')),
      body: tracks.isEmpty
          ? const MusicEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Songs you like show up here',
              description: 'Tap the heart next to any song to add it.',
            )
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackTile(
                track: tracks[i],
                isCurrent: false,
                isPlaying: false,
                onTap: () => handler.playTracks(tracks, i),
              ),
            ),
    );
  }
}

class _TrackSearch extends SearchDelegate<Track?> {
  _TrackSearch(this.tracks, this.handler);
  final List<Track> tracks;
  final GMusicAudioHandler handler;
  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  Widget _results(BuildContext context) {
    final q = query.toLowerCase();
    final filtered = tracks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              (t.artist ?? '').toLowerCase().contains(q),
        )
        .toList();
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, i) => TrackTile(
        track: filtered[i],
        isCurrent: false,
        isPlaying: false,
        onTap: () {
          handler.playTracks(filtered, i);
          close(context, filtered[i]);
        },
      ),
    );
  }
}
