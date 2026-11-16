import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../services/download_storage.dart';
import '../services/settings_store.dart';

String _storageKey(String? userId) => 'downloaded_tracks_${userId ?? 'local'}';

class DownloadEntry {
  const DownloadEntry({
    required this.track,
    required this.path,
    required this.size,
    required this.downloadedAt,
  });
  final Track track;
  final String path;
  final int size;
  final DateTime downloadedAt;

  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'path': path,
    'size': size,
    'downloadedAt': downloadedAt.toIso8601String(),
  };
  factory DownloadEntry.fromJson(Map<String, dynamic> json) {
    final track = Track.fromJson(
      Map<String, dynamic>.from(json['track'] as Map),
    );
    final path = json['path'] as String;
    return DownloadEntry(
      track: track.copyWith(localPath: path),
      path: path,
      size: int.tryParse(json['size']?.toString() ?? '') ?? 0,
      downloadedAt:
          DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DownloadState {
  const DownloadState({
    this.items = const {},
    this.progress = const {},
    this.errors = const {},
    this.failedTracks = const {},
    this.pausedTracks = const {},
  });
  final Map<String, DownloadEntry> items;
  final Map<String, double> progress;
  final Map<String, String> errors;
  final Map<String, Track> failedTracks;
  final Map<String, Track> pausedTracks;

  DownloadState copyWith({
    Map<String, DownloadEntry>? items,
    Map<String, double>? progress,
    Map<String, String>? errors,
    Map<String, Track>? failedTracks,
    Map<String, Track>? pausedTracks,
  }) => DownloadState(
    items: items ?? this.items,
    progress: progress ?? this.progress,
    errors: errors ?? this.errors,
    failedTracks: failedTracks ?? this.failedTracks,
    pausedTracks: pausedTracks ?? this.pausedTracks,
  );
}

class DownloadController extends StateNotifier<DownloadState> {
  DownloadController(
    this._preferences,
    this.userId, {
    http.Client Function()? clientFactory,
  }) : _key = _storageKey(userId),
       _pendingKey = '${_storageKey(userId)}_pending',
       _clientFactory = clientFactory ?? http.Client.new,
       super(
         _read(
           _preferences,
           _storageKey(userId),
           '${_storageKey(userId)}_pending',
         ),
       );

  final SharedPreferences _preferences;
  final String? userId;
  final String _key;
  final String _pendingKey;
  final http.Client Function() _clientFactory;
  final Map<String, http.Client> _clients = {};
  final Map<String, DownloadFile> _files = {};
  final Map<String, Track> _activeTracks = {};
  final Set<String> _cancelled = {};
  final Set<String> _pauseRequested = {};
  final Set<String> _retainPartial = {};

  static DownloadState _read(
    SharedPreferences preferences,
    String key,
    String pendingKey,
  ) {
    try {
      final values = preferences.getStringList(key) ?? const [];
      final items = <String, DownloadEntry>{};
      for (final value in values) {
        final entry = DownloadEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(value) as Map),
        );
        items[entry.track.id] = entry;
      }
      final pending = <String, Track>{};
      for (final value in preferences.getStringList(pendingKey) ?? const []) {
        final track = Track.fromJson(
          Map<String, dynamic>.from(jsonDecode(value) as Map),
        );
        pending[track.id] = track;
      }
      return DownloadState(items: items, pausedTracks: pending);
    } on Object {
      return const DownloadState();
    }
  }

  bool get supported => downloadsSupported;
  bool isDownloaded(String id) => state.items.containsKey(id);
  Track? activeTrack(String id) => _activeTracks[id];
  void clearError(String id) => _clearError(id);

  Future<void> verifyFiles() async {
    final retained = <String, DownloadEntry>{};
    for (final entry in state.items.entries) {
      if (await downloadFileExists(entry.value.path)) {
        retained[entry.key] = entry.value;
      }
    }
    if (retained.length != state.items.length) {
      state = state.copyWith(items: retained);
      await _persist();
    }
  }

  Future<void> download(Track track) async {
    if (!supported) {
      _setError(
        track.id,
        'Offline downloads are not supported on this platform.',
        track,
      );
      return;
    }
    if (state.items.containsKey(track.id) || _clients.containsKey(track.id)) {
      return;
    }
    if (track.streamUrl.isEmpty) {
      _setError(
        track.id,
        'This track has no active stream URL. Refresh the library and retry.',
        track,
      );
      return;
    }
    _cancelled.remove(track.id);
    _pauseRequested.remove(track.id);
    state = state.copyWith(
      pausedTracks: {...state.pausedTracks}..remove(track.id),
    );
    _activeTracks[track.id] = track;
    await _persistPending(track);
    final client = _clientFactory();
    _clients[track.id] = client;
    _clearError(track.id);
    DownloadFile? file;
    try {
      final offset = await partialDownloadLength(
        userId ?? 'local',
        track.id,
        track.name,
      );
      final request = http.Request('GET', Uri.parse(track.streamUrl));
      if (offset > 0) request.headers['range'] = 'bytes=$offset-';
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Download returned HTTP ${response.statusCode}',
          Uri.parse(track.streamUrl),
        );
      }
      final append = offset > 0 && response.statusCode == 206;
      final actualOffset = append ? offset : 0;
      file = await createDownloadFile(
        userId ?? 'local',
        track.id,
        track.name,
        appendToPartial: append,
      );
      _files[track.id] = file;
      final total = (response.contentLength ?? 0) + actualOffset;
      var received = actualOffset;
      state = state.copyWith(
        progress: {
          ...state.progress,
          track.id: total > 0 ? (received / total).clamp(0, 1) : 0,
        },
      );
      await for (final chunk in response.stream) {
        if (_cancelled.contains(track.id)) throw const _DownloadCancelled();
        if (_pauseRequested.contains(track.id)) throw const _DownloadPaused();
        await file.write(chunk);
        received += chunk.length;
        if (total > 0) {
          state = state.copyWith(
            progress: {
              ...state.progress,
              track.id: (received / total).clamp(0, 1),
            },
          );
        }
      }
      if (_cancelled.contains(track.id)) throw const _DownloadCancelled();
      if (_pauseRequested.contains(track.id)) throw const _DownloadPaused();
      final path = await file.complete();
      final downloaded = DownloadEntry(
        track: track.copyWith(localPath: path),
        path: path,
        size: received,
        downloadedAt: DateTime.now(),
      );
      state = state.copyWith(
        items: {...state.items, track.id: downloaded},
        progress: {...state.progress}..remove(track.id),
        errors: {...state.errors}..remove(track.id),
        failedTracks: {...state.failedTracks}..remove(track.id),
        pausedTracks: {...state.pausedTracks}..remove(track.id),
      );
      await _persist();
      await _persistPending();
    } on _DownloadPaused {
      state = state.copyWith(
        progress: {...state.progress}..remove(track.id),
        pausedTracks: {...state.pausedTracks, track.id: track},
      );
      await _persistPending(track);
    } on _DownloadCancelled {
      state = state.copyWith(
        progress: {...state.progress}..remove(track.id),
        pausedTracks: {...state.pausedTracks}..remove(track.id),
      );
      await _persistPending();
    } on Object catch (error) {
      if (_pauseRequested.contains(track.id)) {
        state = state.copyWith(
          progress: {...state.progress}..remove(track.id),
          pausedTracks: {...state.pausedTracks, track.id: track},
        );
        await _persistPending(track);
      } else if (!_cancelled.contains(track.id)) {
        _retainPartial.add(track.id);
        _setError(track.id, 'Download failed: $error', track);
        await _persistPending();
      }
      state = state.copyWith(progress: {...state.progress}..remove(track.id));
    } finally {
      final activeFile = _files.remove(track.id);
      if (activeFile != null) {
        if (_pauseRequested.contains(track.id) ||
            _retainPartial.contains(track.id)) {
          await activeFile.pause();
        } else {
          await activeFile.cancel();
        }
      }
      _clients.remove(track.id)?.close();
      _activeTracks.remove(track.id);
      _cancelled.remove(track.id);
      _pauseRequested.remove(track.id);
      _retainPartial.remove(track.id);
    }
  }

  Future<void> downloadAll(Iterable<Track> tracks) async {
    for (final track in tracks) {
      if (!isDownloaded(track.id)) await download(track);
    }
  }

  Future<void> pause(String id) async {
    final track = _activeTracks[id];
    if (track == null) return;
    _pauseRequested.add(id);
    _clients[id]?.close();
    await _persistPending(track);
  }

  Future<void> cancel(String id) async {
    final track = _activeTracks[id] ?? state.pausedTracks[id];
    _cancelled.add(id);
    _pauseRequested.remove(id);
    _retainPartial.remove(id);
    _clients[id]?.close();
    await _files.remove(id)?.cancel();
    if (track != null) {
      await deletePartialDownload(userId ?? 'local', id, track.name);
    }
    state = state.copyWith(
      progress: {...state.progress}..remove(id),
      pausedTracks: {...state.pausedTracks}..remove(id),
    );
    await _persistPending();
  }

  Future<void> remove(String id) async {
    await cancel(id);
    final entry = state.items[id];
    if (entry != null) await deleteDownloadFile(entry.path);
    state = state.copyWith(
      items: {...state.items}..remove(id),
      errors: {...state.errors}..remove(id),
      failedTracks: {...state.failedTracks}..remove(id),
      pausedTracks: {...state.pausedTracks}..remove(id),
    );
    await _persist();
  }

  void _setError(String id, String error, [Track? track]) =>
      state = state.copyWith(
        errors: {...state.errors, id: error},
        failedTracks: {...state.failedTracks, id: ?track},
      );
  void _clearError(String id) => state = state.copyWith(
    errors: {...state.errors}..remove(id),
    failedTracks: {...state.failedTracks}..remove(id),
  );

  Future<void> _persistPending([Track? extra]) async {
    final pending = {...state.pausedTracks};
    if (extra != null) pending[extra.id] = extra;
    await _preferences.setStringList(
      _pendingKey,
      pending.values.map((track) => jsonEncode(track.toJson())).toList(),
    );
  }

  Future<void> _persist() async {
    await _preferences.setStringList(
      _key,
      state.items.values.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  @override
  void dispose() {
    for (final client in _clients.values) {
      client.close();
    }
    for (final file in _files.values) {
      unawaited(file.pause());
    }
    _activeTracks.clear();
    super.dispose();
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}

class _DownloadPaused implements Exception {
  const _DownloadPaused();
}

final downloadsProvider =
    StateNotifierProvider<DownloadController, DownloadState>((ref) {
      final preferences = ref.watch(sharedPreferencesProvider);
      final userId = ref.watch(
        settingsControllerProvider.select((value) => value.user?.id),
      );
      final controller = DownloadController(preferences, userId);
      unawaited(controller.verifyFiles());
      return controller;
    });
