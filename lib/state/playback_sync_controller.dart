import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback.dart';
import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';

const _deviceIdKey = 'playback_device_id_v1';
const _deviceNameKey = 'playback_device_name_v1';
const _deviceVisibleKey = 'playback_device_visible_v1';

class PlaybackSyncController extends StateNotifier<RemotePlaybackState> {
  PlaybackSyncController(this._preferences, this._settings, this._handler)
    : super(const RemotePlaybackState()) {
    _subscription = _handler.remoteStateStream.listen(_onRemoteState);
    unawaited(configure(_settings.state));
  }

  final SharedPreferences _preferences;
  final SettingsController _settings;
  final GMusicAudioHandler _handler;
  late final StreamSubscription<RemotePlaybackState> _subscription;
  int _generation = 0;
  PlaybackDeviceIdentity? _identity;
  DriveBridgeClient? _configuredClient;
  String? _configuredUserId;
  String? _remoteQueueKey;
  String? _offlineFailoverAttemptKey;

  Future<void> configure(SettingsState settings) async {
    final generation = ++_generation;
    if (!settings.configured || settings.user == null) {
      if (_configuredClient != null && _identity != null) {
        unawaited(
          _configuredClient!.disconnectPlaybackDevice(_identity!.id).catchError(
            (Object error) {
              state = state.copyWith(
                error: 'Could not disconnect this device: $error',
              );
            },
          ),
        );
        _handler.stopForAccountChange();
      }
      _identity = null;
      _configuredClient = null;
      _configuredUserId = null;
      _remoteQueueKey = null;
      _offlineFailoverAttemptKey = null;
      _handler.disableRemoteSync();
      state = const RemotePlaybackState();
      return;
    }

    final identity = _identity ?? await _loadOrCreateIdentity();
    if (generation != _generation) return;
    _identity = identity;
    final client = _settings.client();
    if (identical(_configuredClient, client) &&
        _configuredUserId == settings.user!.id) {
      return;
    }
    _remoteQueueKey = null;
    _configuredClient = client;
    _configuredUserId = settings.user!.id;
    state = RemotePlaybackState(
      deviceId: identity.id,
      syncing: true,
      deviceName: identity.name,
      deviceVisible: identity.visible,
    );
    _handler.configureRemoteSync(
      client: client,
      identity: identity,
      userId: settings.user!.id,
    );
  }

  Future<void> handoffTo(String deviceId) => _handler.handoffTo(deviceId);

  Future<void> renameDevice(String deviceId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError.value(name, 'name', 'Use 1 to 80 characters.');
    }
    final client = _configuredClient;
    if (client == null) throw StateError('Sign in to manage playback devices.');
    await client.renamePlaybackDevice(deviceId, trimmed);
    if (deviceId == _identity?.id) {
      _identity = _identity!.copyWith(name: trimmed);
      await _preferences.setString(_deviceNameKey, trimmed);
      _handler.updateRemoteIdentity(_identity!);
    }
    await refresh();
  }

  Future<void> setDeviceVisibility(bool visible) async {
    final identity = _identity;
    final client = _configuredClient;
    if (identity == null || client == null) {
      throw StateError('Sign in to manage playback devices.');
    }
    await client.setPlaybackDeviceVisibility(identity.id, visible: visible);
    _identity = identity.copyWith(visible: visible);
    await _preferences.setBool(_deviceVisibleKey, visible);
    _handler.updateRemoteIdentity(_identity!);
    state = state.copyWith(deviceVisible: visible);
  }

  Future<void> forgetOfflineDevice(String deviceId) async {
    final client = _configuredClient;
    if (client == null) throw StateError('Sign in to manage playback devices.');
    await client.forgetPlaybackDevice(deviceId);
    await refresh();
  }

  Future<void> disconnectThisDevice() async {
    final identity = _identity;
    await _handler.disconnectRemoteDevice();
    if (identity == null) return;
    state = RemotePlaybackState(
      deviceId: identity.id,
      devices: state.devices
          .where((device) => device.id != identity.id)
          .toList(),
      deviceName: identity.name,
      deviceVisible: identity.visible,
    );
  }

  Future<void> reconnectThisDevice() async {
    final identity = _identity;
    final client = _configuredClient;
    final userId = _configuredUserId;
    if (identity == null || client == null || userId == null) {
      throw StateError('Sign in to connect this device.');
    }
    state = RemotePlaybackState(
      deviceId: identity.id,
      deviceName: identity.name,
      deviceVisible: identity.visible,
      syncing: true,
    );
    _handler.configureRemoteSync(
      client: client,
      identity: identity,
      userId: userId,
    );
    await _handler.pollRemoteNow();
  }

  Future<void> sendCommand(
    String action, {
    Map<String, dynamic> payload = const {},
  }) => _handler.sendRemoteCommand(action, payload: payload);

  Future<void> refresh() {
    _remoteQueueKey = null;
    return _handler.pollRemoteNow();
  }

  void _onRemoteState(RemotePlaybackState next) {
    _considerOfflineFailover(next);
    final session = next.session;
    if (session == null || session.trackIds.isEmpty) {
      _remoteQueueKey = null;
      state = next.copyWith(clearRemoteQueue: true);
      return;
    }

    final queueKey = session.trackIds.join('\u0000');
    if (!next.remoteTargeted) {
      if (_remoteQueueKey == queueKey &&
          (state.remoteQueue.isNotEmpty || state.remoteQueueLoading)) {
        state = next.copyWith(
          remoteQueue: state.remoteQueue,
          remoteQueueLoading: state.remoteQueueLoading,
          remoteQueueError: state.remoteQueueError,
        );
        return;
      }

      final localQueue = _handler.currentUiState.queue;
      if (_matchesTrackIds(localQueue, session.trackIds)) {
        _remoteQueueKey = queueKey;
        state = next.copyWith(
          remoteQueue: localQueue,
          remoteQueueLoading: false,
          clearRemoteQueueError: true,
        );
      } else {
        _remoteQueueKey = null;
        state = next.copyWith(clearRemoteQueue: true);
      }
      return;
    }

    if (_remoteQueueKey == queueKey) {
      state = next.copyWith(
        remoteQueue: state.remoteQueue,
        remoteQueueLoading: state.remoteQueueLoading,
        remoteQueueError: state.remoteQueueError,
      );
      return;
    }

    _remoteQueueKey = queueKey;
    state = next.copyWith(
      remoteQueue: const [],
      remoteQueueLoading: session.trackIds.isNotEmpty,
      clearRemoteQueueError: true,
    );
    if (session.trackIds.isEmpty) return;

    final client = _configuredClient;
    if (client == null) {
      state = state.copyWith(
        remoteQueueLoading: false,
        remoteQueueError:
            'Could not sync remote queue: connection unavailable.',
      );
      return;
    }
    unawaited(
      _loadRemoteQueue(client, session.trackIds, queueKey, _generation),
    );
  }

  bool _matchesTrackIds(List<Track> tracks, List<String> trackIds) {
    if (tracks.length != trackIds.length) return false;
    for (var index = 0; index < tracks.length; index += 1) {
      if (tracks[index].id != trackIds[index]) return false;
    }
    return true;
  }

  void _considerOfflineFailover(RemotePlaybackState remoteState) {
    final identity = _identity;
    final session = remoteState.session;
    if (identity == null ||
        session == null ||
        session.trackIds.isEmpty ||
        session.activeDeviceId == null ||
        session.activeDeviceId == identity.id) {
      _offlineFailoverAttemptKey = null;
      return;
    }
    if (remoteState.transferInProgress) return;

    if (!remoteState.canFailoverToThisDevice) {
      final activeDevice = remoteState.activeDevice;
      if (activeDevice?.online == true) {
        _offlineFailoverAttemptKey = null;
      }
      return;
    }

    final attemptKey =
        '${session.activeDeviceId}:${session.queueRevision}:${identity.id}';
    if (_offlineFailoverAttemptKey == attemptKey) return;
    _offlineFailoverAttemptKey = attemptKey;
    unawaited(_handler.handoffTo(identity.id).catchError((Object _) {}));
  }

  Future<void> _loadRemoteQueue(
    DriveBridgeClient client,
    List<String> trackIds,
    String queueKey,
    int generation,
  ) async {
    try {
      final resolved = await client.catalogTracksByIds(trackIds);
      if (generation != _generation || queueKey != _remoteQueueKey) return;
      final byId = {for (final track in resolved) track.id: track};
      final tracks = trackIds.map((id) => byId[id]).toList();
      if (tracks.any((track) => track == null)) {
        throw StateError('One or more queued tracks are unavailable.');
      }
      state = state.copyWith(
        remoteQueue: tracks.cast<Track>(),
        remoteQueueLoading: false,
        clearRemoteQueueError: true,
      );
    } on Object catch (error) {
      if (generation != _generation || queueKey != _remoteQueueKey) return;
      state = state.copyWith(
        remoteQueueLoading: false,
        remoteQueueError: 'Could not sync remote queue: $error',
      );
    }
  }

  Future<PlaybackDeviceIdentity> _loadOrCreateIdentity() async {
    var id = _preferences.getString(_deviceIdKey);
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      final random = Random.secure();
      id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _preferences.setString(_deviceIdKey, id);
    }
    final suffix = id.substring(0, 4).toUpperCase();
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => ('Android device', 'android'),
      TargetPlatform.iOS => ('iPhone or iPad', 'ios'),
      TargetPlatform.windows => ('Windows PC', 'windows'),
      TargetPlatform.macOS => ('Mac', 'macos'),
      TargetPlatform.linux => ('Linux PC', 'linux'),
      TargetPlatform.fuchsia => ('GMusic device', 'unknown'),
    };
    final resolvedPlatform = kIsWeb ? ('Web player', 'web') : platform;
    return PlaybackDeviceIdentity(
      id: id,
      name:
          _preferences.getString(_deviceNameKey) ??
          '${resolvedPlatform.$1} · $suffix',
      platform: resolvedPlatform.$2,
      visible: _preferences.getBool(_deviceVisibleKey) ?? true,
    );
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_subscription.cancel());
    _handler.disableRemoteSync();
    super.dispose();
  }
}

final playbackSyncControllerProvider =
    StateNotifierProvider<PlaybackSyncController, RemotePlaybackState>((ref) {
      final controller = PlaybackSyncController(
        ref.watch(sharedPreferencesProvider),
        ref.watch(settingsControllerProvider.notifier),
        ref.watch(audioHandlerProvider),
      );
      ref.listen(settingsControllerProvider, (_, settings) {
        unawaited(controller.configure(settings));
      });
      return controller;
    });
