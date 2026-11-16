import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';
import '../state/library_controller.dart';
import '../state/download_controller.dart';
import '../widgets/cover_image.dart';
import '../widgets/music_empty_state.dart';
import '../widgets/track_tile.dart';

class ExploreTab extends ConsumerStatefulWidget {
  const ExploreTab({super.key, required this.onPlay, this.initialTab = 0});
  final void Function(List<Track>, int) onPlay;
  final int initialTab;

  @override
  ConsumerState<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<ExploreTab> {
  Future<CatalogEntityPage>? _artists;
  Future<CatalogEntityPage>? _albums;
  Future<List<CatalogEntity>>? _genres;

  @override
  Widget build(BuildContext context) {
    final catalogAvailable =
        ref.watch(libraryProvider).valueOrNull?.catalogAvailable ?? false;
    if (catalogAvailable && _artists == null) {
      final controller = ref.read(libraryProvider.notifier);
      _artists = controller.catalogArtists();
      _albums = controller.catalogAlbums();
      _genres = controller.catalogGenres();
    }
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Explore'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Artists'),
              Tab(text: 'Albums'),
              Tab(text: 'Genres'),
            ],
          ),
        ),
        body: !catalogAvailable
            ? const MusicEmptyState(
                icon: Icons.library_music_outlined,
                title: 'Catalog not ready',
                description:
                    'Artist, album, and genre browsing will be available when the library is connected.',
              )
            : TabBarView(
                children: [
                  _entityList(_artists!, 'artist'),
                  _entityList(_albums!, 'album'),
                  _genreList(_genres!),
                ],
              ),
      ),
    );
  }

  Widget _entityList(Future<CatalogEntityPage> future, String kind) =>
      FutureBuilder<CatalogEntityPage>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: 'Could not load $kind list: ${snapshot.error}',
              onRetry: () => setState(() {
                final controller = ref.read(libraryProvider.notifier);
                if (kind == 'artist') {
                  _artists = controller.catalogArtists();
                } else {
                  _albums = controller.catalogAlbums();
                }
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!.items;
          if (items.isEmpty) return Center(child: Text('No $kind found yet.'));
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 3,
                ),
                leading: kind == 'artist'
                    ? CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: Icon(
                          Icons.person_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.album_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  kind == 'album' && item.artist != null
                      ? '${item.artist} · ${item.trackCount} tracks'
                      : '${item.trackCount} tracks',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCollection(item, kind),
              );
            },
          );
        },
      );

  Widget _genreList(Future<List<CatalogEntity>> future) =>
      FutureBuilder<List<CatalogEntity>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(
              message: 'Could not load genres: ${snapshot.error}',
              onRetry: () => setState(() {
                _genres = ref.read(libraryProvider.notifier).catalogGenres();
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No genres found yet.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final genre = items[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 3,
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(genre.name),
                subtitle: Text('${genre.trackCount} tracks'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCollection(genre, 'genre'),
              );
            },
          );
        },
      );

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
}

class CatalogCollectionScreen extends ConsumerStatefulWidget {
  const CatalogCollectionScreen({
    super.key,
    required this.entity,
    required this.kind,
    required this.onPlay,
  });

  final CatalogEntity entity;
  final String kind;
  final void Function(List<Track>, int) onPlay;

  @override
  ConsumerState<CatalogCollectionScreen> createState() =>
      _CatalogCollectionScreenState();
}

class _CatalogCollectionScreenState
    extends ConsumerState<CatalogCollectionScreen> {
  List<Track> _tracks = [];
  String? _nextPageToken;
  String? _error;
  bool _loading = false;
  bool _saved = false;
  bool _downloadingCollection = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    try {
      final client = ref.read(settingsControllerProvider.notifier).client();
      final entities = widget.kind == 'artist'
          ? await client.followedArtists()
          : widget.kind == 'album'
          ? await client.savedAlbums()
          : const <CatalogEntity>[];
      if (mounted) {
        setState(
          () => _saved = entities.any((item) => item.id == widget.entity.id),
        );
      }
    } catch (_) {
      // The detail remains browseable if personal-library sync is temporarily
      // unavailable; the explicit action below reports mutation failures.
    }
  }

  Future<void> _toggleSaved() async {
    final client = ref.read(settingsControllerProvider.notifier).client();
    final next = !_saved;
    setState(() => _saved = next);
    try {
      if (widget.kind == 'artist') {
        if (next) {
          await client.followArtist(widget.entity);
        } else {
          await client.unfollowArtist(widget.entity.id);
        }
      } else {
        if (next) {
          await client.saveAlbum(widget.entity);
        } else {
          await client.unsaveAlbum(widget.entity.id);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next
                  ? (widget.kind == 'artist'
                        ? 'Artist followed'
                        : 'Album saved')
                  : (widget.kind == 'artist'
                        ? 'Artist unfollowed'
                        : 'Album removed from your library'),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saved = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update your library: $error')),
        );
      }
    }
  }

  Future<void> _downloadAlbum() async {
    setState(() => _downloadingCollection = true);
    try {
      final allTracks = <Track>[];
      String? token;
      do {
        final page = await ref
            .read(libraryProvider.notifier)
            .catalogEntityTracks(
              widget.kind,
              widget.entity.id,
              pageToken: token,
            );
        allTracks.addAll(page.files);
        token = page.nextPageToken;
      } while (token != null && mounted);
      if (!mounted) return;
      await ref.read(downloadsProvider.notifier).downloadAll(allTracks);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${allTracks.length} album tracks added to downloads',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download album: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingCollection = false);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(libraryProvider.notifier)
          .catalogEntityTracks(
            widget.kind,
            widget.entity.id,
            pageToken: reset ? null : _nextPageToken,
          );
      if (!mounted) return;
      setState(() {
        _tracks = reset ? page.files : [..._tracks, ...page.files];
        _nextPageToken = page.nextPageToken;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load tracks: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.entity.name),
      actions: [
        if (widget.kind == 'album')
          IconButton(
            tooltip: 'Download album',
            onPressed:
                _downloadingCollection ||
                    !ref.read(downloadsProvider.notifier).supported
                ? null
                : _downloadAlbum,
            icon: _downloadingCollection
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_for_offline_outlined),
          ),
        if (widget.kind == 'artist' || widget.kind == 'album')
          IconButton(
            tooltip: widget.kind == 'artist'
                ? (_saved ? 'Unfollow artist' : 'Follow artist')
                : (_saved ? 'Remove saved album' : 'Save album'),
            onPressed: _toggleSaved,
            icon: Icon(
              _saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: _saved ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
      ],
    ),
    body: _error != null && _tracks.isEmpty
        ? _LoadError(message: _error!, onRetry: () => _load(reset: true))
        : _tracks.isEmpty && _loading
        ? const Center(child: CircularProgressIndicator())
        : _tracks.isEmpty
        ? const MusicEmptyState(
            icon: Icons.music_off_rounded,
            title: 'No songs here yet',
            description: 'This collection has no playable tracks.',
          )
        : CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _collectionHero(context)),
              SliverList.builder(
                itemCount: _tracks.length + (_nextPageToken == null ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == _tracks.length) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _loading
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: _load,
                                child: const Text('Load more'),
                              ),
                      ),
                    );
                  }
                  final track = _tracks[index];
                  return TrackTile(
                    track: track,
                    isCurrent: false,
                    isPlaying: false,
                    onTap: () => widget.onPlay(_tracks, index),
                  );
                },
              ),
            ],
          ),
  );

  Widget _collectionHero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = _tracks.isEmpty
        ? Container(
            width: 184,
            height: 184,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(
                widget.kind == 'artist' ? 100 : 8,
              ),
            ),
            child: Icon(
              widget.kind == 'artist'
                  ? Icons.person_rounded
                  : Icons.album_rounded,
              size: 72,
              color: colors.onSurfaceVariant,
            ),
          )
        : ClipOval(
            clipBehavior: widget.kind == 'artist' ? Clip.antiAlias : Clip.none,
            child: CoverImage(
              track: _tracks.first,
              size: 184,
              radius: widget.kind == 'artist' ? 184 : 8,
            ),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        children: [
          image,
          const SizedBox(height: 18),
          Text(
            widget.entity.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
          ),
          const SizedBox(height: 6),
          Text(
            widget.kind == 'album'
                ? '${widget.entity.artist ?? 'Unknown artist'} · ${widget.entity.trackCount} songs'
                : '${widget.entity.trackCount} songs',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _tracks.isEmpty
                    ? null
                    : () => widget.onPlay(_tracks, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
              OutlinedButton.icon(
                onPressed: _tracks.isEmpty
                    ? null
                    : () {
                        unawaited(
                          ref
                              .read(audioHandlerProvider)
                              .setShuffleMode(AudioServiceShuffleMode.all),
                        );
                        widget.onPlay(_tracks, 0);
                      },
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
