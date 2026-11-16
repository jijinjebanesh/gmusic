import 'track.dart';

class PlaybackMonotonicClock {
  PlaybackMonotonicClock._();

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int? _serverOffsetMicros;

  static Duration get now => _stopwatch.elapsed;

  static void observeServerTime(DateTime serverTime, Duration localTime) {
    final sampleOffset =
        serverTime.toUtc().microsecondsSinceEpoch - localTime.inMicroseconds;
    final previousOffset = _serverOffsetMicros;
    _serverOffsetMicros = previousOffset == null
        ? sampleOffset
        : previousOffset + ((sampleOffset - previousOffset) / 4).round();
  }

  static DateTime? serverTimeAt(Duration localTime) {
    final offset = _serverOffsetMicros;
    if (offset == null) return null;
    return DateTime.fromMicrosecondsSinceEpoch(
      localTime.inMicroseconds + offset,
      isUtc: true,
    );
  }
}

class PlaybackDeviceIdentity {
  const PlaybackDeviceIdentity({
    required this.id,
    required this.name,
    required this.platform,
    this.visible = true,
  });

  final String id;
  final String name;
  final String platform;
  final bool visible;

  PlaybackDeviceIdentity copyWith({String? name, bool? visible}) =>
      PlaybackDeviceIdentity(
        id: id,
        name: name ?? this.name,
        platform: platform,
        visible: visible ?? this.visible,
      );
}

class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.trackIds,
    required this.index,
    required this.positionMs,
    required this.durationMs,
    required this.playing,
    required this.shuffle,
    required this.repeat,
    required this.title,
    required this.artist,
    this.volume = 1,
    this.playbackEpoch,
    this.advancePlaybackEpoch = false,
  });

  final List<String> trackIds;
  final int index;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final bool shuffle;
  final String repeat;
  final String title;
  final String artist;
  final double volume;
  final int? playbackEpoch;
  final bool advancePlaybackEpoch;

  Map<String, dynamic> toJson() => {
    'trackIds': trackIds,
    'index': index,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'playing': playing,
    'shuffle': shuffle,
    'repeat': repeat,
    'title': title,
    'artist': artist,
    'volume': volume,
    if (playbackEpoch != null) 'playbackEpoch': playbackEpoch,
    if (advancePlaybackEpoch) 'advancePlaybackEpoch': true,
  };
}

class PlaybackDevice {
  const PlaybackDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.online,
    this.lastSeenAt,
    this.capabilities = const PlaybackCapabilities(),
    this.visible = true,
    this.type = 'unknown',
    this.isActive = false,
    this.isRestricted = false,
  });

  final String id;
  final String name;
  final String platform;
  final bool online;
  final DateTime? lastSeenAt;
  final PlaybackCapabilities capabilities;
  final bool visible;
  final String type;
  final bool isActive;
  final bool isRestricted;

  factory PlaybackDevice.fromJson(Map<String, dynamic> json) => PlaybackDevice(
    id: json['deviceId'] as String,
    name: json['name'] as String? ?? 'GMusic device',
    platform: json['platform'] as String? ?? 'unknown',
    online: json['online'] == true,
    lastSeenAt: DateTime.tryParse(json['lastSeenAt']?.toString() ?? ''),
    capabilities: PlaybackCapabilities.fromJson(
      Map<String, dynamic>.from(json['capabilities'] as Map? ?? const {}),
    ),
    visible: json['visible'] != false,
    type: json['type'] as String? ?? 'unknown',
    isActive: json['isActive'] == true,
    isRestricted: json['isRestricted'] == true,
  );
}

class PlaybackCapabilities {
  const PlaybackCapabilities({
    this.playback = true,
    this.pause = true,
    this.seek = true,
    this.volume = true,
    this.queue = true,
  });

  final bool playback;
  final bool pause;
  final bool seek;
  final bool volume;
  final bool queue;

  Map<String, bool> toJson() => {
    'playback': playback,
    'pause': pause,
    'seek': seek,
    'volume': volume,
    'queue': queue,
  };

  factory PlaybackCapabilities.fromJson(Map<String, dynamic> json) =>
      PlaybackCapabilities(
        playback: json['playback'] != false,
        pause: json['pause'] != false,
        seek: json['seek'] != false,
        volume: json['volume'] != false,
        queue: json['queue'] != false,
      );
}

class RemotePlaybackSession {
  const RemotePlaybackSession({
    required this.activeDeviceId,
    required this.trackIds,
    required this.index,
    required this.positionMs,
    required this.durationMs,
    required this.playing,
    required this.shuffle,
    required this.repeat,
    required this.title,
    required this.artist,
    required this.queueRevision,
    this.volume = 1,
    this.revision = 0,
    this.stateVersion,
    this.playbackEpoch = 0,
    this.updatedAt,
    this.serverTimestamp,
    this.serverTimeAtReceipt,
    this.monotonicAtReceipt,
  });

  final String? activeDeviceId;
  final List<String> trackIds;
  final int index;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final bool shuffle;
  final String repeat;
  final String title;
  final String artist;
  final int queueRevision;
  final double volume;
  final int revision;
  final int? stateVersion;
  final int playbackEpoch;
  final DateTime? updatedAt;
  final DateTime? serverTimestamp;
  final DateTime? serverTimeAtReceipt;
  final Duration? monotonicAtReceipt;

  int get effectiveStateVersion => stateVersion ?? revision;

  String? get currentTrackId =>
      index >= 0 && index < trackIds.length ? trackIds[index] : null;

  Track? get trackPlaceholder {
    final id = currentTrackId;
    if (id == null) return null;
    final trackTitle = title.trim();
    final trackArtist = artist.trim();
    return Track(
      id: id,
      name: trackTitle.isEmpty ? 'Unknown track' : trackTitle,
      streamUrl: '',
      catalogTitle: trackTitle.isEmpty ? null : trackTitle,
      artists: trackArtist.isEmpty ? const [] : [trackArtist],
    );
  }

  Duration get currentPosition => currentPositionAt(PlaybackMonotonicClock.now);

  bool isNewerThan(RemotePlaybackSession other) =>
      playbackEpoch >= other.playbackEpoch &&
      effectiveStateVersion >= other.effectiveStateVersion &&
      (playbackEpoch > other.playbackEpoch ||
          effectiveStateVersion > other.effectiveStateVersion);

  Duration currentPositionAt(Duration monotonicNow) {
    var elapsed = 0;
    if (playing &&
        updatedAt != null &&
        serverTimeAtReceipt != null &&
        monotonicAtReceipt != null) {
      final serverElapsed = serverTimeAtReceipt!
          .difference(updatedAt!)
          .inMilliseconds;
      final monotonicElapsed =
          (monotonicNow - monotonicAtReceipt!).inMilliseconds;
      elapsed = (serverElapsed + monotonicElapsed).clamp(0, 86_400_000);
    }
    final estimate = positionMs + elapsed;
    final bounded = durationMs > 0 ? estimate.clamp(0, durationMs) : estimate;
    return Duration(milliseconds: bounded.toInt());
  }

  factory RemotePlaybackSession.fromJson(
    Map<String, dynamic> json, {
    DateTime? serverTimeAtReceipt,
    Duration? monotonicAtReceipt,
  }) {
    final serverTimestamp = DateTime.tryParse(
      json['serverTimestamp']?.toString() ?? '',
    );
    return RemotePlaybackSession(
      activeDeviceId: json['activeDeviceId'] as String?,
      trackIds: (json['trackIds'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
      index: int.tryParse(json['index']?.toString() ?? '') ?? 0,
      positionMs: int.tryParse(json['positionMs']?.toString() ?? '') ?? 0,
      durationMs: int.tryParse(json['durationMs']?.toString() ?? '') ?? 0,
      playing: json.containsKey('isPlaying')
          ? json['isPlaying'] == true
          : json['playing'] == true,
      shuffle: json['shuffle'] == true,
      repeat: json['repeat'] as String? ?? 'none',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      queueRevision: int.tryParse(json['queueRevision']?.toString() ?? '') ?? 0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1,
      revision: int.tryParse(json['revision']?.toString() ?? '') ?? 0,
      stateVersion: int.tryParse(
        json['stateVersion']?.toString() ?? json['revision']?.toString() ?? '',
      ),
      playbackEpoch: int.tryParse(json['playbackEpoch']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      serverTimestamp: serverTimestamp,
      serverTimeAtReceipt:
          serverTimeAtReceipt ??
          (monotonicAtReceipt == null
              ? serverTimestamp
              : PlaybackMonotonicClock.serverTimeAt(monotonicAtReceipt) ??
                    serverTimestamp),
      monotonicAtReceipt:
          monotonicAtReceipt ??
          (serverTimestamp == null ? null : PlaybackMonotonicClock.now),
    );
  }
}

class PlaybackTransfer {
  const PlaybackTransfer({required this.id, required this.status, this.error});

  final String? id;
  final String status;
  final String? error;

  factory PlaybackTransfer.fromJson(Map<String, dynamic> json) =>
      PlaybackTransfer(
        id: json['transferId'] as String?,
        status: json['status'] as String? ?? 'pending',
        error: json['error'] as String?,
      );
}

class PlaybackCommandStatus {
  const PlaybackCommandStatus({
    required this.id,
    required this.status,
    this.error,
  });

  final String id;
  final String status;
  final String? error;

  factory PlaybackCommandStatus.fromJson(Map<String, dynamic> json) =>
      PlaybackCommandStatus(
        id: json['commandId'] as String,
        status: json['status'] as String? ?? 'pending',
        error: json['error'] as String?,
      );
}

class PlaybackCommand {
  const PlaybackCommand({
    required this.id,
    required this.action,
    required this.payload,
    this.serverTimeAtReceipt,
    this.monotonicAtReceipt,
  });

  final String id;
  final String action;
  final Map<String, dynamic> payload;
  final DateTime? serverTimeAtReceipt;
  final Duration? monotonicAtReceipt;

  factory PlaybackCommand.fromJson(
    Map<String, dynamic> json, {
    DateTime? serverTimeAtReceipt,
    Duration? monotonicAtReceipt,
  }) => PlaybackCommand(
    id: json['id'] as String,
    action: json['action'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    serverTimeAtReceipt: serverTimeAtReceipt,
    monotonicAtReceipt: monotonicAtReceipt,
  );
}

class PlaybackPollResult {
  const PlaybackPollResult({
    required this.session,
    required this.devices,
    required this.commands,
  });

  final RemotePlaybackSession? session;
  final List<PlaybackDevice> devices;
  final List<PlaybackCommand> commands;

  factory PlaybackPollResult.fromJson(
    Map<String, dynamic> json, {
    Duration? clientRequestStartedAtMonotonic,
    Duration? clientResponseReceivedAtMonotonic,
    DateTime? serverTimeAtReceiptOverride,
  }) {
    final rawSession = json['session'];
    final rawDevices = json['devices'];
    final rawCommands = json['commands'];
    final serverRequestTimestamp = DateTime.tryParse(
      json['serverRequestTimestamp']?.toString() ?? '',
    );
    final serverTimestamp = DateTime.tryParse(
      json['serverTimestamp']?.toString() ?? '',
    );
    final serverTimeAtReceipt =
        serverTimeAtReceiptOverride ??
        _estimateServerTimeAtReceipt(
          serverRequestTimestamp: serverRequestTimestamp,
          serverTimestamp: serverTimestamp,
          clientRequestStartedAtMonotonic: clientRequestStartedAtMonotonic,
          clientResponseReceivedAtMonotonic: clientResponseReceivedAtMonotonic,
        );
    if (serverTimeAtReceipt != null &&
        clientResponseReceivedAtMonotonic != null) {
      PlaybackMonotonicClock.observeServerTime(
        serverTimeAtReceipt,
        clientResponseReceivedAtMonotonic,
      );
    }
    return PlaybackPollResult(
      session: rawSession is Map
          ? RemotePlaybackSession.fromJson(
              Map<String, dynamic>.from(rawSession),
              serverTimeAtReceipt: serverTimeAtReceipt,
              monotonicAtReceipt: clientResponseReceivedAtMonotonic,
            )
          : null,
      devices: rawDevices is List
          ? rawDevices
                .map(
                  (device) => PlaybackDevice.fromJson(
                    Map<String, dynamic>.from(device as Map),
                  ),
                )
                .toList()
          : const [],
      commands: rawCommands is List
          ? rawCommands
                .map(
                  (command) => PlaybackCommand.fromJson(
                    Map<String, dynamic>.from(command as Map),
                    serverTimeAtReceipt: serverTimeAtReceipt,
                    monotonicAtReceipt: clientResponseReceivedAtMonotonic,
                  ),
                )
                .toList()
          : const [],
    );
  }

  static DateTime? _estimateServerTimeAtReceipt({
    required DateTime? serverRequestTimestamp,
    required DateTime? serverTimestamp,
    required Duration? clientRequestStartedAtMonotonic,
    required Duration? clientResponseReceivedAtMonotonic,
  }) {
    if (serverRequestTimestamp == null ||
        serverTimestamp == null ||
        clientRequestStartedAtMonotonic == null ||
        clientResponseReceivedAtMonotonic == null) {
      return null;
    }

    final roundTripMicros =
        (clientResponseReceivedAtMonotonic - clientRequestStartedAtMonotonic)
            .inMicroseconds;
    if (roundTripMicros < 0) return null;
    final serverProcessingMicros = serverTimestamp
        .difference(serverRequestTimestamp)
        .inMicroseconds;
    final networkMicros = (roundTripMicros - serverProcessingMicros).clamp(
      0,
      roundTripMicros,
    );
    return serverTimestamp.add(
      Duration(microseconds: (networkMicros / 2).round()),
    );
  }
}

class RemotePlaybackState {
  const RemotePlaybackState({
    this.deviceId,
    this.devices = const [],
    this.session,
    this.error,
    this.syncing = false,
    this.remoteQueue = const [],
    this.remoteQueueLoading = false,
    this.remoteQueueError,
    this.deviceName,
    this.deviceVisible = true,
    this.transferId,
    this.transferTargetId,
    this.transferInProgress = false,
  });

  final String? deviceId;
  final List<PlaybackDevice> devices;
  final RemotePlaybackSession? session;
  final String? error;
  final bool syncing;
  final List<Track> remoteQueue;
  final bool remoteQueueLoading;
  final String? remoteQueueError;
  final String? deviceName;
  final bool deviceVisible;
  final String? transferId;
  final String? transferTargetId;
  final bool transferInProgress;

  PlaybackDevice? get activeDevice {
    final activeId = session?.activeDeviceId;
    if (activeId == null) return null;
    for (final device in devices) {
      if (device.id == activeId) return device;
    }
    return null;
  }

  bool get remoteActive => remoteTargeted && activeDevice?.online == true;

  bool get remoteTargeted =>
      session?.activeDeviceId != null && session?.activeDeviceId != deviceId;

  bool get canFailoverToThisDevice {
    final activeId = session?.activeDeviceId;
    if (deviceId == null ||
        activeId == null ||
        activeId == deviceId ||
        session!.trackIds.isEmpty) {
      return false;
    }
    PlaybackDevice? active;
    PlaybackDevice? current;
    for (final device in devices) {
      if (device.id == activeId) active = device;
      if (device.id == deviceId) current = device;
    }
    return active != null &&
        !active.online &&
        active.capabilities.playback &&
        current?.online == true;
  }

  Track? get remoteCurrentTrack {
    final currentIndex = session?.index;
    if (!remoteTargeted ||
        currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= remoteQueue.length) {
      return null;
    }
    return remoteQueue[currentIndex];
  }

  RemotePlaybackState copyWith({
    String? deviceId,
    List<PlaybackDevice>? devices,
    RemotePlaybackSession? session,
    bool clearSession = false,
    String? error,
    bool clearError = false,
    bool? syncing,
    List<Track>? remoteQueue,
    bool clearRemoteQueue = false,
    bool? remoteQueueLoading,
    String? remoteQueueError,
    bool clearRemoteQueueError = false,
    String? deviceName,
    bool? deviceVisible,
    String? transferId,
    bool clearTransfer = false,
    String? transferTargetId,
    bool? transferInProgress,
  }) => RemotePlaybackState(
    deviceId: deviceId ?? this.deviceId,
    devices: devices ?? this.devices,
    session: clearSession ? null : (session ?? this.session),
    error: clearError ? null : (error ?? this.error),
    syncing: syncing ?? this.syncing,
    remoteQueue: clearRemoteQueue
        ? const []
        : (remoteQueue ?? this.remoteQueue),
    remoteQueueLoading: clearRemoteQueue
        ? false
        : (remoteQueueLoading ?? this.remoteQueueLoading),
    remoteQueueError: clearRemoteQueue || clearRemoteQueueError
        ? null
        : (remoteQueueError ?? this.remoteQueueError),
    deviceName: deviceName ?? this.deviceName,
    deviceVisible: deviceVisible ?? this.deviceVisible,
    transferId: clearTransfer ? null : (transferId ?? this.transferId),
    transferTargetId: clearTransfer
        ? null
        : (transferTargetId ?? this.transferTargetId),
    transferInProgress: clearTransfer
        ? false
        : (transferInProgress ?? this.transferInProgress),
  );
}
