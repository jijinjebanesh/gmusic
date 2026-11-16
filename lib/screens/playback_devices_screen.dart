import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playback.dart';
import '../state/playback_sync_controller.dart';
import '../services/settings_store.dart';

class PlaybackDevicesScreen extends ConsumerWidget {
  const PlaybackDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackSyncControllerProvider);
    final controller = ref.read(playbackSyncControllerProvider.notifier);
    final settings = ref.watch(settingsControllerProvider);
    final session = state.session;
    final activeDeviceId = session?.activeDeviceId;
    final devices = [...state.devices]
      ..sort((left, right) {
        final leftActive = left.id == activeDeviceId;
        final rightActive = right.id == activeDeviceId;
        if (leftActive != rightActive) return leftActive ? -1 : 1;
        if (left.online != right.online) return left.online ? -1 : 1;
        return (right.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              left.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            );
      });

    Future<void> runAction(
      Future<void> Function() action,
      String successMessage,
    ) async {
      try {
        await action();
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(successMessage)));
        }
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
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
      if (name == null) return;
      await runAction(
        () => controller.renameDevice(device.id, name),
        'Device renamed.',
      );
    }

    Future<void> transferTo(PlaybackDevice device) => runAction(
      () => controller.handoffTo(device.id),
      'Playback switched to ${device.name}.',
    );

    Future<void> disconnectThisDevice() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Disconnect this device?'),
          content: const Text(
            'Playback on this device will stop. You can reconnect it later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await runAction(
          controller.disconnectThisDevice,
          'This device is disconnected.',
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Connected devices')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (!settings.configured)
            const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('Sign in to connect your devices'),
              subtitle: Text(
                'Only devices signed in to the same GMusic account can appear here.',
              ),
            )
          else ...[
            if (session?.activeDeviceId != null)
              _ActivePlaybackCard(
                session: session!,
                device: state.activeDevice,
                onCommand: (action, payload) => runAction(
                  () => controller.sendCommand(action, payload: payload),
                  'Playback command sent.',
                ),
              )
            else
              const ListTile(
                leading: Icon(Icons.music_off_rounded),
                title: Text('No active playback device'),
                subtitle: Text('Start playing music on any connected device.'),
              ),
            SwitchListTile(
              title: const Text('Show this device to my account'),
              subtitle: const Text(
                'Other signed-in GMusic devices can connect to this player.',
              ),
              value: state.deviceVisible,
              onChanged: (visible) => runAction(
                () => controller.setDeviceVisibility(visible),
                visible ? 'This device is visible.' : 'This device is hidden.',
              ),
            ),
            if (state.error != null)
              ListTile(
                leading: Icon(
                  Icons.error_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(state.error!),
                trailing: IconButton(
                  tooltip: 'Retry',
                  onPressed: controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Devices on this account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (devices.isEmpty)
              const ListTile(
                leading: Icon(Icons.devices_other_rounded),
                title: Text('No devices found'),
                subtitle: Text(
                  'Open GMusic on another device and sign in to the same account.',
                ),
              )
            else
              for (final device in devices)
                ListTile(
                  leading: Icon(
                    device.id == activeDeviceId
                        ? Icons.graphic_eq_rounded
                        : _deviceIcon(device.platform),
                    color: device.id == activeDeviceId
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(device.name),
                  subtitle: Text(
                    device.id == activeDeviceId
                        ? '${session?.playing == true ? 'Playing' : 'Paused'} · ${session?.title ?? 'Playback'}'
                        : device.online
                        ? 'Available'
                        : 'Offline',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.transferInProgress &&
                          state.transferTargetId == device.id)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (device.id == activeDeviceId)
                        const Icon(Icons.check_circle_rounded),
                      PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'switch':
                              transferTo(device);
                            case 'rename':
                              renameDevice(device);
                            case 'disconnect':
                              disconnectThisDevice();
                            case 'forget':
                              runAction(
                                () => controller.forgetOfflineDevice(device.id),
                                'Offline device removed.',
                              );
                          }
                        },
                        itemBuilder: (_) => [
                          if (device.online && device.id != activeDeviceId)
                            const PopupMenuItem(
                              value: 'switch',
                              child: Text('Switch playback here'),
                            ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename device'),
                          ),
                          if (device.id == state.deviceId)
                            const PopupMenuItem(
                              value: 'disconnect',
                              child: Text('Disconnect this device'),
                            ),
                          if (!device.online && device.id != state.deviceId)
                            const PopupMenuItem(
                              value: 'forget',
                              child: Text('Forget offline device'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  onTap: device.online && device.id != activeDeviceId
                      ? () => transferTo(device)
                      : null,
                ),
            if (state.deviceId != null &&
                !devices.any((device) => device.id == state.deviceId))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () => runAction(
                    controller.reconnectThisDevice,
                    'This device is connected.',
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reconnect this device'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Playback runs on GMusic devices. TVs and speakers need their own GMusic player app.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _deviceIcon(String platform) => switch (platform) {
    'android' => Icons.phone_android_rounded,
    'ios' => Icons.phone_iphone_rounded,
    'windows' || 'linux' || 'web' => Icons.laptop_windows_rounded,
    'macos' => Icons.laptop_mac_rounded,
    _ => Icons.devices_other_rounded,
  };
}

class _ActivePlaybackCard extends StatelessWidget {
  const _ActivePlaybackCard({
    required this.session,
    required this.device,
    required this.onCommand,
  });

  final RemotePlaybackSession session;
  final PlaybackDevice? device;
  final Future<void> Function(String action, Map<String, dynamic> payload)
  onCommand;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Listening on ${device?.name ?? 'an unavailable device'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('${session.title} · ${session.artist}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Previous track',
                onPressed: () => onCommand('previous', const {}),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filled(
                tooltip: session.playing ? 'Pause' : 'Play',
                onPressed: () =>
                    onCommand(session.playing ? 'pause' : 'play', const {}),
                icon: Icon(
                  session.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Next track',
                onPressed: () => onCommand('next', const {}),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          if (device?.capabilities.volume ?? true)
            _DeviceVolumeSlider(
              volume: session.volume,
              onChangeEnd: (value) => onCommand('volume', {'volume': value}),
            ),
        ],
      ),
    ),
  );
}

class _DeviceVolumeSlider extends StatefulWidget {
  const _DeviceVolumeSlider({required this.volume, required this.onChangeEnd});

  final double volume;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_DeviceVolumeSlider> createState() => _DeviceVolumeSliderState();
}

class _DeviceVolumeSliderState extends State<_DeviceVolumeSlider> {
  double? _value;

  @override
  void didUpdateWidget(covariant _DeviceVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volume != widget.volume) _value = null;
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.volume_down_rounded),
      Expanded(
        child: Slider(
          value: (_value ?? widget.volume).clamp(0.0, 1.0).toDouble(),
          onChanged: (value) => setState(() => _value = value),
          onChangeEnd: (value) {
            widget.onChangeEnd(value);
            setState(() => _value = null);
          },
        ),
      ),
      const Icon(Icons.volume_up_rounded),
    ],
  );
}
