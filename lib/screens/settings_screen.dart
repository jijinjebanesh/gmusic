import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/drive_auth.dart';
import '../services/settings_store.dart';
import '../state/auth_controller.dart';
import 'playback_devices_screen.dart';

/// Bridge connection: URL, bearer token, theme, and the Drive sign-in.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final session = ref.watch(authControllerProvider);
    final auth = ref.watch(driveAuthControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Drive bridge'),
          _BridgeForm(settings: settings),
          const Divider(height: 24),
          const _SectionHeader('Account'),
          if (session.error != null)
            ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Account synchronization issue'),
              subtitle: Text(session.error!),
              trailing: TextButton(
                onPressed: session.working
                    ? null
                    : () => ref
                          .read(authControllerProvider.notifier)
                          .restoreSession(),
                child: session.working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Retry'),
              ),
            ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(settings.user?.label ?? 'Not signed in'),
            subtitle: Text(
              settings.user == null
                  ? 'Session expired. Sign in again.'
                  : 'Signed in. Favorites and history sync to your account.',
            ),
            trailing: TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              child: const Text('Sign out'),
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader('Connected devices'),
          ListTile(
            leading: const Icon(Icons.devices_rounded),
            title: const Text('Manage playback devices'),
            subtitle: const Text(
              'Rename devices, control visibility, or remove offline devices.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlaybackDevicesScreen(),
              ),
            ),
          ),
          const Divider(height: 24),
          _SectionHeader(
            auth.sharedMode ? 'Google Drive library (shared)' : 'Google Drive',
          ),
          ListTile(
            leading: Icon(
              auth.connected ? Icons.cloud_done : Icons.cloud_off,
              color: auth.connected
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(
              auth.checking
                  ? 'Checking backend…'
                  : auth.connected
                  ? 'Connected'
                  : 'Unavailable',
            ),
            subtitle: Text(
              auth.message ??
                  (auth.connected
                      ? auth.sharedMode
                            ? 'All GMusic accounts use this common Google Drive library.'
                            : 'This account has its own Google Drive connection.'
                      : auth.sharedMode
                      ? 'Connect the common Google Drive account for all GMusic users.'
                      : 'Connect a Drive account for this GMusic account.'),
            ),
            trailing: auth.checking || auth.working
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Refresh Drive status',
                    onPressed: () => ref
                        .read(driveAuthControllerProvider.notifier)
                        .checkStatus(),
                    icon: const Icon(Icons.refresh),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  if (auth.sharedMode)
                    OutlinedButton(
                      onPressed: auth.checking || auth.working
                          ? null
                          : () => _connectDrive(context, ref),
                      child: Text(auth.connected ? 'Reconnect' : 'Connect'),
                    )
                  else if (auth.connected)
                    OutlinedButton(
                      onPressed: auth.working
                          ? null
                          : () => _disconnectDrive(context, ref),
                      child: const Text('Disconnect'),
                    )
                  else if (!auth.connected)
                    FilledButton(
                      onPressed: auth.checking || auth.working
                          ? null
                          : () => _connectDrive(context, ref),
                      child: const Text('Connect'),
                    ),
                  if (auth.connected)
                    FilledButton.tonal(
                      onPressed: auth.working
                          ? null
                          : () => _syncDrive(context, ref),
                      child: const Text('Sync'),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (mode) {
              if (mode != null) controller.setThemeMode(mode);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('System'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('Light'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('Dark'),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('GMusic'),
            subtitle: Text(
              'Streams music from the common Google Drive library. '
              'Google credentials remain on the backend; signed-in users share this catalog.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDrive(BuildContext context, WidgetRef ref) async {
    try {
      final uri = await ref
          .read(driveAuthControllerProvider.notifier)
          .startOAuth();
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(
          'No browser app could open the Google authorization page.',
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finish Google authorization in your browser, then refresh Drive status.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect Google Drive: $error')),
        );
      }
    }
  }

  Future<void> _disconnectDrive(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(driveAuthControllerProvider.notifier).disconnect();
    } on Object {
      // The controller retains the failure message for the status row.
    }
  }

  Future<void> _syncDrive(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref
          .read(driveAuthControllerProvider.notifier)
          .sync();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Drive index: ${result['status'] ?? 'updated'}'),
          ),
        );
      }
    } on Object {
      // The controller retains the failure message for the status row.
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BridgeForm extends ConsumerStatefulWidget {
  const _BridgeForm({required this.settings});

  final SettingsState settings;

  @override
  ConsumerState<_BridgeForm> createState() => _BridgeFormState();
}

class _BridgeFormState extends ConsumerState<_BridgeForm> {
  late final TextEditingController _url;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.settings.bridgeUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Bridge URL',
              hintText: 'https://gmusicbackend.vercel.app/',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    await ref
                        .read(settingsControllerProvider.notifier)
                        .saveBridgeUrl(_url.text);
                    await ref
                        .read(driveAuthControllerProvider.notifier)
                        .checkStatus();
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bridge settings saved')),
                    );
                  },
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
