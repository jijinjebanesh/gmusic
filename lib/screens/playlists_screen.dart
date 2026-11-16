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

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  List<UserPlaylist> _items = [];
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
      final items = await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .playlists();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load playlists: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _create() async {
    final name = await _playlistNameDialog(context, title: 'New playlist');
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .createPlaylist(name.trim());
      await _load();
    } catch (error) {
      if (mounted) _message('Could not create playlist: $error');
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Playlists'),
      actions: [
        IconButton(
          tooltip: 'Create playlist',
          onPressed: _create,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : _items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 72),
                SizedBox(
                  height: 280,
                  child: MusicEmptyState(
                    icon: Icons.queue_music_rounded,
                    title: 'Make it yours',
                    description:
                        'Create a playlist for every mood, moment, or memory.',
                    action: FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Create playlist'),
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${item.trackIds.length} tracks${item.description.isEmpty ? '' : ' · ${item.description}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistDetailScreen(playlist: item),
                      ),
                    );
                    _load();
                  },
                );
              },
            ),
    ),
    floatingActionButton: _items.isNotEmpty
        ? FloatingActionButton(onPressed: _create, child: const Icon(Icons.add))
        : null,
  );
}

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});
  final UserPlaylist playlist;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  late UserPlaylist _playlist = widget.playlist;
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveTracks();
  }

  Future<void> _resolveTracks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(settingsControllerProvider.notifier).client();
      final tracks = await Future.wait(
        _playlist.trackIds.map(client.catalogTrack),
      );
      final downloads = ref.read(downloadsProvider).items;
      if (mounted) {
        setState(() {
          _tracks = tracks
              .whereType<Track>()
              .map((track) => downloads[track.id]?.track ?? track)
              .toList();
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load playlist tracks: $error';
          _loading = false;
        });
      }
    }
  }

  Future<bool> _save(UserPlaylist next) async {
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .updatePlaylist(next);
      if (mounted) setState(() => _playlist = next);
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save playlist: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _edit() async {
    final values = await _playlistEditDialog(context, _playlist);
    if (values != null) {
      await _save(_playlist.copyWith(name: values.$1, description: values.$2));
    }
  }

  Future<void> _addTrack() async {
    final all =
        ref.read(libraryProvider).valueOrNull?.tracks ?? const <Track>[];
    final candidates = all
        .where((track) => !_playlist.trackIds.contains(track.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other loaded tracks are available to add.'),
        ),
      );
      return;
    }
    final track = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  'Add a track',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final item = candidates[index];
                    return ListTile(
                      leading: CoverImage(track: item, size: 44),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(item.artist ?? 'Unknown artist'),
                      onTap: () => Navigator.pop(context, item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (track == null) return;
    final saved = await _save(
      _playlist.copyWith(trackIds: [..._playlist.trackIds, track.id]),
    );
    if (saved) await _resolveTracks();
  }

  Future<void> _removeTrack(Track track) async {
    final saved = await _save(
      _playlist.copyWith(
        trackIds: _playlist.trackIds.where((id) => id != track.id).toList(),
      ),
    );
    if (saved) await _resolveTracks();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('“${_playlist.name}” will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .deletePlaylist(_playlist.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete playlist: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final downloadController = ref.read(downloadsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _edit();
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Row(
              children: [
                Container(
                  width: 112,
                  height: 112,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _tracks.isEmpty
                      ? Icon(
                          Icons.queue_music_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : CoverImage(track: _tracks.first, size: 112, radius: 8),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playlist.description.isEmpty
                            ? 'Playlist'
                            : _playlist.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_playlist.trackIds.length} tracks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _tracks.isEmpty
                      ? null
                      : () => handler.playTracks(_tracks, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _addTrack,
                  icon: const Icon(Icons.add),
                  label: const Text('Add tracks'),
                ),
                OutlinedButton.icon(
                  onPressed: _tracks.isEmpty || !downloadController.supported
                      ? null
                      : () => downloadController.downloadAll(_tracks),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Download'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _error != null && _tracks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(
                          onPressed: _resolveTracks,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _loading && _tracks.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _tracks.isEmpty
                ? const Center(
                    child: Text('Add tracks from your library to get started.'),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _tracks.length,
                    onReorderItem: (oldIndex, newIndex) async {
                      final reordered = [..._tracks];
                      final track = reordered.removeAt(oldIndex);
                      reordered.insert(newIndex, track);
                      setState(() => _tracks = reordered);
                      final saved = await _save(
                        _playlist.copyWith(
                          trackIds: reordered.map((item) => item.id).toList(),
                        ),
                      );
                      if (!saved) await _resolveTracks();
                    },
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return TrackTile(
                        key: ValueKey(track.id),
                        track: track,
                        isCurrent: false,
                        isPlaying: false,
                        onTap: () => handler.playTracks(_tracks, index),
                        trailing: PopupMenuButton<String>(
                          onSelected: (_) => _removeTrack(track),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove from playlist'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _playlistNameDialog(
  BuildContext context, {
  required String title,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PlaylistNameDialog(title: title),
);

Future<(String, String)?> _playlistEditDialog(
  BuildContext context,
  UserPlaylist playlist,
) => showDialog<(String, String)>(
  context: context,
  builder: (_) => _PlaylistEditDialog(playlist: playlist),
);

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title});

  final String title;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(hintText: 'Playlist name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Create'),
      ),
    ],
  );
}

class _PlaylistEditDialog extends StatefulWidget {
  const _PlaylistEditDialog({required this.playlist});

  final UserPlaylist playlist;

  @override
  State<_PlaylistEditDialog> createState() => _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends State<_PlaylistEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
    _descriptionController = TextEditingController(
      text: widget.playlist.description,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit playlist'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        TextField(
          controller: _descriptionController,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          _nameController.text.trim(),
          _descriptionController.text.trim(),
        )),
        child: const Text('Save'),
      ),
    ],
  );
}
