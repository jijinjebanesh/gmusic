import 'dart:math' show max;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/playback.dart';
import '../models/track.dart';
import '../state/lyrics_controller.dart';
import '../state/playback_sync_controller.dart';
import '../services/audio_handler.dart';
import '../services/settings_store.dart';
import '../utils/duration_format.dart';
import '../widgets/cover_palette.dart';
import '../widgets/queue_list_panel.dart';

final _remoteCurrentTrackProvider = FutureProvider.family<Track?, String>((
  ref,
  trackId,
) {
  final userId = ref.watch(
    settingsControllerProvider.select((settings) => settings.user?.id),
  );
  if (userId == null) return null;
  return ref
      .read(settingsControllerProvider.notifier)
      .client()
      .catalogTrack(trackId);
});

// Player presentation adapted from SpotiFLAC-Mobile (MIT, Copyright (c) 2026 zarzet).
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute() : super(fullscreenDialog: true);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const NowPlayingScreen();

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = CurvedAnimation(
      parent: animation,
      curve: Easing.emphasizedDecelerate,
      reverseCurve: Easing.emphasizedAccelerate,
    );
    return SlideTransition(
      position: slide.drive(Tween(begin: const Offset(0, 1), end: Offset.zero)),
      child: child,
    );
  }
}

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui =
        ref.watch(playerUiProvider).valueOrNull ??
        ref.read(audioHandlerProvider).currentUiState;
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final remoteSession = remoteState.remoteTargeted
        ? remoteState.session
        : null;
    final remoteTrackId = remoteSession?.currentTrackId;
    final resolvedRemoteTrack = remoteTrackId == null
        ? null
        : remoteState.remoteCurrentTrack ??
              ref.watch(_remoteCurrentTrackProvider(remoteTrackId)).valueOrNull;
    final track = remoteSession == null
        ? ui.track
        : remoteTrackId == null
        ? null
        : resolvedRemoteTrack?.id == remoteTrackId
        ? resolvedRemoteTrack
        : ui.track?.id == remoteTrackId
        ? ui.track
        : remoteSession.trackPlaceholder;
    if (track == null) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Minimize player',
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IconButton(
              tooltip: 'Audio output',
              icon: const Icon(Icons.devices_rounded),
              onPressed: () => _showAudioOutput(context),
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Nothing is playing',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).valueOrNull;
    final favorite = ref.watch(favoritesControllerProvider).contains(track.id);
    return CoverPaletteBuilder(
      imageUrl: track.artUrl,
      builder: (context, coverScheme) => Theme(
        data: _playerTheme(context, coverScheme),
        child: Builder(
          builder: (playerContext) {
            final scheme = Theme.of(playerContext).colorScheme;
            void onOutput() => _showAudioOutput(playerContext);
            void onMore() => _showMoreActions(playerContext, ref, track);

            void onQueue() => _openQueue(playerContext, ref);

            final details = _PlayerDetails(
              track: track,
              ui: ui,
              favorite: favorite,
              position: position,
              duration: duration,
              onLike: () =>
                  _toggleFavorite(playerContext, ref, track, favorite),
              onOutput: onOutput,
              onShare: () => _shareTrack(playerContext, track),
              onQueue: onQueue,
            );
            final routeAnimation = ModalRoute.of(playerContext)?.animation;
            final playerPage = SizedBox(
              height: max(
                620.0,
                MediaQuery.sizeOf(playerContext).height * 0.82,
              ),
              child: _PlayerPage(
                track: track,
                details: details,
                remotePlayback:
                    remoteSession != null &&
                    (remoteSession.index < 0 ||
                        remoteSession.index >= remoteSession.trackIds.length ||
                        remoteSession.trackIds[remoteSession.index] !=
                            track.id),
              ),
            );
            Widget content = CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: false,
                  expandedHeight: 72,
                  toolbarHeight: 56,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  forceMaterialTransparency: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  shadowColor: Colors.transparent,
                  foregroundColor: scheme.onSurface,
                  leading: IconButton(
                    tooltip: 'Minimize player',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: () => Navigator.of(playerContext).maybePop(),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Audio output',
                      icon: const Icon(Icons.devices_rounded),
                      onPressed: onOutput,
                    ),
                    IconButton(
                      tooltip: 'More options',
                      icon: const Icon(Icons.more_vert),
                      onPressed: onMore,
                    ),
                  ],
                  flexibleSpace: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        'Playing',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        playerPage,
                        if (remoteSession == null)
                          _LyricsPanel(
                            trackId: track.id,
                            onExpand: () =>
                                _showLyricsScreen(playerContext, track),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
            if (routeAnimation != null) {
              content = FadeTransition(
                opacity: CurvedAnimation(
                  parent: routeAnimation,
                  curve: const Interval(0.4, 1, curve: Curves.easeOut),
                ),
                child: content,
              );
            }

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: scheme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: scheme.brightness == Brightness.dark
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: scheme.surface,
                systemNavigationBarIconBrightness:
                    scheme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: Scaffold(
                backgroundColor: scheme.surface,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverAtmosphere(
                      imageUrl: track.artUrl,
                      colorScheme: scheme,
                    ),
                    content,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    Track track,
    bool favorite,
  ) async {
    final favorites = ref.read(favoritesControllerProvider.notifier);
    final settings = ref.read(settingsControllerProvider.notifier);
    final added = !favorite;
    await favorites.toggle(track.id);
    final synced = await syncFavoriteRemote(
      favorites: favorites,
      settings: settings,
      added: added,
      track: track,
    );
    if (!synced && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Favorite saved on this device; sync will retry.'),
        ),
      );
    }
  }

  Future<void> _showAudioOutput(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.66,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: const _PlaybackDevicesSection(),
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreActions(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_up_outlined),
              title: const Text('Volume'),
              onTap: () => Navigator.of(context).pop('volume'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Track details'),
              onTap: () => Navigator.of(context).pop('details'),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Open queue'),
              onTap: () => Navigator.of(context).pop('queue'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;

    switch (action) {
      case 'volume':
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => const _VolumeSheet(),
        );
      case 'details':
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(label: 'Title', value: track.title),
                  _DetailRow(
                    label: 'Artist',
                    value: track.artist ?? 'Unknown artist',
                  ),
                  if (track.album?.trim().isNotEmpty == true)
                    _DetailRow(label: 'Album', value: track.album!),
                  _DetailRow(label: 'File', value: track.name),
                  if (track.extension.isNotEmpty)
                    _DetailRow(label: 'Format', value: track.extension),
                ],
              ),
            ),
          ),
        );
      case 'queue':
        _openQueue(context, ref);
    }
  }

  Future<void> _shareTrack(BuildContext context, Track track) async {
    final artist = track.artist?.trim() ?? '';
    await SharePlus.instance.share(
      ShareParams(
        text: artist.isEmpty ? track.title : '${track.title}\n$artist',
      ),
    );
  }

  void _showLyricsScreen(BuildContext context, Track track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _LyricsScreen(track: track)),
    );
  }

  void _openQueue(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.94,
        minChildSize: 0.45,
        builder: (context, controller) => Column(
          children: [
            Expanded(
              child: QueueListPanel(
                scrollController: controller,
                onTrackSelected: (_) => Navigator.of(sheetContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaybackDevicesSection extends ConsumerWidget {
  const _PlaybackDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackSyncControllerProvider);
    final controller = ref.read(playbackSyncControllerProvider.notifier);
    final session = state.session;
    final localTrack = ref.watch(playerUiProvider).valueOrNull?.track;
    final currentTrack = [
      session?.title ?? '',
      session?.artist ?? '',
    ].where((value) => value.trim().isNotEmpty).join(' · ');

    Future<void> sendCommand(String action) async {
      try {
        await controller.sendCommand(action);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not control playback: $error')),
          );
        }
      }
    }

    Future<void> switchTo(PlaybackDevice device) async {
      try {
        await controller.handoffTo(device.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Playback switched to ${device.name}.')),
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not switch playback: $error')),
          );
        }
      }
    }

    Future<void> renameDevice(PlaybackDevice device) async {
      final nameController = TextEditingController(text: device.name);
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Device name'),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(nameController.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      nameController.dispose();
      if (name == null || !context.mounted) return;
      try {
        await controller.renameDevice(device.id, name);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not rename device: $error')),
          );
        }
      }
    }

    Future<void> forgetDevice(PlaybackDevice device) async {
      try {
        await controller.forgetOfflineDevice(device.id);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove device: $error')),
          );
        }
      }
    }

    Future<void> disconnectThisDevice() async {
      try {
        await controller.disconnectThisDevice();
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not disconnect this device: $error')),
          );
        }
      }
    }

    Future<void> reconnectThisDevice() async {
      try {
        await controller.reconnectThisDevice();
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not reconnect this device: $error')),
          );
        }
      }
    }

    final canRefresh = state.deviceId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Connect to a device',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (session?.activeDeviceId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening on ${state.activeDevice?.name ?? 'another device'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (currentTrack.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    currentTrack,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Previous track',
                      onPressed: () => sendCommand('previous'),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    IconButton.filled(
                      tooltip: session?.playing == true ? 'Pause' : 'Play',
                      onPressed: () => sendCommand(
                        session?.playing == true ? 'pause' : 'play',
                      ),
                      icon: Icon(
                        session?.playing == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed: () => sendCommand('next'),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                if (state.activeDevice?.capabilities.volume ?? true)
                  _RemoteVolumeControl(
                    volume: session?.volume ?? 1,
                    deviceName: state.activeDevice?.name ?? 'active device',
                    onChangeEnd: (value) async {
                      try {
                        await controller.sendCommand(
                          'volume',
                          payload: {'volume': value},
                        );
                      } on Object catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not set volume: $error'),
                            ),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
        if (state.deviceId == null)
          const Expanded(
            child: Center(
              child: Text('Sign in to connect your GMusic devices.'),
            ),
          )
        else if (state.devices.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                state.syncing ? 'Finding devices…' : 'No other devices found.',
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: state.devices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final device = state.devices[index];
                final isCurrent = device.id == state.deviceId;
                final isActive = device.id == session?.activeDeviceId;
                final selected =
                    isActive || (session?.activeDeviceId == null && isCurrent);
                final title = device.name;
                final String subtitle;
                if (isActive && !device.online) {
                  subtitle = 'Offline';
                } else if (isActive) {
                  subtitle = [
                    if (currentTrack.isNotEmpty) currentTrack,
                    if (session?.playing == true)
                      'Playing here'
                    else
                      'Paused here',
                  ].join(' · ');
                } else if (isCurrent) {
                  subtitle = localTrack == null
                      ? 'This device · Ready to play'
                      : 'This device · ${localTrack.title} · ${localTrack.artist ?? ''}';
                } else {
                  subtitle = device.online ? 'Available' : 'Offline';
                }
                final String? badgeLabel;
                if (!selected) {
                  badgeLabel = null;
                } else if (!isActive) {
                  badgeLabel = 'This device';
                } else if (!device.online) {
                  badgeLabel = 'Offline';
                } else {
                  badgeLabel = session?.playing == true ? 'Playing' : 'Paused';
                }
                final platformIcon = switch (device.platform) {
                  'android' => Icons.phone_android_rounded,
                  'ios' => Icons.phone_iphone_rounded,
                  'windows' || 'linux' || 'web' => Icons.laptop_windows_rounded,
                  'macos' => Icons.laptop_mac_rounded,
                  _ => Icons.devices_rounded,
                };
                return Material(
                  color: selected
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    minVerticalPadding: 12,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 3,
                    ),
                    leading: Icon(
                      isActive ? Icons.graphic_eq_rounded : platformIcon,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCurrent ? 21 : 16,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 8),
                          _DeviceBadge(label: badgeLabel),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          Icon(
                            platformIcon,
                            color: Theme.of(context).colorScheme.primary,
                            size: 26,
                          ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz_rounded),
                          onSelected: (action) {
                            switch (action) {
                              case 'switch':
                                switchTo(device);
                              case 'rename':
                                renameDevice(device);
                              case 'disconnect':
                                disconnectThisDevice();
                              case 'forget':
                                forgetDevice(device);
                            }
                          },
                          itemBuilder: (_) => [
                            if (device.online && !isActive)
                              const PopupMenuItem(
                                value: 'switch',
                                child: Text('Switch playback here'),
                              ),
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename device'),
                            ),
                            if (isCurrent)
                              const PopupMenuItem(
                                value: 'disconnect',
                                child: Text('Disconnect this device'),
                              )
                            else if (!device.online)
                              const PopupMenuItem(
                                value: 'forget',
                                child: Text('Forget offline device'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    enabled: device.online,
                    onTap: device.online && !isCurrent && !isActive
                        ? () => switchTo(device)
                        : null,
                  ),
                );
              },
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (state.deviceId != null) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show this device to my account'),
            subtitle: const Text(
              'Other signed-in GMusic devices can connect to this player.',
            ),
            value: state.deviceVisible,
            onChanged: (visible) async {
              try {
                await controller.setDeviceVisibility(visible);
              } on Object catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not update visibility: $error'),
                    ),
                  );
                }
              }
            },
          ),
          if (!state.devices.any((device) => device.id == state.deviceId))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: reconnectThisDevice,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reconnect this device'),
                ),
              ),
            ),
        ],
        SizedBox(
          width: double.infinity,
          height: 60,
          child: FilledButton.tonalIcon(
            onPressed: canRefresh ? controller.refresh : null,
            icon: const Icon(Icons.devices_rounded),
            label: const Text('Find GMusic devices'),
          ),
        ),
      ],
    );
  }
}

class _RemoteVolumeControl extends StatefulWidget {
  const _RemoteVolumeControl({
    required this.volume,
    required this.deviceName,
    required this.onChangeEnd,
  });

  final double volume;
  final String deviceName;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_RemoteVolumeControl> createState() => _RemoteVolumeControlState();
}

class _RemoteVolumeControlState extends State<_RemoteVolumeControl> {
  double? _editedVolume;

  @override
  void didUpdateWidget(covariant _RemoteVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volume != widget.volume) _editedVolume = null;
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.volume_down_rounded, size: 20),
      Expanded(
        child: Slider(
          value: (_editedVolume ?? widget.volume).clamp(0.0, 1.0).toDouble(),
          onChanged: (value) => setState(() => _editedVolume = value),
          onChangeEnd: (value) {
            widget.onChangeEnd(value);
            setState(() => _editedVolume = null);
          },
        ),
      ),
      const Icon(Icons.volume_up_rounded, size: 20),
      const SizedBox(width: 4),
      Text(
        widget.deviceName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );
}

class _DeviceBadge extends StatelessWidget {
  const _DeviceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PlayerPage extends StatelessWidget {
  const _PlayerPage({
    required this.track,
    required this.details,
    required this.remotePlayback,
  });

  final Track track;
  final Widget details;
  final bool remotePlayback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget artworkAt(double size) => Center(
        child: remotePlayback
            ? SizedBox(
                width: size,
                height: size,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : _PlayerArtwork(track: track, size: size),
      );
      final twoPane =
          constraints.maxWidth >= 720 &&
          constraints.maxWidth > constraints.maxHeight;
      if (twoPane) {
        final artworkSize = (constraints.maxHeight - 96).clamp(0.0, 420.0);
        return Row(
          children: [
            Expanded(child: artworkAt(artworkSize)),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [details],
                ),
              ),
            ),
          ],
        );
      }

      final artworkSize = (constraints.maxWidth - 40).clamp(0.0, 360.0);
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: artworkAt(artworkSize)),
            const SizedBox(height: 32),
            details,
          ],
        ),
      );
    },
  );
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({required this.track, required this.size});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artUrl = track.artUrl;
    Widget placeholder() => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 40, color: scheme.onSurfaceVariant),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: size, maxHeight: size),
      child: AspectRatio(
        aspectRatio: 1,
        child: Hero(
          tag: 'gmusic-art-${track.id}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: artUrl == null
                  ? SizedBox(
                      key: ValueKey(track.id),
                      width: size,
                      height: size,
                      child: placeholder(),
                    )
                  : CachedNetworkImage(
                      key: ValueKey(track.id),
                      imageUrl: artUrl,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => placeholder(),
                      errorWidget: (_, _, _) => placeholder(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

const _playerGreen = Color(0xFF1DB954);

class _ActiveDotIcon extends StatelessWidget {
  const _ActiveDotIcon({
    required this.icon,
    required this.active,
    required this.color,
  });

  final IconData icon;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon, color: color),
      if (active)
        Positioned(
          top: -3,
          right: -3,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _playerGreen,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 1.5,
              ),
            ),
          ),
        ),
    ],
  );
}

class _PlayerDetails extends ConsumerWidget {
  const _PlayerDetails({
    required this.track,
    required this.ui,
    required this.favorite,
    required this.position,
    required this.duration,
    required this.onLike,
    required this.onOutput,
    required this.onShare,
    required this.onQueue,
  });

  final Track track;
  final PlayerUiState ui;
  final bool favorite;
  final Duration position;
  final Duration? duration;
  final VoidCallback onLike;
  final VoidCallback onOutput;
  final VoidCallback onShare;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final remoteSession = remoteState.remoteTargeted
        ? remoteState.session
        : null;
    final scheme = Theme.of(context).colorScheme;
    final actionColor = scheme.brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.primary;
    final actionForeground = scheme.brightness == Brightness.dark
        ? scheme.surface
        : scheme.onPrimary;
    final playing = remoteSession?.playing ?? ui.playing;
    final shuffle = remoteSession?.shuffle ?? ui.shuffle;
    final repeat = switch (remoteSession?.repeat) {
      'one' => AudioServiceRepeatMode.one,
      'all' => AudioServiceRepeatMode.all,
      'none' || null => ui.repeat,
      _ => ui.repeat,
    };
    final title = remoteSession?.title.trim().isNotEmpty == true
        ? remoteSession!.title
        : track.title;
    final artist = remoteSession?.artist.trim().isNotEmpty == true
        ? remoteSession!.artist
        : track.artist ?? '';
    final destination = remoteSession == null
        ? remoteState.deviceName ?? 'this device'
        : remoteState.activeDevice?.name ?? 'an unavailable device';
    final destinationStatus =
        remoteSession != null && remoteState.activeDevice?.online != true
        ? ' · Offline'
        : '';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Row(
              key: ValueKey(remoteSession?.activeDeviceId ?? track.id),
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: favorite ? 'Remove from liked songs' : 'Like song',
                  onPressed: onLike,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween(begin: 0.65, end: 1.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                      ),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      favorite ? Icons.check_rounded : Icons.add_rounded,
                      key: ValueKey(favorite),
                      size: 34,
                      color: favorite ? _playerGreen : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _PlayerSeekBar(
          position: remoteSession?.currentPosition ?? position,
          duration: remoteSession == null
              ? duration
              : remoteSession.durationMs > 0
              ? Duration(milliseconds: remoteSession.durationMs)
              : track.duration,
          format: remoteSession == null ? track.extension : '',
          onSeek: handler.seek,
          remote: remoteSession != null,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              isSelected: shuffle,
              iconSize: 24,
              icon: _ActiveDotIcon(
                icon: shuffle ? Icons.shuffle : Icons.shuffle_outlined,
                active: shuffle,
                color: shuffle ? _playerGreen : scheme.onSurfaceVariant,
              ),
              onPressed: () => handler.setShuffleMode(
                shuffle
                    ? AudioServiceShuffleMode.none
                    : AudioServiceShuffleMode.all,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Previous track',
              iconSize: 44,
              icon: const Icon(Icons.skip_previous),
              onPressed: handler.skipToPrevious,
            ),
            const SizedBox(width: 20),
            Material(
              color: actionColor,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: handler.togglePlayPause,
                child: AnimatedScale(
                  scale: playing ? 1 : 0.96,
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutBack,
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: Tween(begin: 0.65, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: ui.buffering
                            ? SizedBox(
                                key: const ValueKey('buffering'),
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: actionForeground,
                                ),
                              )
                            : Icon(
                                key: ValueKey(playing),
                                playing ? Icons.pause : Icons.play_arrow,
                                size: 44,
                                color: actionForeground,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              tooltip: 'Next track',
              iconSize: 44,
              icon: const Icon(Icons.skip_next),
              onPressed: handler.skipToNext,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: _repeatTooltip(repeat),
              isSelected: repeat != AudioServiceRepeatMode.none,
              iconSize: 24,
              icon: _ActiveDotIcon(
                icon: _repeatIcon(repeat),
                active: repeat != AudioServiceRepeatMode.none,
                color: repeat == AudioServiceRepeatMode.none
                    ? scheme.onSurfaceVariant
                    : _playerGreen,
              ),
              onPressed: () => handler.setRepeatMode(_nextRepeat(repeat)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: onOutput,
                  icon: const Icon(Icons.devices_rounded),
                  label: Text(
                    'Listening on $destination$destinationStatus',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Share track',
                icon: const Icon(Icons.share_outlined),
                onPressed: onShare,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Up next',
                icon: _ActiveDotIcon(
                  icon: Icons.queue_music_outlined,
                  active:
                      (remoteSession?.trackIds.length ?? ui.queue.length) > 1,
                  color: (remoteSession?.trackIds.length ?? ui.queue.length) > 1
                      ? _playerGreen
                      : scheme.onSurface,
                ),
                onPressed: onQueue,
              ),
            ],
          ),
        ),
        if (ui.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              color: scheme.errorContainer,
              child: ListTile(
                title: Text(ui.error!),
                trailing: TextButton(
                  onPressed: handler.clearError,
                  child: const Text('Dismiss'),
                ),
              ),
            ),
          ),
        if (remoteState.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              remoteState.error!,
              style: TextStyle(color: scheme.error),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  static IconData _repeatIcon(AudioServiceRepeatMode mode) => switch (mode) {
    AudioServiceRepeatMode.one => Icons.repeat_one,
    AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => Icons.repeat,
    _ => Icons.repeat,
  };

  static String _repeatTooltip(AudioServiceRepeatMode mode) => switch (mode) {
    AudioServiceRepeatMode.one => 'Repeat one',
    AudioServiceRepeatMode.none => 'Repeat off',
    _ => 'Repeat all',
  };

  static AudioServiceRepeatMode _nextRepeat(AudioServiceRepeatMode mode) =>
      switch (mode) {
        AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
        AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
}

class _PlayerSeekBar extends StatefulWidget {
  const _PlayerSeekBar({
    required this.position,
    required this.duration,
    required this.format,
    required this.onSeek,
    required this.remote,
  });

  final Duration position;
  final Duration? duration;
  final String format;
  final ValueChanged<Duration> onSeek;
  final bool remote;

  @override
  State<_PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<_PlayerSeekBar> {
  Duration? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final position = _dragPosition ?? widget.position;
    final maxMilliseconds = widget.duration?.inMilliseconds ?? 0;
    final value = maxMilliseconds > 0
        ? position.inMilliseconds.clamp(0, maxMilliseconds).toDouble()
        : 0.0;
    final formatLabel = widget.format.trim().isEmpty
        ? null
        : widget.format.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: scheme.onSurface,
              inactiveTrackColor: scheme.onSurfaceVariant.withValues(
                alpha: 0.34,
              ),
              thumbColor: scheme.onSurface,
              overlayColor: scheme.onSurface.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            ),
            child: Slider(
              value: value,
              max: maxMilliseconds > 0 ? maxMilliseconds.toDouble() : 1,
              onChanged: maxMilliseconds > 0
                  ? (value) {
                      final next = Duration(milliseconds: value.round());
                      if (widget.remote) {
                        setState(() => _dragPosition = next);
                      } else {
                        widget.onSeek(next);
                      }
                    }
                  : null,
              onChangeEnd: maxMilliseconds > 0 && widget.remote
                  ? (value) {
                      widget.onSeek(Duration(milliseconds: value.round()));
                      setState(() => _dragPosition = null);
                    }
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  formatDuration(position),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                Expanded(
                  child: Center(
                    child: formatLabel == null
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.onSurface.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.graphic_eq,
                                  size: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  formatLabel,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontSize: 10.5,
                                        color: scheme.onSurfaceVariant,
                                        letterSpacing: 0.2,
                                      ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                Text(
                  formatDuration(widget.duration),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsPanel extends ConsumerWidget {
  const _LyricsPanel({required this.trackId, required this.onExpand});

  final String trackId;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lyricsScheme = _lyricsColorScheme(scheme);
    final lyrics = ref.watch(trackLyricsProvider(trackId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: lyricsScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.lyrics_outlined,
                    size: 22,
                    color: lyricsScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Lyrics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: lyricsScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open lyrics',
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: onExpand,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 170,
              child: _LyricsContent(
                lyrics: lyrics,
                compact: true,
                onRetry: () => ref.invalidate(trackLyricsProvider(trackId)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsScreen extends ConsumerWidget {
  const _LyricsScreen({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(trackLyricsProvider(track.id));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close lyrics',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Lyrics'),
      ),
      body: SafeArea(
        child: _LyricsContent(
          lyrics: lyrics,
          onRetry: () => ref.invalidate(trackLyricsProvider(track.id)),
        ),
      ),
    );
  }
}

class _LyricsContent extends StatelessWidget {
  const _LyricsContent({
    required this.lyrics,
    required this.onRetry,
    this.compact = false,
  });

  final AsyncValue<String?> lyrics;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) => lyrics.when(
    data: (text) {
      if (text == null) {
        return Center(
          child: Padding(
            padding: EdgeInsets.all(compact ? 20 : 32),
            child: Text(
              'No embedded lyrics found for this track.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
      return SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
        ),
      );
    },
    loading: () => const Center(child: CircularProgressIndicator.adaptive()),
    error: (error, stackTrace) => Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load lyrics.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    ),
  );
}

class _VolumeSheet extends ConsumerStatefulWidget {
  const _VolumeSheet();

  @override
  ConsumerState<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends ConsumerState<_VolumeSheet> {
  double? _editedVolume;

  Future<void> _setRemoteVolume(double value) async {
    try {
      await ref
          .read(playbackSyncControllerProvider.notifier)
          .sendCommand('volume', payload: {'volume': value});
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not set volume: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final remoteState = ref.watch(playbackSyncControllerProvider);
    final remoteSession = remoteState.remoteTargeted
        ? remoteState.session
        : null;
    final remoteVolumeSupported =
        remoteState.activeDevice?.capabilities.volume ?? true;
    final volume =
        _editedVolume ??
        remoteSession?.volume ??
        ref.watch(volumeProvider).valueOrNull ??
        handler.player.volume;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              remoteSession == null
                  ? 'This device volume'
                  : 'Volume on ${remoteState.activeDevice?.name ?? 'active device'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (remoteSession != null && !remoteVolumeSupported)
              const Text('This device does not support remote volume control.')
            else
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded),
                  Expanded(
                    child: Slider(
                      value: volume.clamp(0.0, 1.0).toDouble(),
                      onChanged: (value) {
                        setState(() => _editedVolume = value);
                        if (remoteSession == null) {
                          handler.setVolume(value);
                        }
                      },
                      onChangeEnd: remoteSession == null
                          ? null
                          : _setRemoteVolume,
                    ),
                  ),
                  const Icon(Icons.volume_up_rounded),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

ColorScheme _lyricsColorScheme(ColorScheme colorScheme) {
  final top = coverPlayerTopColor(colorScheme.primary);
  final surface = Color.lerp(
    top,
    colorScheme.surface,
    colorScheme.brightness == Brightness.dark ? 0.28 : 0.74,
  )!;
  return colorScheme.copyWith(
    surface: surface,
    surfaceContainerHighest: surface,
  );
}

ThemeData _playerTheme(BuildContext context, ColorScheme scheme) {
  final base = Theme.of(context);
  return base.copyWith(
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    iconTheme: IconThemeData(color: scheme.onSurface),
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: scheme.onSurface.withValues(alpha: 0.72),
      inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.32),
      thumbColor: scheme.onSurface,
      overlayColor: scheme.onSurface.withValues(alpha: 0.12),
    ),
  );
}
