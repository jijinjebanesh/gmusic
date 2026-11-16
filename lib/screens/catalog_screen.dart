import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/audio_handler.dart';
import '../state/download_controller.dart';
import '../state/library_controller.dart';
import '../widgets/track_tile.dart';

/// The full Drive catalog lives here instead of dominating the Home feed.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    final library = ref.read(libraryProvider).valueOrNull;
    if (library != null && library.query.isNotEmpty) {
      unawaited(ref.read(libraryProvider.notifier).search(''));
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(libraryProvider.notifier).search(query.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).valueOrNull;
    final tracks = library?.tracks ?? const [];
    final downloads = ref.watch(downloadsProvider).items;
    final ui = ref.watch(playerUiProvider).valueOrNull;
    final handler = ref.read(audioHandlerProvider);
    final loading = library?.loading ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All songs'),
        actions: [
          if (tracks.isNotEmpty)
            IconButton(
              tooltip: 'Shuffle all tracks',
              onPressed: () {
                unawaited(handler.setShuffleMode(AudioServiceShuffleMode.all));
                handler.playTracks(tracks, 0);
              },
              icon: const Icon(Icons.shuffle_rounded),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Find a song in your library',
              leading: const Icon(Icons.search_rounded),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchController.clear();
                      _search('');
                      setState(() {});
                    },
                  ),
              ],
              onChanged: (value) {
                _search(value);
                setState(() {});
              },
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(libraryProvider.notifier).load(),
        child: tracks.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 150),
                  Icon(
                    library?.error == null
                        ? Icons.library_music_outlined
                        : Icons.cloud_off_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      loading
                          ? 'Loading your music…'
                          : library?.error ?? 'No tracks found.',
                    ),
                  ),
                  if (!loading && library?.error != null)
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            ref.read(libraryProvider.notifier).load(),
                        child: const Text('Try again'),
                      ),
                    ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 28),
                itemCount:
                    tracks.length + (library?.nextPageToken == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == tracks.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: loading
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: () => ref
                                    .read(libraryProvider.notifier)
                                    .loadMore(),
                                child: const Text('Load more'),
                              ),
                      ),
                    );
                  }
                  final sourceTrack = tracks[index];
                  final track = downloads[sourceTrack.id]?.track ?? sourceTrack;
                  return TrackTile(
                    track: track,
                    isCurrent: ui?.track?.id == track.id,
                    isPlaying: ui?.playing ?? false,
                    onTap: () => handler.playTracks(
                      tracks
                          .map((item) => downloads[item.id]?.track ?? item)
                          .toList(),
                      index,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
