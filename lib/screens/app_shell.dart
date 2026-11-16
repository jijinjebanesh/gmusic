import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/drive_auth.dart';
import '../services/settings_store.dart';
import '../state/download_controller.dart';
import '../state/auth_controller.dart';
import '../state/library_controller.dart';
import '../state/recent_controller.dart';
import '../widgets/gmusic_brand_mark.dart';
import '../widgets/mini_player.dart';
import 'catalog_screen.dart';
import 'home_tab.dart';
import 'library_tab.dart';
import 'profile_screen.dart';
import 'queue_screen.dart';
import 'search_tab.dart';

/// Responsive navigation shell with a persistent player dock.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final library = ref.read(libraryProvider.notifier);
      final libraryLoad = library.load();
      // Expired stream tickets are refreshed from this loader.
      final handler = ref.read(audioHandlerProvider);
      handler.setBridgeUrl(ref.read(settingsControllerProvider).bridgeUrl);
      handler.refresher = (id) async {
        await libraryLoad;
        return library.refreshTrack(id);
      };
      final auth = ref.read(driveAuthControllerProvider.notifier);
      auth.checkStatus();
      // Validate the stored session; a dead token drops us to the login screen.
      ref.read(authControllerProvider.notifier).restoreSession();
      ref.read(recentControllerProvider.notifier).load();
    });
  }

  void _playFrom(List<Track> tracks, int index) {
    if (tracks.isEmpty) return;
    final downloads = ref.read(downloadsProvider).items;
    final playable = tracks
        .map((track) => downloads[track.id]?.track ?? track)
        .toList();
    ref.read(audioHandlerProvider).playTracks(playable, index);
    ref.read(recentControllerProvider.notifier).record(playable[index]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsControllerProvider, (_, settings) {
      ref.read(audioHandlerProvider).setBridgeUrl(settings.bridgeUrl);
    });
    final pages = [
      const HomeTab(),
      SearchTab(onPlay: _playFrom),
      const LibraryTab(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _DesktopNavigation(
                    selectedIndex: _tab,
                    onSelected: (index) => setState(() => _tab = index),
                    onCatalog: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CatalogScreen(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: IndexedStack(index: _tab, children: pages),
                        ),
                        const MiniPlayer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: _tab, children: pages),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (index) => setState(() => _tab = index),
                destinations: _destinations,
              ),
            ],
          ),
        );
      },
    );
  }
}

const _destinations = [
  NavigationDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: 'Home',
  ),
  NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
  NavigationDestination(
    icon: Icon(Icons.library_music_outlined),
    selectedIcon: Icon(Icons.library_music_rounded),
    label: 'Library',
  ),
];

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onCatalog,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onCatalog;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 16, 34),
              child: Row(
                children: [
                  const GMusicBrandMark(size: 38),
                  const SizedBox(width: 11),
                  Text(
                    'GMusic',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 0, 8),
              child: Text(
                'YOUR MUSIC',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            for (var index = 0; index < _destinations.length; index++)
              _DesktopNavigationItem(
                destination: _destinations[index],
                selected: selectedIndex == index,
                onTap: () => onSelected(index),
              ),
            _DesktopUtilityItem(
              icon: Icons.library_music_rounded,
              label: 'All music',
              onTap: onCatalog,
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 0, 8),
              child: Text(
                'PLAYBACK',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            _DesktopUtilityItem(
              icon: Icons.queue_music_rounded,
              label: 'Queue',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopUtilityItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfileScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your music, one collection.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopUtilityItem extends StatelessWidget {
  const _DesktopUtilityItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class _DesktopNavigationItem extends StatelessWidget {
  const _DesktopNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = selected
        ? destination.selectedIcon ?? destination.icon
        : destination.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border(left: BorderSide(color: colors.primary, width: 2))
                  : null,
            ),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 20,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 13),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: selected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
