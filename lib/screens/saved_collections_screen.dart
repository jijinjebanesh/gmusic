import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';
import '../state/download_controller.dart';
import 'explore_tab.dart';
import '../widgets/music_empty_state.dart';

class SavedCollectionsScreen extends ConsumerStatefulWidget {
  const SavedCollectionsScreen({super.key});
  @override
  ConsumerState<SavedCollectionsScreen> createState() =>
      _SavedCollectionsScreenState();
}

class _SavedCollectionsScreenState
    extends ConsumerState<SavedCollectionsScreen> {
  List<CatalogEntity> _artists = [];
  List<CatalogEntity> _albums = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(settingsControllerProvider.notifier).client();
      final results = await Future.wait([
        client.followedArtists(),
        client.savedAlbums(),
      ]);
      if (mounted) {
        setState(() {
          _artists = results[0];
          _albums = results[1];
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your saved music: $error';
          _loading = false;
        });
      }
    }
  }

  void _play(List<Track> tracks, int index) {
    final downloads = ref.read(downloadsProvider).items;
    final playable = tracks
        .map((track) => downloads[track.id]?.track ?? track)
        .toList();
    ref.read(audioHandlerProvider).playTracks(playable, index);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Saved music'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Artists'),
            Tab(text: 'Albums'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && _artists.isEmpty && _albums.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _artists.isEmpty && _albums.isEmpty
          ? _SavedError(message: _error!, onRetry: _load)
          : TabBarView(
              children: [_list(_artists, 'artist'), _list(_albums, 'album')],
            ),
    ),
  );

  Widget _list(List<CatalogEntity> entities, String kind) => RefreshIndicator(
    onRefresh: _load,
    child: entities.isEmpty
        ? ListView(
            children: [
              const SizedBox(height: 80),
              SizedBox(
                height: 280,
                child: MusicEmptyState(
                  icon: kind == 'artist'
                      ? Icons.person_outline_rounded
                      : Icons.album_outlined,
                  title: kind == 'artist'
                      ? 'Follow an artist'
                      : 'Save an album',
                  description: kind == 'artist'
                      ? 'Artists you follow will be easy to find here.'
                      : 'Albums you save will be easy to find here.',
                ),
              ),
            ],
          )
        : ListView.builder(
            itemCount: entities.length,
            itemBuilder: (context, index) {
              final entity = entities[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  child: Icon(
                    kind == 'artist'
                        ? Icons.person_rounded
                        : Icons.album_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(
                  entity.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  kind == 'album'
                      ? '${entity.artist ?? 'Unknown artist'} · ${entity.trackCount} tracks'
                      : '${entity.trackCount} tracks',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CatalogCollectionScreen(
                      entity: entity,
                      kind: kind,
                      onPlay: _play,
                    ),
                  ),
                ),
              );
            },
          ),
  );
}

class _SavedError extends StatelessWidget {
  const _SavedError({required this.message, required this.onRetry});
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
