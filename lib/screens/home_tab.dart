import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';
import '../state/library_controller.dart';
import '../widgets/cover_image.dart';
import 'library_tab.dart';
import 'playlists_screen.dart';
import 'profile_screen.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});
  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  List<UserPlaylist> _playlists = const [];
  bool _loadingPlaylists = true;
  String? _playlistError;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _loadingPlaylists = true;
      _playlistError = null;
    });
    try {
      final playlists = await ref
          .read(settingsControllerProvider.notifier)
          .client()
          .playlists();
      if (mounted) {
        setState(() {
          _playlists = playlists;
          _loadingPlaylists = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _playlistError = 'Could not load playlists: $error';
          _loadingPlaylists = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(libraryProvider.notifier).load(),
      _loadPlaylists(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tracks =
        ref.watch(libraryProvider).valueOrNull?.tracks ?? const <Track>[];
    final hour = DateTime.now().hour;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _greeting(hour),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.7,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Your profile',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.person_outline_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your music',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PlaylistsScreen(),
                          ),
                        );
                        if (mounted) _loadPlaylists();
                      },
                      child: const Text('Playlists'),
                    ),
                  ],
                ),
              ),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 700 ? 3 : 2;
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.45,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      if (index == 0) {
                        return _CollectionShortcut(
                          title: 'Liked Songs',
                          icon: Icons.favorite_rounded,
                          gradient: const [
                            Color(0xFF7653C8),
                            Color(0xFF273C8D),
                          ],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LikedSongsScreen(),
                            ),
                          ),
                        );
                      }

                      final playlist = _playlists[index - 1];
                      final firstTrackId = playlist.trackIds.isEmpty
                          ? null
                          : playlist.trackIds.first;
                      final artworkTrack = firstTrackId == null
                          ? null
                          : _trackById(tracks, firstTrackId);
                      return _CollectionShortcut(
                        title: playlist.name,
                        track: artworkTrack,
                        icon: Icons.queue_music_rounded,
                        gradient: _playlistGradient(index - 1),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PlaylistDetailScreen(playlist: playlist),
                            ),
                          );
                          if (mounted) _loadPlaylists();
                        },
                      );
                    }, childCount: _playlists.length + 1),
                  ),
                );
              },
            ),
            if (_loadingPlaylists)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else if (_playlistError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _playlistError!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _loadPlaylists,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_playlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Text(
                    'No playlists yet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _greeting(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

Track? _trackById(List<Track> tracks, String id) {
  for (final track in tracks) {
    if (track.id == id) return track;
  }
  return null;
}

List<Color> _playlistGradient(int index) {
  const gradients = [
    [Color(0xFFB05A36), Color(0xFF6D382B)],
    [Color(0xFF3D806E), Color(0xFF24493E)],
    [Color(0xFF5276A8), Color(0xFF303E70)],
    [Color(0xFF9B6940), Color(0xFF62402D)],
  ];
  return gradients[index % gradients.length];
}

class _CollectionShortcut extends StatelessWidget {
  const _CollectionShortcut({
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.track,
  });

  final String title;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(7),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: double.infinity,
              child: track == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 23),
                    )
                  : CoverImage(track: track!, size: 58, radius: 0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
