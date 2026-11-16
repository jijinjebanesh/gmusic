import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';
import '../widgets/track_tile.dart';
import '../widgets/music_empty_state.dart';
import '../widgets/music_section_header.dart';
import 'explore_tab.dart';
import 'library_tab.dart';
import 'catalog_screen.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key, required this.onPlay});
  final void Function(List<Track>, int) onPlay;
  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHistoryEntry> _history = [];
  bool _historyLoading = true;
  String? _historyError;
  List<Track> _searchTracks = [];
  List<CatalogEntity> _searchArtists = [];
  List<CatalogEntity> _searchAlbums = [];
  bool _searching = false;
  String? _searchError;
  int _searchRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _searchRevision++;
      setState(() {
        _searchTracks = [];
        _searchArtists = [];
        _searchAlbums = [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _searchRevision++;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final revision = ++_searchRevision;
    try {
      final result = await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .searchCatalog(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searchTracks = _decodeSearchItems(
          result['tracks'],
          Track.fromJson,
          'tracks',
        );
        _searchArtists = _decodeSearchItems(
          result['artists'],
          CatalogEntity.fromJson,
          'artists',
        );
        _searchAlbums = _decodeSearchItems(
          result['albums'],
          CatalogEntity.fromJson,
          'albums',
        );
        _searching = false;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _searching = false;
        _searchError = 'Search failed: $error';
      });
    }
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    unawaited(_performSearch(query));
    unawaited(_record(query));
  }

  void _openCollection(CatalogEntity entity, String kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogCollectionScreen(
          entity: entity,
          kind: kind,
          onPlay: widget.onPlay,
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .searchHistory();
      if (mounted) {
        setState(() {
          _history = rows;
          _historyLoading = false;
          _historyError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _historyLoading = false;
          _historyError = 'Search history is unavailable: $error';
        });
      }
    }
  }

  Future<void> _record(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    try {
      final client = ref.read(settingsControllerProvider.notifier).client();
      await client.recordSearch(query);
      await _loadHistory();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Search worked, but could not save it to your history.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeHistory(String query) async {
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .removeSearch(query);
      await _loadHistory();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove search: $error')),
        );
      }
    }
  }

  Future<void> _clearHistory() async {
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .clearSearchHistory();
      if (mounted) setState(() => _history = []);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear history: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerUiProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final query = _controller.text.trim();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(pinned: true, title: Text('Search')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
              child: TextField(
                controller: _controller,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: 'Songs, artists, or albums',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                          },
                        ),
                ),
              ),
            ),
          ),
          if (query.isEmpty) ...[
            if (_history.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 8, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Recent searches',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: _clearHistory,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final entry = _history[index];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(entry.query),
                    trailing: IconButton(
                      tooltip: 'Remove search',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => _removeHistory(entry.query),
                    ),
                    onTap: () {
                      _controller.text = entry.query;
                      _controller.selection = TextSelection.collapsed(
                        offset: entry.query.length,
                      );
                      setState(() {});
                      _search(entry.query);
                      unawaited(_record(entry.query));
                    },
                  );
                },
              ),
            ] else if (_historyLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_historyError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    _historyError!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: MusicSectionHeader(
                title: 'Browse all',
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  _BrowseTile(
                    'Artists',
                    Icons.person_rounded,
                    const Color(0xFF704B78),
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ExploreTab(onPlay: widget.onPlay, initialTab: 0),
                      ),
                    ),
                  ),
                  _BrowseTile(
                    'Albums',
                    Icons.album_rounded,
                    const Color(0xFF9C6344),
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ExploreTab(onPlay: widget.onPlay, initialTab: 1),
                      ),
                    ),
                  ),
                  _BrowseTile(
                    'Genres',
                    Icons.graphic_eq_rounded,
                    const Color(0xFF267F83),
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ExploreTab(onPlay: widget.onPlay, initialTab: 2),
                      ),
                    ),
                  ),
                  _BrowseTile(
                    'Your music',
                    Icons.library_music_rounded,
                    const Color(0xFF175A35),
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LibraryTab(),
                      ),
                    ),
                  ),
                  _BrowseTile(
                    'All songs',
                    Icons.music_note_rounded,
                    const Color(0xFF3B5B48),
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CatalogScreen(),
                      ),
                    ),
                  ),
                ]),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 11,
                  crossAxisSpacing: 11,
                  childAspectRatio: 1.65,
                ),
              ),
            ),
          ] else if (_searching)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchError != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _searchError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => _submitSearch(query),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            )
          else if (_searchTracks.isEmpty &&
              _searchArtists.isEmpty &&
              _searchAlbums.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: MusicEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                description: 'Try another song, artist, or album.',
              ),
            )
          else ...[
            if (_searchArtists.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: MusicSectionHeader(
                  title: 'Artists',
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                ),
              ),
              SliverList.builder(
                itemCount: _searchArtists.length,
                itemBuilder: (context, index) {
                  final artist = _searchArtists[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 2,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: scheme.surfaceContainerHigh,
                      child: Icon(
                        Icons.person_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${artist.trackCount} songs'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openCollection(artist, 'artist'),
                  );
                },
              ),
            ],
            if (_searchAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: MusicSectionHeader(
                  title: 'Albums',
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                ),
              ),
              SliverList.builder(
                itemCount: _searchAlbums.length,
                itemBuilder: (context, index) {
                  final album = _searchAlbums[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.album_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${album.artist ?? 'Unknown artist'} · ${album.trackCount} songs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openCollection(album, 'album'),
                  );
                },
              ),
            ],
            if (_searchTracks.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: MusicSectionHeader(
                    title: 'Songs',
                    actionLabel: 'All songs',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CatalogScreen(),
                      ),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: _searchTracks.length,
                itemBuilder: (context, index) => TrackTile(
                  track: _searchTracks[index],
                  isCurrent: player?.track?.id == _searchTracks[index].id,
                  isPlaying: player?.playing ?? false,
                  onTap: () {
                    unawaited(_record(query));
                    widget.onPlay(_searchTracks, index);
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

List<T> _decodeSearchItems<T>(
  Object? value,
  T Function(Map<String, dynamic>) decode,
  String key,
) {
  if (value is! List) {
    throw FormatException('Expected a $key list in search response');
  }
  return value.map((item) {
    if (item is! Map) {
      throw FormatException('Expected a $key item to be an object');
    }
    return decode(Map<String, dynamic>.from(item));
  }).toList();
}

class _BrowseTile extends StatelessWidget {
  const _BrowseTile(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -12,
            bottom: -17,
            child: Transform.rotate(
              angle: .3,
              child: Icon(
                icon,
                size: 92,
                color: Colors.white.withValues(alpha: .15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
