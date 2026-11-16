import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_store.dart';
import '../state/auth_controller.dart';
import '../state/library_controller.dart';
import '../state/recent_controller.dart';
import 'downloads_screen.dart';
import 'playlists_screen.dart';
import 'saved_collections_screen.dart';
import 'settings_screen.dart';
import '../widgets/music_section_header.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(settingsControllerProvider).user;
    final favorites = ref.watch(favoritesControllerProvider).length;
    final library = ref.watch(libraryProvider).valueOrNull;
    final recentCount = ref.watch(recentControllerProvider).length;
    final loadedTracks = library?.tracks.length ?? 0;
    final trackCount =
        '$loadedTracks${library?.nextPageToken == null ? '' : '+'}';
    final name = user?.label.trim().isNotEmpty == true
        ? user!.label.trim()
        : 'GMusic listener';
    final initial = name.substring(0, 1).toUpperCase();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: Container(
              width: 94,
              height: 94,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary,
              ),
              child: Text(
                initial,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
          ),
          if (user?.email case final String email) ...[
            const SizedBox(height: 4),
            Text(
              email,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(value: '$favorites', label: 'Liked songs'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileStat(
                  value: '$recentCount',
                  label: 'Recent plays',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileStat(value: trackCount, label: 'In library'),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const MusicSectionHeader(
            title: 'Your music',
            padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
          ),
          _ProfileAction(
            icon: Icons.queue_music_rounded,
            title: 'Playlists',
            subtitle: 'Your created collections',
            onTap: () => _open(context, const PlaylistsScreen()),
          ),
          _ProfileAction(
            icon: Icons.bookmark_outline_rounded,
            title: 'Saved artists and albums',
            subtitle: 'Music you follow and keep',
            onTap: () => _open(context, const SavedCollectionsScreen()),
          ),
          _ProfileAction(
            icon: Icons.download_for_offline_outlined,
            title: 'Downloads',
            subtitle: 'Offline music on this device',
            onTap: () => _open(context, const DownloadsScreen()),
          ),
          const SizedBox(height: 20),
          const MusicSectionHeader(
            title: 'Account',
            padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
          ),
          _ProfileAction(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Appearance, playback and Drive',
            onTap: () => _open(context, const SettingsScreen()),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
