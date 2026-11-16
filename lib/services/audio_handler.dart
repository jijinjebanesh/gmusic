import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playback.dart';
import '../models/track.dart';
import 'drive_bridge_client.dart';

/// Injected in main(); the single [AudioPlayer] lives inside the handler.
final audioHandlerProvider = Provider<GMusicAudioHandler>(
  (ref) => throw UnimplementedError(
    'audioHandlerProvider must be overridden in main()',
  ),
);

/// Snapshot of everything the player UI needs, emitted on any change so the
/// widget tree rebuilds from one source of truth.
class PlayerUiState {
  const PlayerUiState({
    this.track,
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.buffering = false,
    this.shuffle = false,
    this.repeat = AudioServiceRepeatMode.none,
    this.error,
  });

  final Track? track;
  final List<Track> queue;
  final int index;
  final bool playing;
  final bool buffering;
  final bool shuffle;
  final AudioServiceRepeatMode repeat;
  final String? error;

  PlayerUiState copyWith({
    Track? track,
    bool clearTrack = false,
    List<Track>? queue,
    int? index,
    bool? playing,
    bool? buffering,
    bool? shuffle,
    AudioServiceRepeatMode? repeat,
    String? error,
    bool clearError = false,
  }) => PlayerUiState(
    track: clearTrack ? null : (track ?? this.track),
    queue: queue ?? this.queue,
    index: index ?? this.index,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    shuffle: shuffle ?? this.shuffle,
    repeat: repeat ?? this.repeat,
    error: clearError ? null : (error ?? this.error),
  );
}

class _RemoteWorkItem {
  const _RemoteWorkItem(this.generation, this.run);

  final int generation;
  final Future<void> Function() run;
}

typedef _RemoteCommandOutcome = ({bool succeeded, String? error});

class GMusicAudioHandler extends BaseAudioHandler with SeekHandler {
  GMusicAudioHandler() {
    _subscriptions.addAll([
      _player.playerStateStream.listen(_onPlayerState),
      _player.positionStream.listen((position) {
        _positionController.add(position);
        _schedulePositionSave();
        _publishPlaybackState();
      }),
      _player.durationStream.listen(_onDuration),
      _player.volumeStream.listen(_volumeController.add),
    ]);
    _publishPlaybackState();
  }

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // _queue keeps the original library order; _order is what plays (shuffle
  // moves the picked track to the front). Both are kept in sync on edits.
  List<Track> _queue = [];
  List<Track> _order = [];
  List<int> _orderIndices = [];
  int _index = 0;
  int _playRequestId = 0;
  bool _shuffle = false;
  bool _switchingSource = false;
  bool _pendingAutoplay = false;
  AudioServiceRepeatMode _repeat = AudioServiceRepeatMode.none;
  bool _retried = false;
  bool _loadedSource = false;
  SharedPreferences? _preferences;
  bool _restored = false;
  Duration _resumePosition = Duration.zero;
  Timer? _positionSaveTimer;
  bool _resumeAfterInterruption = false;
  double? _volumeBeforeDucking;
  String? _backendOrigin;
  DriveBridgeClient? _remoteClient;
  PlaybackDeviceIdentity? _remoteIdentity;
  String? _remoteUserId;
  Timer? _remotePollTimer;
  Timer? _remotePositionTimer;
  Timer? _remoteSocketHeartbeatTimer;
  Timer? _remoteSocketSnapshotTimer;
  Timer? _remoteSocketReconnectTimer;
  PlaybackSocketConnection? _remoteSocket;
  StreamSubscription<Map<String, dynamic>>? _remoteSocketSubscription;
  bool _remotePollInFlight = false;
  bool _remoteSocketReady = false;
  bool _remoteSocketCrossInstance = false;
  bool _remoteSocketConnecting = false;
  bool _remoteClaimRequested = false;
  bool _playbackEpochResetPending = false;
  bool _applyingRemoteCommand = false;
  bool _remoteWorkInFlight = false;
  int _remoteGeneration = 0;
  int _remoteSocketReconnectAttempt = 0;
  final Map<String, _RemoteCommandOutcome> _processedRemoteCommands = {};
  final Set<String> _queuedRemoteCommandIds = {};
  final List<_RemoteWorkItem> _remoteWorkQueue = [];
  RemotePlaybackState _remoteState = const RemotePlaybackState();
  String? _preparedHandoffId;
  String? _preparedHandoffSignature;

  static const _queueStorageKey = 'playback_queue_v1';
  static const _remoteCommandsStorageKey = 'remote_commands_v1';

  /// Configures Android/iOS audio focus and routes headset removal and system
  /// interruptions through the same player used by the media notification.
  Future<void> configureAudioSession() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(session.interruptionEventStream.listen(_onInterruption));
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        _resumeAfterInterruption = false;
        unawaited(pause());
      }),
    );
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      _resumeAfterInterruption = _player.playing;
      switch (event.type) {
        case AudioInterruptionType.duck:
          _volumeBeforeDucking ??= _player.volume;
          unawaited(_player.setVolume(_volumeBeforeDucking! * 0.2));
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          unawaited(_player.pause());
      }
      _emit();
      return;
    }
    final priorVolume = _volumeBeforeDucking;
    _volumeBeforeDucking = null;
    if (priorVolume != null) unawaited(_player.setVolume(priorVolume));
    if (_resumeAfterInterruption &&
        event.type != AudioInterruptionType.unknown) {
      _resumeAfterInterruption = false;
      unawaited(play());
    } else {
      _resumeAfterInterruption = false;
    }
  }

  void _schedulePositionSave() {
    if (_preferences == null || _order.isEmpty) return;
    if (_positionSaveTimer?.isActive ?? false) return;
    _positionSaveTimer = Timer(const Duration(seconds: 5), () {
      _persistQueue(position: _player.position);
    });
  }

  /// Queue state is restored without autoplay. Stream tickets are refreshed
  /// on demand through [refresher] if a persisted URL has expired.
  Future<void> restoreQueue(SharedPreferences preferences) async {
    if (_restored) return;
    _preferences = preferences;
    _restored = true;
    for (final saved
        in preferences.getStringList(_remoteCommandsStorageKey) ?? const []) {
      if (!saved.startsWith('{')) {
        _processedRemoteCommands[saved] = (succeeded: true, error: null);
        continue;
      }
      final result = Map<String, dynamic>.from(jsonDecode(saved) as Map);
      final id = result['id'] as String?;
      if (id != null && id.isNotEmpty) {
        _processedRemoteCommands[id] = (
          succeeded: result['succeeded'] == true,
          error: result['error'] as String?,
        );
      }
    }
    final raw = preferences.getString(_queueStorageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _queue = (saved['queue'] as List? ?? const [])
          .map((item) => Track.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      final indices = (saved['orderIndices'] as List? ?? const [])
          .map((value) => int.tryParse(value.toString()) ?? -1)
          .where((index) => index >= 0 && index < _queue.length)
          .toList();
      _orderIndices = indices.isEmpty
          ? List.generate(_queue.length, (index) => index)
          : indices;
      _order = _orderIndices.map((index) => _queue[index]).toList();
      _index = (int.tryParse(saved['index']?.toString() ?? '') ?? 0).clamp(
        0,
        math.max(0, _order.length - 1),
      );
      _shuffle = saved['shuffle'] == true;
      _resumePosition = Duration(
        milliseconds: int.tryParse(saved['positionMs']?.toString() ?? '') ?? 0,
      );
      _repeat = switch (saved['repeat']) {
        'all' => AudioServiceRepeatMode.all,
        'one' => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
      if (_repeat == AudioServiceRepeatMode.one) {
        await _player.setLoopMode(LoopMode.one);
      }
      queue.add(_order.map(_toMediaItem).toList());
      if (_order.isNotEmpty) mediaItem.add(_toMediaItem(_order[_index]));
      _emit();
    } on Object {
      _queue = [];
      _order = [];
      _orderIndices = [];
      _index = 0;
      await preferences.remove(_queueStorageKey);
    }
  }

  void _persistQueue({Duration? position}) {
    final preferences = _preferences;
    if (preferences == null) return;
    final repeat = switch (_repeat) {
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
      AudioServiceRepeatMode.one => 'one',
      _ => 'none',
    };
    unawaited(
      preferences
          .setString(
            _queueStorageKey,
            jsonEncode({
              'queue': _queue.map((track) => track.toJson()).toList(),
              'orderIndices': _orderIndices,
              'index': _index,
              'shuffle': _shuffle,
              'repeat': repeat,
              'positionMs': (position ?? _player.position).inMilliseconds,
            }),
          )
          .then((_) {})
          .catchError((Object error) {
            _emit(
              _current.copyWith(error: 'Could not save playback queue: $error'),
            );
          }),
    );
  }

  /// Set by the library controller: fetches the same track again with a fresh
  /// stream ticket when a ticket expires mid-playback (tickets last 8 hours).
  Future<Track?> Function(String id)? refresher;

  void setBridgeUrl(String bridgeUrl) {
    _backendOrigin = _originForUrl(bridgeUrl);
  }

  void configureRemoteSync({
    required DriveBridgeClient client,
    required PlaybackDeviceIdentity identity,
    required String userId,
  }) {
    if (identical(_remoteClient, client) &&
        _remoteIdentity?.id == identity.id &&
        _remoteUserId == userId) {
      return;
    }
    _remoteGeneration += 1;
    _closeRemoteSocket();
    _remotePollTimer?.cancel();
    _remotePositionTimer?.cancel();
    _remoteSocketHeartbeatTimer?.cancel();
    _remoteSocketSnapshotTimer?.cancel();
    _remoteSocketReconnectTimer?.cancel();
    _remoteClient = client;
    _remoteIdentity = identity;
    _remoteUserId = userId;
    _remoteSocketReady = false;
    _remoteSocketCrossInstance = false;
    _remoteSocketConnecting = false;
    _remoteSocketReconnectAttempt = 0;
    _remoteClaimRequested = _player.playing;
    _remoteWorkQueue.clear();
    _queuedRemoteCommandIds.clear();
    _setRemoteState(RemotePlaybackState(deviceId: identity.id, syncing: true));
    final generation = _remoteGeneration;
    _remotePollTimer = Timer(const Duration(seconds: 4), () {
      if (generation == _remoteGeneration && !_remoteSocketReady) {
        _startRemoteFallbackPolling();
      }
    });
    unawaited(_connectRemoteSocket(generation));
  }

  void disableRemoteSync() {
    _remoteGeneration += 1;
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _remotePositionTimer?.cancel();
    _remotePositionTimer = null;
    _remoteSocketHeartbeatTimer?.cancel();
    _remoteSocketHeartbeatTimer = null;
    _remoteSocketSnapshotTimer?.cancel();
    _remoteSocketSnapshotTimer = null;
    _remoteSocketReconnectTimer?.cancel();
    _remoteSocketReconnectTimer = null;
    _closeRemoteSocket();
    _remoteSocketReady = false;
    _remoteSocketCrossInstance = false;
    _remoteSocketConnecting = false;
    _remoteClient = null;
    _remoteIdentity = null;
    _remoteUserId = null;
    _remoteClaimRequested = false;
    _remoteWorkQueue.clear();
    _queuedRemoteCommandIds.clear();
    _setRemoteState(const RemotePlaybackState());
  }

  void _closeRemoteSocket() {
    final subscription = _remoteSocketSubscription;
    _remoteSocketSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final socket = _remoteSocket;
    _remoteSocket = null;
    if (socket != null) unawaited(socket.close());
  }

  void _startRemoteFallbackPolling() {
    if (_remoteClient == null || _remoteIdentity == null) return;
    _remotePollTimer?.cancel();
    _remotePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(pollRemoteNow());
    });
    unawaited(pollRemoteNow());
  }

  Future<void> _connectRemoteSocket(int generation) async {
    final client = _remoteClient;
    final identity = _remoteIdentity;
    if (client == null ||
        identity == null ||
        generation != _remoteGeneration ||
        _remoteSocketConnecting ||
        _remoteSocketReady) {
      return;
    }
    _remoteSocketConnecting = true;
    try {
      final socket = await client.connectPlaybackSocket(
        device: identity,
        snapshot: _remoteSnapshot(),
        claim: _remoteClaimRequested && _player.playing,
      );
      if (generation != _remoteGeneration) {
        await socket.close();
        return;
      }
      _remoteSocket = socket;
      _remoteSocketSubscription = socket.stream.listen(
        (message) => unawaited(_handleRemoteSocketMessage(message, generation)),
        onError: (Object error) =>
            _onRemoteSocketUnavailable(generation, error),
        onDone: () => _onRemoteSocketUnavailable(generation, null),
      );
      await _handleRemoteSocketMessage(socket.initialMessage, generation);
    } on Object catch (error) {
      _onRemoteSocketUnavailable(generation, error);
    } finally {
      if (generation == _remoteGeneration) {
        _remoteSocketConnecting = false;
      }
    }
  }

  Future<void> _handleRemoteSocketMessage(
    Map<String, dynamic> decoded,
    int generation,
  ) async {
    if (generation != _remoteGeneration) return;
    try {
      final type = decoded['type'];
      if (type == 'disconnect') {
        _onRemoteSocketUnavailable(
          generation,
          StateError(decoded['error']?.toString() ?? 'socket_disconnected'),
        );
        return;
      }
      if (type == 'ready') {
        _remoteSocketReady = true;
        _remoteSocketCrossInstance = decoded['crossInstance'] == true;
        _remoteSocketReconnectAttempt = 0;
        _remoteSocketReconnectTimer?.cancel();
        _remoteSocketReconnectTimer = null;
        if (_remoteSocketCrossInstance) {
          _remotePollTimer?.cancel();
          _remotePollTimer = null;
          _remoteSocketHeartbeatTimer?.cancel();
          _remoteSocketHeartbeatTimer = Timer.periodic(
            const Duration(seconds: 4),
            (_) {
              _sendRemoteSocketHeartbeat(generation, includeSnapshot: false);
            },
          );
        } else {
          _remoteSocketHeartbeatTimer?.cancel();
          _remoteSocketHeartbeatTimer = null;
          _startRemoteFallbackPolling();
        }
      }
      if (type == 'error') {
        final error = decoded['error']?.toString() ?? 'socket_error';
        _setRemoteState(
          _remoteState.copyWith(error: 'Playback socket error: $error'),
        );
        return;
      }
      if (type != 'ready' && type != 'sync' && type != 'state') return;
      final rawResult = decoded['result'];
      if (rawResult is! Map) {
        throw const FormatException('Playback socket response is incomplete');
      }
      final responseReceivedAtMicros =
          decoded['clientResponseReceivedAtMonotonicMicros'];
      final responseReceivedAt = responseReceivedAtMicros is int
          ? Duration(microseconds: responseReceivedAtMicros)
          : null;
      final result = PlaybackPollResult.fromJson(
        Map<String, dynamic>.from(rawResult),
        clientRequestStartedAtMonotonic: _durationFromMicros(
          decoded['clientRequestStartedAtMonotonicMicros'],
        ),
        clientResponseReceivedAtMonotonic: responseReceivedAt,
        serverTimeAtReceiptOverride: DateTime.tryParse(
          decoded['serverTimeAtReceipt']?.toString() ?? '',
        ),
      );
      await _applyRemotePollResult(
        result,
        generation: generation,
        claim: type == 'ready' && _remoteClaimRequested && _player.playing,
        preserveDevices: type == 'state',
      );
    } on Object catch (error) {
      if (generation == _remoteGeneration) {
        _setRemoteState(
          _remoteState.copyWith(
            error: 'Could not read playback socket update: $error',
          ),
        );
      }
    }
  }

  void _sendRemoteSocketHeartbeat(
    int generation, {
    bool includeSnapshot = true,
  }) {
    final socket = _remoteSocket;
    if (socket == null ||
        generation != _remoteGeneration ||
        !_remoteSocketReady ||
        !_remoteSocketCrossInstance) {
      return;
    }
    try {
      final claim = _remoteClaimRequested && _player.playing;
      socket.sendHeartbeat(
        includeSnapshot || claim ? _remoteSnapshot() : null,
        claim: claim,
      );
    } on Object catch (error) {
      _onRemoteSocketUnavailable(generation, error);
    }
  }

  void _scheduleRemoteSocketSnapshot() {
    final identity = _remoteIdentity;
    if (!_remoteSocketReady ||
        !_remoteSocketCrossInstance ||
        identity == null ||
        (_remoteState.session?.activeDeviceId != identity.id &&
            !_remoteClaimRequested) ||
        _remoteSocketSnapshotTimer?.isActive == true) {
      return;
    }
    final generation = _remoteGeneration;
    _remoteSocketSnapshotTimer = Timer(const Duration(milliseconds: 800), () {
      _remoteSocketSnapshotTimer = null;
      if (generation == _remoteGeneration) {
        _sendRemoteSocketHeartbeat(generation);
      }
    });
  }

  void _sendRemoteSnapshotImmediately() {
    final identity = _remoteIdentity;
    if (identity == null ||
        (_remoteState.session?.activeDeviceId != identity.id &&
            !_remoteClaimRequested)) {
      return;
    }
    _remoteSocketSnapshotTimer?.cancel();
    _remoteSocketSnapshotTimer = null;
    final socket = _remoteSocket;
    if (_remoteSocketReady &&
        _remoteSocketCrossInstance &&
        socket != null &&
        socket.isConnected) {
      _sendRemoteSocketHeartbeat(_remoteGeneration);
    } else {
      unawaited(pollRemoteNow());
    }
  }

  void _onRemoteSocketUnavailable(int generation, Object? error) {
    if (generation != _remoteGeneration) return;
    if (_remoteSocket == null &&
        _remoteSocketReconnectTimer?.isActive == true) {
      return;
    }
    _remoteSocketReady = false;
    _remoteSocketCrossInstance = false;
    _remoteSocketHeartbeatTimer?.cancel();
    _remoteSocketHeartbeatTimer = null;
    _remoteSocketSnapshotTimer?.cancel();
    _remoteSocketSnapshotTimer = null;
    _closeRemoteSocket();
    if (error != null) {
      _setRemoteState(
        _remoteState.copyWith(error: 'Playback Socket.IO disconnected: $error'),
      );
    }
    _startRemoteFallbackPolling();
    _scheduleRemoteSocketReconnect(generation);
  }

  void _scheduleRemoteSocketReconnect(int generation) {
    if (generation != _remoteGeneration ||
        _remoteSocketReconnectTimer?.isActive == true) {
      return;
    }
    final seconds = math.min(30, 1 << _remoteSocketReconnectAttempt);
    _remoteSocketReconnectAttempt += 1;
    _remoteSocketReconnectTimer = Timer(Duration(seconds: seconds), () {
      _remoteSocketReconnectTimer = null;
      unawaited(_connectRemoteSocket(generation));
    });
  }

  Future<void> _applyRemotePollResult(
    PlaybackPollResult result, {
    required int generation,
    required bool claim,
    bool preserveDevices = false,
  }) async {
    if (generation != _remoteGeneration) return;
    final identity = _remoteIdentity;
    final client = _remoteClient;
    if (identity == null || client == null) return;
    final previousSession = _remoteState.session;
    final incomingSession = result.session;
    final session =
        previousSession != null &&
            incomingSession != null &&
            !incomingSession.isNewerThan(previousSession)
        ? previousSession
        : incomingSession;
    final acceptedSession =
        incomingSession != null &&
        (previousSession == null ||
            incomingSession.isNewerThan(previousSession));
    final wasActive = previousSession?.activeDeviceId == identity.id;
    final isActive = session?.activeDeviceId == identity.id;
    if (claim && isActive) _remoteClaimRequested = false;
    if (_playbackEpochResetPending &&
        acceptedSession &&
        session != null &&
        (previousSession == null ||
            session.playbackEpoch > previousSession.playbackEpoch)) {
      _playbackEpochResetPending = false;
    }
    _setRemoteState(
      RemotePlaybackState(
        deviceId: identity.id,
        devices: preserveDevices ? _remoteState.devices : result.devices,
        session: session,
        deviceName: identity.name,
        deviceVisible: identity.visible,
        transferId: _remoteState.transferId,
        transferTargetId: _remoteState.transferTargetId,
        transferInProgress: _remoteState.transferInProgress,
      ),
    );
    if (acceptedSession && session?.activeDeviceId != null && !isActive) {
      _remoteClaimRequested = false;
      final cancelPendingStart = _pendingAutoplay || _switchingSource;
      if (cancelPendingStart) {
        _playRequestId += 1;
        _pendingAutoplay = false;
        _switchingSource = false;
      }
      if (_player.playing) {
        await _player.pause();
        _emit();
      } else if (cancelPendingStart) {
        _emit();
      }
    } else if (acceptedSession &&
        wasActive &&
        session?.activeDeviceId == null &&
        _player.playing) {
      _remoteClaimRequested = true;
    } else if (acceptedSession &&
        isActive &&
        !wasActive &&
        !claim &&
        session != null) {
      if (_isPreparedHandoff(session, identity.id)) {
        _preparedHandoffId = null;
        _preparedHandoffSignature = null;
        _enqueueRemoteWork(generation, () async {
          await _player.setVolume(session.volume.clamp(0.0, 1.0).toDouble());
          _shuffle = session.shuffle;
          _repeat = switch (session.repeat) {
            'all' => AudioServiceRepeatMode.all,
            'one' => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          };
          await _player.setLoopMode(
            _repeat == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
          );
          if (!_player.playing || !_loadedSource) {
            await _player.seek(session.currentPosition);
            _persistQueue(position: session.currentPosition);
            if (session.playing) {
              unawaited(_playAudio(_order[_index], _playRequestId));
            }
          }
          _emit();
        });
      } else {
        _enqueueRemoteWork(
          generation,
          () => _applyRemoteSession(client, session, generation),
        );
      }
    }
    for (final command in result.commands) {
      if (_queuedRemoteCommandIds.add(command.id)) {
        _enqueueRemoteWork(generation, () async {
          try {
            await _processRemoteCommand(client, identity, command);
          } finally {
            _queuedRemoteCommandIds.remove(command.id);
          }
        });
      }
    }
  }

  Future<void> pollRemoteNow() async {
    final client = _remoteClient;
    final identity = _remoteIdentity;
    if (client == null || identity == null || _remotePollInFlight) return;
    final generation = _remoteGeneration;
    _remotePollInFlight = true;
    _setRemoteState(_remoteState.copyWith(syncing: true, clearError: true));
    try {
      final claim = _remoteClaimRequested && _player.playing;
      final result = await client.pollPlayback(
        device: identity,
        snapshot:
            _remoteWorkInFlight ||
                _remoteWorkQueue.isNotEmpty ||
                _applyingRemoteCommand
            ? null
            : _remoteSnapshot(),
        claim: claim,
      );
      if (generation != _remoteGeneration) return;
      await _applyRemotePollResult(
        result,
        generation: generation,
        claim: claim,
      );
    } on Object catch (error) {
      if (generation != _remoteGeneration) return;
      _setRemoteState(
        _remoteState.copyWith(error: 'Could not sync playback devices: $error'),
      );
    } finally {
      _remotePollInFlight = false;
      if (generation == _remoteGeneration) {
        _setRemoteState(_remoteState.copyWith(syncing: false));
      }
    }
  }

  void _enqueueRemoteWork(int generation, Future<void> Function() work) {
    _remoteWorkQueue.add(_RemoteWorkItem(generation, work));
    unawaited(_drainRemoteWork());
  }

  Future<void> _drainRemoteWork() async {
    if (_remoteWorkInFlight) return;
    _remoteWorkInFlight = true;
    try {
      while (_remoteWorkQueue.isNotEmpty) {
        final item = _remoteWorkQueue.removeAt(0);
        if (item.generation != _remoteGeneration) continue;
        try {
          await item.run();
        } on Object catch (error) {
          if (item.generation == _remoteGeneration) {
            _setRemoteState(
              _remoteState.copyWith(
                error: 'Could not sync remote playback: $error',
              ),
            );
          }
        }
      }
    } finally {
      _remoteWorkInFlight = false;
      if (_remoteWorkQueue.isNotEmpty) unawaited(_drainRemoteWork());
    }
  }

  Future<void> handoffTo(String deviceId) async {
    final client = _remoteClient;
    if (client == null) throw StateError('Sign in to use playback devices.');
    if (_remoteState.session?.activeDeviceId == _remoteIdentity?.id) {
      _remoteClaimRequested = false;
    }
    _setRemoteState(
      _remoteState.copyWith(
        transferInProgress: true,
        transferTargetId: deviceId,
        clearError: true,
      ),
    );
    try {
      final socket = _remoteSocket;
      final transfer =
          _remoteSocketReady && socket != null && socket.isConnected
          ? await socket.handoffPlayback(deviceId)
          : await client.handoffPlayback(deviceId);
      if (transfer.status == 'completed') {
        await pollRemoteNow();
        _setRemoteState(_remoteState.copyWith(clearTransfer: true));
        return;
      }
      final transferId = transfer.id;
      if (transferId == null) {
        throw StateError('The backend did not return a transfer identifier.');
      }
      _setRemoteState(_remoteState.copyWith(transferId: transferId));
      final activated = Completer<void>();
      final subscription = _remoteStateController.stream.listen((state) {
        if (state.session?.activeDeviceId == deviceId &&
            !activated.isCompleted) {
          activated.complete();
        }
      });
      try {
        for (var attempt = 0; attempt < 30; attempt += 1) {
          if (_remoteState.session?.activeDeviceId == deviceId) {
            _setRemoteState(_remoteState.copyWith(clearTransfer: true));
            return;
          }
          await Future.any([
            Future<void>.delayed(const Duration(seconds: 1)),
            activated.future,
          ]);
          if (_remoteState.session?.activeDeviceId == deviceId) {
            _setRemoteState(_remoteState.copyWith(clearTransfer: true));
            return;
          }
          final status = await client.playbackTransfer(transferId);
          if (status.status == 'completed') {
            await pollRemoteNow();
            _setRemoteState(_remoteState.copyWith(clearTransfer: true));
            return;
          }
          if (status.status == 'failed') {
            throw StateError(
              'Playback transfer failed'
              '${status.error == null ? '.' : ': ${status.error}'}',
            );
          }
        }
      } finally {
        await subscription.cancel();
      }
      throw StateError('Playback transfer timed out.');
    } on Object catch (error) {
      _setRemoteState(
        _remoteState.copyWith(
          clearTransfer: true,
          error: 'Could not switch playback device: $error',
        ),
      );
      rethrow;
    }
  }

  void updateRemoteIdentity(PlaybackDeviceIdentity identity) {
    if (_remoteIdentity?.id != identity.id) return;
    _remoteIdentity = identity;
    _setRemoteState(
      _remoteState.copyWith(
        deviceName: identity.name,
        deviceVisible: identity.visible,
      ),
    );
    unawaited(pollRemoteNow());
  }

  void stopForAccountChange() {
    if (_remoteState.session?.activeDeviceId != _remoteIdentity?.id) return;
    _applyingRemoteCommand = true;
    try {
      unawaited(_player.pause());
      clearQueue();
    } finally {
      _applyingRemoteCommand = false;
    }
  }

  Future<void> disconnectRemoteDevice() async {
    final client = _remoteClient;
    final identity = _remoteIdentity;
    if (identity != null &&
        _remoteState.session?.activeDeviceId == identity.id) {
      _applyingRemoteCommand = true;
      try {
        await _player.pause();
        clearQueue();
      } finally {
        _applyingRemoteCommand = false;
      }
    }
    disableRemoteSync();
    if (client != null && identity != null) {
      await client.disconnectPlaybackDevice(identity.id);
    }
  }

  Future<void> sendRemoteCommand(
    String action, {
    Map<String, dynamic> payload = const {},
  }) async {
    final client = _remoteClient;
    if (client == null) {
      throw StateError('Sign in to control playback devices.');
    }
    try {
      final socket = _remoteSocket;
      final session = _remoteState.session;
      final commandId =
          _remoteSocketReady &&
              socket != null &&
              socket.isConnected &&
              session != null
          ? await socket.sendPlaybackCommand(
              action,
              payload: payload,
              expectedQueueRevision:
                  action.startsWith('queue') || action == 'playQueue'
                  ? session.queueRevision
                  : null,
            )
          : await client.sendPlaybackCommand(action, payload: payload);
      if (_remoteSocketReady && socket != null && socket.isConnected) {
        try {
          final acknowledgement = await socket.waitForCommandResult(commandId);
          if (acknowledgement.status == 'ok') {
            if (_remoteSocketCrossInstance) {
              socket.requestSync();
            } else {
              await pollRemoteNow();
            }
            return;
          }
          if (acknowledgement.status != 'pending') {
            throw StateError(
              'Playback command ${acknowledgement.status}'
              '${acknowledgement.error == null ? '.' : ': ${acknowledgement.error}'}',
            );
          }
        } on TimeoutException {
          // The REST status endpoint is the durable fallback for missed events.
        }
      }
      var delayMs = 250;
      for (var attempt = 0; attempt < 8; attempt += 1) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          delayMs = math.min(delayMs + 250, 1_000);
        }
        final status = await client.playbackCommandStatus(commandId);
        if (status.status == 'ok') {
          if (_remoteSocketReady && _remoteSocketCrossInstance) {
            _remoteSocket?.requestSync();
          } else {
            await pollRemoteNow();
          }
          return;
        }
        if (status.status != 'pending') {
          throw StateError(
            'Playback command ${status.status}'
            '${status.error == null ? '.' : ': ${status.error}'}',
          );
        }
      }
      String? cancellationError;
      try {
        await client.cancelPlaybackCommand(commandId);
      } on Object catch (cancelError) {
        cancellationError = '$cancelError';
      }
      throw StateError(
        'Playback command timed out.'
        '${cancellationError == null ? '' : ' Cancellation failed: $cancellationError'}',
      );
    } on Object catch (error) {
      _setRemoteState(
        _remoteState.copyWith(error: 'Could not send playback command: $error'),
      );
      rethrow;
    }
  }

  PlaybackSnapshot _remoteSnapshot() {
    final track = _index < _order.length ? _order[_index] : null;
    final duration = _switchingSource
        ? track?.duration ?? Duration.zero
        : _player.duration ?? track?.duration ?? Duration.zero;
    final snapshot = PlaybackSnapshot(
      trackIds: _order.map((item) => item.id).toList(),
      index: _order.isEmpty ? 0 : _index,
      positionMs: (_switchingSource ? _resumePosition : _player.position)
          .inMilliseconds
          .clamp(0, 86_400_000)
          .toInt(),
      durationMs: duration.inMilliseconds.clamp(0, 86_400_000).toInt(),
      playing: !_switchingSource && _player.playing,
      shuffle: _shuffle,
      repeat: switch (_repeat) {
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => 'all',
        AudioServiceRepeatMode.one => 'one',
        _ => 'none',
      },
      title: track?.title ?? '',
      artist: track?.artist ?? '',
      volume: _player.volume,
      playbackEpoch: _remoteState.session?.playbackEpoch,
      advancePlaybackEpoch: _playbackEpochResetPending,
    );
    return snapshot;
  }

  bool _isPreparedHandoff(RemotePlaybackSession session, String deviceId) =>
      _preparedHandoffId != null &&
      _preparedHandoffSignature ==
          _handoffSignature(deviceId, session.trackIds, session.index);

  String _handoffSignature(String deviceId, List<String> trackIds, int index) =>
      '$deviceId:${trackIds.join('\u0000')}:$index';

  void _setRemoteState(RemotePlaybackState next) {
    _remoteState = next;
    if (!_remoteStateController.isClosed) _remoteStateController.add(next);
    final session = next.session;
    if (session?.playing == true && next.remoteTargeted) {
      _remotePositionTimer ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (_remoteState.session?.playing != true ||
              !_remoteState.remoteTargeted) {
            _remotePositionTimer?.cancel();
            _remotePositionTimer = null;
          } else if (!_remoteStateController.isClosed) {
            _remoteStateController.add(_remoteState);
          }
        },
      );
    } else {
      _remotePositionTimer?.cancel();
      _remotePositionTimer = null;
    }
  }

  void _markPlaybackEpochReset() {
    _playbackEpochResetPending = true;
  }

  Duration? _durationFromMicros(dynamic value) =>
      value is int ? Duration(microseconds: value) : null;

  bool get _shouldForwardToRemote =>
      !_applyingRemoteCommand && _remoteState.remoteTargeted;

  bool _forwardRemoteCommand(
    String action, {
    Map<String, dynamic> payload = const {},
  }) {
    if (!_shouldForwardToRemote) return false;
    unawaited(
      sendRemoteCommand(action, payload: payload).catchError((Object _) {}),
    );
    return true;
  }

  Future<void> _applyRemoteSession(
    DriveBridgeClient client,
    RemotePlaybackSession session,
    int generation, {
    bool? autoplay,
    bool fastHandoff = false,
  }) async {
    _applyingRemoteCommand = true;
    try {
      if (session.trackIds.isEmpty) {
        clearQueue();
        return;
      }
      if (session.index < 0 || session.index >= session.trackIds.length) {
        throw StateError('The remote queue index is invalid.');
      }
      var queueMatches = _order.length == session.trackIds.length;
      for (var index = 0; queueMatches && index < _order.length; index += 1) {
        queueMatches = _order[index].id == session.trackIds[index];
      }
      late final List<Track> resolvedTracks;
      var resolveQueueInBackground = false;
      if (queueMatches) {
        resolvedTracks = List.of(_order);
      } else if (fastHandoff) {
        final currentTrack = await client.catalogTrack(
          session.trackIds[session.index],
        );
        if (generation != _remoteGeneration) return;
        if (currentTrack == null) {
          throw StateError('The current track is no longer available.');
        }
        final existingTracks = {for (final track in _order) track.id: track};
        resolvedTracks = List.generate(session.trackIds.length, (index) {
          final id = session.trackIds[index];
          if (index == session.index) return currentTrack;
          return existingTracks[id] ??
              Track(id: id, name: 'Loading track', streamUrl: '');
        });
        resolveQueueInBackground = true;
      } else {
        final resolved = await client.catalogTracksByIds(session.trackIds);
        if (generation != _remoteGeneration) return;
        final byId = {for (final track in resolved) track.id: track};
        final tracks = session.trackIds.map((id) => byId[id]).toList();
        if (tracks.any((track) => track == null)) {
          throw StateError(
            'One or more queued tracks are no longer available.',
          );
        }
        resolvedTracks = tracks.cast<Track>();
      }
      _queue = resolvedTracks;
      _orderIndices = List.generate(resolvedTracks.length, (index) => index);
      _order = List.of(resolvedTracks);
      _index = session.index;
      _shuffle = session.shuffle;
      _repeat = switch (session.repeat) {
        'all' => AudioServiceRepeatMode.all,
        'one' => AudioServiceRepeatMode.one,
        _ => AudioServiceRepeatMode.none,
      };
      _retried = false;
      _resumePosition = session.currentPosition;
      await _player.setVolume(session.volume.clamp(0.0, 1.0).toDouble());
      await _player.setLoopMode(
        _repeat == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
      );
      if (generation != _remoteGeneration) return;
      queue.add(_order.map(_toMediaItem).toList());
      mediaItem.add(_toMediaItem(_order[_index]));
      _persistQueue(position: _resumePosition);
      _emit();
      await _playCurrent(autoplay: autoplay ?? session.playing);
      if (resolveQueueInBackground) {
        unawaited(
          _resolveRemoteQueueMetadata(
            client,
            List.of(session.trackIds),
            generation,
          ),
        );
      }
    } finally {
      _applyingRemoteCommand = false;
    }
  }

  Future<void> _resolveRemoteQueueMetadata(
    DriveBridgeClient client,
    List<String> trackIds,
    int generation,
  ) async {
    try {
      final resolved = await client.catalogTracksByIds(trackIds);
      if (generation != _remoteGeneration || !_queueMatchesTrackIds(trackIds)) {
        return;
      }
      final byId = {for (final track in resolved) track.id: track};
      final tracks = trackIds.map((id) => byId[id]).toList();
      if (tracks.any((track) => track == null)) {
        throw StateError('One or more queued tracks are no longer available.');
      }
      _queue = tracks.cast<Track>();
      _order = List.of(_queue);
      queue.add(_order.map(_toMediaItem).toList());
      if (_index < _order.length) mediaItem.add(_toMediaItem(_order[_index]));
      _persistQueue(position: _player.position);
      _emit();
    } on Object catch (error) {
      if (generation == _remoteGeneration && _queueMatchesTrackIds(trackIds)) {
        _setRemoteState(
          _remoteState.copyWith(
            error: 'Could not load the remote queue: $error',
          ),
        );
      }
    }
  }

  bool _queueMatchesTrackIds(List<String> trackIds) {
    if (_order.length != trackIds.length) return false;
    for (var index = 0; index < _order.length; index += 1) {
      if (_order[index].id != trackIds[index]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _acknowledgeRemoteCommand({
    required DriveBridgeClient client,
    required PlaybackDeviceIdentity identity,
    required String commandId,
    required bool succeeded,
    String? error,
  }) async {
    final socket = _remoteSocket;
    if (_remoteSocketReady && socket != null && socket.isConnected) {
      try {
        return await socket.acknowledgePlaybackCommand(
          commandId: commandId,
          succeeded: succeeded,
          error: error,
        );
      } on Object catch (socketError) {
        _setRemoteState(
          _remoteState.copyWith(
            error: 'Socket command acknowledgement failed: $socketError',
          ),
        );
      }
    }
    return client.acknowledgePlaybackCommand(
      commandId: commandId,
      deviceId: identity.id,
      succeeded: succeeded,
      error: error,
    );
  }

  Future<void> _processRemoteCommand(
    DriveBridgeClient client,
    PlaybackDeviceIdentity identity,
    PlaybackCommand command,
  ) async {
    final previousOutcome = _processedRemoteCommands[command.id];
    if (previousOutcome != null) {
      await _acknowledgeRemoteCommand(
        client: client,
        identity: identity,
        commandId: command.id,
        succeeded: previousOutcome.succeeded,
        error: previousOutcome.error,
      );
      return;
    }
    if (command.action == 'handoff') {
      var succeeded = false;
      String? failure;
      try {
        final payloadSession = command.payload['session'];
        final transferId = command.payload['transferId']?.toString();
        if (payloadSession is! Map ||
            transferId == null ||
            transferId.isEmpty) {
          throw StateError('The handoff session is invalid.');
        }
        final session = RemotePlaybackSession.fromJson(
          Map<String, dynamic>.from(payloadSession),
          serverTimeAtReceipt: command.serverTimeAtReceipt,
          monotonicAtReceipt: command.monotonicAtReceipt,
        );
        if (session.activeDeviceId == null ||
            session.activeDeviceId == identity.id) {
          throw StateError('The handoff source is invalid.');
        }
        await _applyRemoteSession(
          client,
          session,
          _remoteGeneration,
          autoplay: false,
          fastHandoff: true,
        );
        _preparedHandoffId = transferId;
        _preparedHandoffSignature = _handoffSignature(
          identity.id,
          session.trackIds,
          session.index,
        );
        succeeded = true;
      } on Object catch (error) {
        failure = error.toString();
      }
      await _rememberRemoteCommand(
        command.id,
        succeeded: succeeded,
        error: failure,
      );
      await _acknowledgeRemoteCommand(
        client: client,
        identity: identity,
        commandId: command.id,
        succeeded: succeeded,
        error: failure,
      );
      if (!succeeded && failure != null) {
        _setRemoteState(
          _remoteState.copyWith(error: 'Playback transfer failed: $failure'),
        );
      }
      return;
    }
    if (_remoteState.session?.activeDeviceId != identity.id) {
      await _acknowledgeRemoteCommand(
        client: client,
        identity: identity,
        commandId: command.id,
        succeeded: false,
        error: 'device_not_active',
      );
      await _rememberRemoteCommand(
        command.id,
        succeeded: false,
        error: 'device_not_active',
      );
      return;
    }
    var succeeded = false;
    String? failure;
    _applyingRemoteCommand = true;
    try {
      final payload = command.payload;
      switch (command.action) {
        case 'play':
          await play();
        case 'pause':
          if (payload['handoffTransferId'] is String) {
            await _pauseForHandoff(client, identity);
          } else {
            await pause();
          }
        case 'stop':
          clearQueue();
        case 'next':
          await skipToNext();
        case 'previous':
          await skipToPrevious();
        case 'seek':
          await seek(
            Duration(milliseconds: int.parse(payload['positionMs'].toString())),
          );
        case 'shuffle':
          await setShuffleMode(
            payload['enabled'] == true
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
          );
        case 'repeat':
          await setRepeatMode(switch (payload['mode']) {
            'all' => AudioServiceRepeatMode.all,
            'one' => AudioServiceRepeatMode.one,
            _ => AudioServiceRepeatMode.none,
          });
        case 'volume':
          await setVolume((payload['volume'] as num).toDouble());
        case 'playQueue':
          await _replaceQueue(
            client,
            (payload['trackIds'] as List).map((id) => id.toString()).toList(),
            int.parse(payload['index'].toString()),
            Duration(
              milliseconds:
                  int.tryParse(payload['positionMs']?.toString() ?? '') ?? 0,
            ),
            shuffle: payload['shuffle'] == true,
            repeat: payload['repeat'] as String? ?? 'none',
            autoplay: true,
          );
        case 'queueAdd':
          if (_order.length >= 500) {
            throw StateError('The remote queue is limited to 500 tracks.');
          }
          final track = await client.catalogTrack(payload['trackId'] as String);
          if (track == null) throw StateError('The track is unavailable.');
          if (payload['placement'] == 'next') {
            addNext(track);
          } else {
            addLast(track);
          }
        case 'queueRemove':
          final removeIndex = int.parse(payload['index'].toString());
          if (removeIndex >= _order.length) {
            throw StateError('The remote queue item is unavailable.');
          }
          removeAt(removeIndex);
        case 'queueReorder':
          final from = int.parse(payload['from'].toString());
          final to = int.parse(payload['to'].toString());
          if (from >= _order.length || to >= _order.length) {
            throw StateError('The remote queue item is unavailable.');
          }
          reorderQueue(from, to);
        case 'queuePlay':
          final queueIndex = int.parse(payload['index'].toString());
          if (queueIndex >= _order.length) {
            throw StateError('The remote queue item is unavailable.');
          }
          playQueueItem(queueIndex);
        case 'queueClear':
          clearQueue();
        default:
          throw StateError('Unsupported remote command: ${command.action}');
      }
      succeeded = true;
    } on Object catch (error) {
      failure = error.toString();
      _setRemoteState(
        _remoteState.copyWith(error: 'Remote command failed: $failure'),
      );
    } finally {
      _applyingRemoteCommand = false;
    }
    await _rememberRemoteCommand(
      command.id,
      succeeded: succeeded,
      error: failure,
    );
    await _acknowledgeRemoteCommand(
      client: client,
      identity: identity,
      commandId: command.id,
      succeeded: succeeded,
      error: failure,
    );
  }

  Future<void> _replaceQueue(
    DriveBridgeClient client,
    List<String> trackIds,
    int index,
    Duration position, {
    required bool shuffle,
    required String repeat,
    required bool autoplay,
  }) async {
    if (trackIds.isEmpty ||
        trackIds.length > 500 ||
        index < 0 ||
        index >= trackIds.length) {
      throw StateError('The remote queue is invalid.');
    }
    final resolved = await client.catalogTracksByIds(trackIds);
    final byId = {for (final track in resolved) track.id: track};
    final tracks = trackIds.map((id) => byId[id]).toList();
    if (tracks.any((track) => track == null)) {
      throw StateError('One or more queued tracks are no longer available.');
    }
    _queue = tracks.cast<Track>();
    _orderIndices = List.generate(_queue.length, (queueIndex) => queueIndex);
    if (shuffle) {
      final remaining = List.generate(_queue.length, (queueIndex) => queueIndex)
        ..remove(index)
        ..shuffle(_random);
      _orderIndices = [index, ...remaining];
      _index = 0;
    } else {
      _index = index;
    }
    _order = _orderIndices.map((queueIndex) => _queue[queueIndex]).toList();
    _shuffle = shuffle;
    _repeat = switch (repeat) {
      'all' => AudioServiceRepeatMode.all,
      'one' => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
    _retried = false;
    _resumePosition = position;
    await _player.setLoopMode(
      _repeat == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue(position: position);
    unawaited(_playCurrent(autoplay: autoplay));
  }

  Future<void> _pauseForHandoff(
    DriveBridgeClient client,
    PlaybackDeviceIdentity identity,
  ) async {
    _markPlaybackEpochReset();
    _remoteClaimRequested = false;
    _playRequestId += 1;
    _pendingAutoplay = false;
    _switchingSource = false;
    await _player.pause();
    _loadedSource = false;
    _persistQueue(position: _player.position);
    _emit(_current.copyWith(playing: false, buffering: false));

    final snapshot = _remoteSnapshot();
    final socket = _remoteSocket;
    if (_remoteSocketReady && socket != null && socket.isConnected) {
      await socket.sendHeartbeatAndWait(snapshot);
    } else {
      await client.pollPlayback(
        device: identity,
        snapshot: snapshot,
        claim: false,
      );
    }
  }

  Future<void> _rememberRemoteCommand(
    String commandId, {
    required bool succeeded,
    String? error,
  }) async {
    _processedRemoteCommands[commandId] = (succeeded: succeeded, error: error);
    while (_processedRemoteCommands.length > 100) {
      _processedRemoteCommands.remove(_processedRemoteCommands.keys.first);
    }
    final preferences = _preferences;
    if (preferences != null) {
      await preferences.setStringList(
        _remoteCommandsStorageKey,
        _processedRemoteCommands.entries
            .map(
              (entry) => jsonEncode({
                'id': entry.key,
                'succeeded': entry.value.succeeded,
                'error': entry.value.error,
              }),
            )
            .toList(),
      );
    }
  }

  Future<Track> refreshStreamUrlIfNeeded(Track track) async {
    final backendOrigin = _backendOrigin;
    if (track.localPath != null ||
        backendOrigin == null ||
        _originForUrl(track.streamUrl) == backendOrigin) {
      return track;
    }

    final refresh = refresher;
    if (refresh == null) {
      throw StateError('Playback is not ready to refresh this track URL.');
    }
    final refreshed = await refresh(track.id);
    if (refreshed == null) {
      throw StateError('The track is unavailable from the configured server.');
    }
    if (refreshed.id != track.id) {
      throw StateError('The server returned a different track.');
    }
    return refreshed;
  }

  final _uiController = StreamController<PlayerUiState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _remoteStateController =
      StreamController<RemotePlaybackState>.broadcast();
  final _random = math.Random();

  Stream<PlayerUiState> get uiStream => _uiController.stream;
  PlayerUiState get currentUiState => _current;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  Stream<RemotePlaybackState> get remoteStateStream =>
      _remoteStateController.stream;
  RemotePlaybackState get currentRemoteState => _remoteState;

  PlayerUiState get _current => PlayerUiState(
    track: _index < _order.length ? _order[_index] : null,
    queue: List.unmodifiable(_order),
    index: _index,
    playing: _player.playing,
    buffering:
        _switchingSource ||
        _player.processingState == ProcessingState.buffering ||
        _player.processingState == ProcessingState.loading,
    shuffle: _shuffle,
    repeat: _repeat,
  );

  void _emit([PlayerUiState? state]) {
    _uiController.add(state ?? _current);
    _publishPlaybackState();
  }

  void _onDuration(Duration? duration) {
    _durationController.add(duration);
    if (duration != null && _order.isNotEmpty && _index < _order.length) {
      final current = _order[_index];
      if (current.duration != duration) {
        final updated = current.copyWith(duration: duration);
        _order[_index] = updated;
        _queue[_orderIndices[_index]] = updated;
        _persistQueue();
        mediaItem.add(_toMediaItem(updated));
      }
    }
    _emit();
  }

  void _publishPlaybackState() {
    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _order.isEmpty ? null : _index,
        repeatMode: _repeat,
        shuffleMode: _shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
    _scheduleRemoteSocketSnapshot();
  }

  AudioPlayer get player => _player;

  // --- queue ----------------------------------------------------------------

  void playTracks(List<Track> tracks, int initialIndex) {
    if (tracks.isEmpty || initialIndex < 0 || initialIndex >= tracks.length) {
      return;
    }
    if (_shouldForwardToRemote) {
      if (tracks.length > 500) {
        _setRemoteState(
          _remoteState.copyWith(
            error: 'The remote queue is limited to 500 tracks.',
          ),
        );
        return;
      }
      _forwardRemoteCommand(
        'playQueue',
        payload: {
          'trackIds': tracks.map((track) => track.id).toList(),
          'index': initialIndex,
          'positionMs': 0,
          'shuffle': _shuffle,
          'repeat': _repeat == AudioServiceRepeatMode.one
              ? 'one'
              : _repeat == AudioServiceRepeatMode.all
              ? 'all'
              : 'none',
        },
      );
      return;
    }
    _queue = List.of(tracks);
    if (_shuffle) {
      final rest = List.generate(tracks.length, (index) => index)
        ..remove(initialIndex)
        ..shuffle(_random);
      _orderIndices = [initialIndex, ...rest];
      _index = 0;
    } else {
      _orderIndices = List.generate(tracks.length, (index) => index);
      _index = initialIndex;
    }
    _order = _orderIndices.map((index) => _queue[index]).toList();
    _retried = false;
    _resumePosition = Duration.zero;
    _remoteClaimRequested = true;
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue();
    unawaited(_playCurrent());
  }

  void addNext(Track track) {
    if (_order.isEmpty) {
      playTracks([track], 0);
      return;
    }
    if (_forwardRemoteCommand(
      'queueAdd',
      payload: {'trackId': track.id, 'placement': 'next'},
    )) {
      return;
    }
    _queue.add(track);
    final addedIndex = _queue.length - 1;
    _orderIndices.insert(_index + 1, addedIndex);
    _order.insert(_index + 1, track);
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue();
    _emit();
  }

  void addLast(Track track) {
    if (_order.isEmpty) {
      playTracks([track], 0);
      return;
    }
    if (_forwardRemoteCommand(
      'queueAdd',
      payload: {'trackId': track.id, 'placement': 'last'},
    )) {
      return;
    }
    _queue.add(track);
    _orderIndices.add(_queue.length - 1);
    _order.add(track);
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue();
    _emit();
  }

  void playQueueItem(int queueIndex) {
    if (_forwardRemoteCommand('queuePlay', payload: {'index': queueIndex})) {
      return;
    }
    if (queueIndex < 0 || queueIndex >= _order.length) return;
    _index = queueIndex;
    _retried = false;
    _resumePosition = Duration.zero;
    _persistQueue(position: Duration.zero);
    unawaited(_playCurrent());
  }

  void removeAt(int queueIndex) {
    if (_forwardRemoteCommand('queueRemove', payload: {'index': queueIndex})) {
      return;
    }
    if (queueIndex < 0 || queueIndex >= _order.length) return;
    final sourceIndex = _orderIndices.removeAt(queueIndex);
    _queue.removeAt(sourceIndex);
    for (var index = 0; index < _orderIndices.length; index += 1) {
      if (_orderIndices[index] > sourceIndex) _orderIndices[index] -= 1;
    }
    _order = _orderIndices.map((index) => _queue[index]).toList();
    if (queueIndex < _index) {
      _index -= 1;
    } else if (queueIndex == _index && _order.isEmpty) {
      _index = 0;
      _retried = false;
      _player.stop();
      mediaItem.add(null);
      _emit(_current.copyWith(clearTrack: true));
      queue.add(const []);
      _persistQueue();
      return;
    } else if (queueIndex == _index) {
      if (_index >= _order.length) _index = _order.length - 1;
      _retried = false;
      _playCurrent();
    }
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue();
    _emit();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (_forwardRemoteCommand(
      'queueReorder',
      payload: {'from': oldIndex, 'to': newIndex},
    )) {
      return;
    }
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex < 0 || newIndex >= _order.length) return;
    final currentQueueIndex = _orderIndices[_index];
    final moved = _order.removeAt(oldIndex);
    _order.insert(newIndex, moved);
    final movedIndex = _orderIndices.removeAt(oldIndex);
    _orderIndices.insert(newIndex, movedIndex);
    _index = _orderIndices.indexOf(currentQueueIndex);
    queue.add(_order.map(_toMediaItem).toList());
    _persistQueue();
    _emit();
  }

  void clearQueue() {
    if (_forwardRemoteCommand('queueClear')) return;
    _markPlaybackEpochReset();
    _playRequestId += 1;
    _switchingSource = false;
    _pendingAutoplay = false;
    _queue.clear();
    _order = [];
    _orderIndices = [];
    _index = 0;
    _retried = false;
    _player.stop();
    _loadedSource = false;
    mediaItem.add(null);
    queue.add(const []);
    _persistQueue();
    _emit(_current.copyWith(clearTrack: true));
    _sendRemoteSnapshotImmediately();
  }

  int indexOfId(String id) => _queue.indexWhere((t) => t.id == id);

  // --- playback -------------------------------------------------------------

  Future<void> _playCurrent({bool autoplay = true}) async {
    if (_order.isEmpty) return;
    final requestId = ++_playRequestId;
    var track = _order[_index];
    _switchingSource = true;
    _pendingAutoplay = autoplay;
    _loadedSource = false;
    mediaItem.add(_toMediaItem(track));
    var refreshedBeforePlayback = false;
    _emit(_current.copyWith(playing: false, buffering: true));
    try {
      // Stop the old source before network work so snapshots cannot pair the
      // new queue index with the previous track's position.
      await _player.stop();
      if (!_isCurrentRequest(requestId)) return;
      _sendRemoteSnapshotImmediately();
      _emit(_current.copyWith(playing: false, buffering: true));

      if (track.localPath == null &&
          _backendOrigin != null &&
          _originForUrl(track.streamUrl) != _backendOrigin) {
        refreshedBeforePlayback = true;
        track = await refreshStreamUrlIfNeeded(track);
        if (!_isCurrentRequest(requestId)) return;
        _order[_index] = track;
        _queue[_orderIndices[_index]] = track;
        mediaItem.add(_toMediaItem(track));
        _persistQueue(position: _resumePosition);
      }
      await _player.setAudioSource(
        track.localPath == null
            ? AudioSource.uri(Uri.parse(track.streamUrl))
            : AudioSource.file(track.localPath!),
        initialPosition: _resumePosition,
      );
      if (!_isCurrentRequest(requestId)) return;
      _loadedSource = true;
      final shouldAutoplay = _pendingAutoplay;
      _pendingAutoplay = false;
      _resumePosition = Duration.zero;
      _persistQueue(position: _player.position);
      _switchingSource = false;
      _emit();
      if (shouldAutoplay) unawaited(_startPlayback(track, requestId));
    } on Object catch (error) {
      if (!_isCurrentRequest(requestId)) return;
      Object failure = error;
      final refresher = this.refresher;
      if (refresher != null && !_retried && !refreshedBeforePlayback) {
        _retried = true;
        try {
          final refreshed = await refresher(track.id);
          if (!_isCurrentRequest(requestId)) return;
          if (refreshed != null) {
            _order[_index] = refreshed;
            _queue[_orderIndices[_index]] = refreshed;
            await _playCurrent(autoplay: _pendingAutoplay);
            return;
          }
        } on Object catch (refreshError) {
          failure = Exception(
            '$error; refreshing the stream URL failed: $refreshError',
          );
        }
      }
      _switchingSource = false;
      _pendingAutoplay = false;
      _reportPlaybackError(track, failure, requestId);
    }
  }

  bool _isCurrentRequest(int requestId) =>
      requestId == _playRequestId &&
      _order.isNotEmpty &&
      _index < _order.length;

  Future<void> _startPlayback(Track track, int requestId) {
    if (!_applyingRemoteCommand && _remoteIdentity != null) {
      _remoteClaimRequested = true;
    }
    unawaited(_playAudio(track, requestId));
    return Future.value();
  }

  Future<void> _playAudio(Track track, int requestId) async {
    try {
      await _player.play();
    } on Object catch (error) {
      if (_isCurrentRequest(requestId)) {
        _reportPlaybackError(track, error, requestId);
      }
    }
  }

  void _reportPlaybackError(Track track, Object error, int requestId) {
    if (!_isCurrentRequest(requestId)) return;
    _emit(
      _current.copyWith(
        playing: false,
        buffering: false,
        error: 'Could not play "${track.title}": $error',
      ),
    );
  }

  void _onPlayerState(PlayerState state) {
    final completed = state.processingState == ProcessingState.completed;
    if (completed) {
      if (_switchingSource) return;
      unawaited(_handleTrackCompleted());
      return;
    }
    _emit();
  }

  Future<void> _handleTrackCompleted() async {
    if (_repeat == AudioServiceRepeatMode.one) {
      _markPlaybackEpochReset();
      await _player.seek(Duration.zero);
      await _player.play();
      _sendRemoteSnapshotImmediately();
      return;
    }
    if (_index < _order.length - 1) {
      _index += 1;
      _retried = false;
      _persistQueue(position: Duration.zero);
      await _playCurrent();
    } else if (_repeat == AudioServiceRepeatMode.all && _order.isNotEmpty) {
      _index = 0;
      _retried = false;
      _persistQueue(position: Duration.zero);
      await _playCurrent();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
      _emit(_current.copyWith(playing: false));
      _sendRemoteSnapshotImmediately();
    }
  }

  // --- audio_service overrides ----------------------------------------------

  @override
  Future<void> play() async {
    if (_forwardRemoteCommand('play')) return;
    if (_order.isEmpty) return;
    if (_switchingSource) {
      _pendingAutoplay = true;
      _emit(_current.copyWith(playing: false, buffering: true));
      return;
    }
    if (!_loadedSource) {
      if (!_player.playing) _markPlaybackEpochReset();
      await _playCurrent();
      return;
    }
    if (!_player.playing) _markPlaybackEpochReset();
    await _startPlayback(_order[_index], _playRequestId);
    _sendRemoteSnapshotImmediately();
  }

  @override
  Future<void> pause() async {
    if (_forwardRemoteCommand('pause')) return;
    _resumeAfterInterruption = false;
    if (_player.playing || _pendingAutoplay) _markPlaybackEpochReset();
    if (_switchingSource) {
      _pendingAutoplay = false;
      _persistQueue(position: _resumePosition);
      _emit(_current.copyWith(playing: false, buffering: true));
      _sendRemoteSnapshotImmediately();
      return;
    }
    await _player.pause();
    _persistQueue(position: _player.position);
    _emit();
    _sendRemoteSnapshotImmediately();
  }

  @override
  Future<void> stop() {
    clearQueue();
    return Future.value();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_forwardRemoteCommand(
      'seek',
      payload: {'positionMs': position.inMilliseconds},
    )) {
      return;
    }
    _markPlaybackEpochReset();
    if (_switchingSource) {
      final duration = _order[_index].duration;
      final target = position < Duration.zero
          ? Duration.zero
          : duration != null && position > duration
          ? duration
          : position;
      _resumePosition = target;
      _persistQueue(position: target);
      _emit(_current.copyWith(playing: false, buffering: true));
      _sendRemoteSnapshotImmediately();
      return;
    }
    await _player.seek(position);
    _persistQueue(position: position);
    _sendRemoteSnapshotImmediately();
  }

  @override
  Future<void> skipToNext() async {
    if (_forwardRemoteCommand('next')) return;
    if (_index < _order.length - 1) {
      _markPlaybackEpochReset();
      _index += 1;
      _retried = false;
      _persistQueue(position: Duration.zero);
      unawaited(_playCurrent());
    } else if (_repeat == AudioServiceRepeatMode.all && _order.isNotEmpty) {
      _markPlaybackEpochReset();
      _index = 0;
      _retried = false;
      _persistQueue(position: Duration.zero);
      unawaited(_playCurrent());
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_forwardRemoteCommand('previous')) return;
    if (_index > 0) {
      _markPlaybackEpochReset();
      _index -= 1;
      _retried = false;
      _persistQueue(position: Duration.zero);
      unawaited(_playCurrent());
    } else {
      _markPlaybackEpochReset();
      await _player.seek(Duration.zero);
      _sendRemoteSnapshotImmediately();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (_forwardRemoteCommand(
      'shuffle',
      payload: {'enabled': shuffleMode == AudioServiceShuffleMode.all},
    )) {
      return;
    }
    _shuffle = shuffleMode == AudioServiceShuffleMode.all;
    if (_order.isNotEmpty) {
      final currentQueueIndex = _orderIndices[_index];
      if (_shuffle) {
        final rest = List.generate(_queue.length, (index) => index)
          ..remove(currentQueueIndex)
          ..shuffle(_random);
        _orderIndices = [currentQueueIndex, ...rest];
        _index = 0;
      } else {
        _orderIndices = List.generate(_queue.length, (index) => index);
        _index = currentQueueIndex;
      }
      _order = _orderIndices.map((index) => _queue[index]).toList();
      queue.add(_order.map(_toMediaItem).toList());
    }
    _persistQueue();
    _emit();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (_forwardRemoteCommand(
      'repeat',
      payload: {
        'mode': repeatMode == AudioServiceRepeatMode.one
            ? 'one'
            : repeatMode == AudioServiceRepeatMode.all
            ? 'all'
            : 'none',
      },
    )) {
      return;
    }
    _repeat = repeatMode;
    await _player.setLoopMode(
      _repeat == AudioServiceRepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    _persistQueue();
    _emit();
  }

  Future<void> setVolume(double volume) {
    final bounded = volume.clamp(0.0, 1.0);
    if (_forwardRemoteCommand('volume', payload: {'volume': bounded})) {
      return Future.value();
    }
    return _player.setVolume(bounded);
  }

  Future<void> adjustVolume(double change) =>
      setVolume(_player.volume + change);

  void togglePlayPause() {
    if (_remoteState.remoteTargeted) {
      _forwardRemoteCommand(
        _remoteState.session?.playing == true ? 'pause' : 'play',
      );
      return;
    }
    if (_player.playing) {
      unawaited(pause());
    } else {
      unawaited(play());
    }
  }

  void clearError() => _emit(_current.copyWith(clearError: true));

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist ?? 'Unknown artist',
    artUri: track.artUrl == null ? null : Uri.parse(track.artUrl!),
    duration: track.duration,
  );

  void dispose() {
    _playRequestId += 1;
    disableRemoteSync();
    _positionSaveTimer?.cancel();
    _persistQueue(position: _player.position);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    _uiController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
    _remoteStateController.close();
  }
}

String? _originForUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.origin;
}

// --- Riverpod plumbing -------------------------------------------------------

final playerUiProvider = StreamProvider<PlayerUiState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return Stream<PlayerUiState>.multi((controller) {
    final subscription = handler.uiStream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.add(handler.currentUiState);
    controller.onCancel = subscription.cancel;
  });
});

final positionProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.positionStream;
});

final playbackDurationProvider = StreamProvider<Duration?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.durationStream;
});

final volumeProvider = StreamProvider<double>((ref) async* {
  final handler = ref.watch(audioHandlerProvider);
  yield handler.player.volume;
  yield* handler.volumeStream;
});
