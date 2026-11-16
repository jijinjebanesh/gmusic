import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import '../models/playback.dart';
import '../models/track.dart';
import '../models/user.dart';

/// Client for the local Google Drive streaming bridge (mornye-gdrive-bridge).
///
/// The bridge is the only process holding the Google OAuth secret; the app
/// authenticates to it with a session token (from user login) and receives
/// per-file stream tickets, so no Google credential ever reaches the device.
class DriveBridgeClient {
  DriveBridgeClient({
    required String baseUrl,
    required this._token,
    http.Client? client,
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final String _token;
  final http.Client _client;
  final Map<String, ({Track track, DateTime expiresAt})> _catalogTrackCache =
      {};

  static const _catalogTrackCacheDuration = Duration(minutes: 5);
  static const _maxCatalogTrackCacheEntries = 500;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path')
          .replace(queryParameters: query?.isNotEmpty == true ? query : null);

  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  Map<String, String> get _jsonHeaders => {
    ..._headers,
    'Content-Type': 'application/json; charset=utf-8',
  };

  static const _publicJsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// Liveness + authorization state of the bridge.
  Future<Map<String, dynamic>> status() async =>
      _object(await _client.get(_uri('/api/v1/status'), headers: _headers));

  Future<Map<String, dynamic>> driveStatus() async => _object(
    await _client.get(_uri('/api/v1/drive/status'), headers: _headers),
  );

  Future<Uri> startDriveOAuth() async {
    final value = _object(
      await _client.post(_uri('/api/v1/drive/oauth/start'), headers: _headers),
    );
    final uri = Uri.tryParse(value['url'] as String? ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'accounts.google.com') {
      throw const FormatException(
        'Backend returned an invalid Google OAuth URL',
      );
    }
    return uri;
  }

  Future<Map<String, dynamic>> disconnectDrive() async => _object(
    await _client.post(
      _uri('/api/v1/drive/oauth/disconnect'),
      headers: _headers,
    ),
  );

  Future<Map<String, dynamic>> syncDriveBatch() async => _object(
    await _client.post(_uri('/api/v1/drive/sync'), headers: _headers),
  );

  // ---- user accounts (MongoDB Atlas `Users` + `sessions`) ------------------

  /// Creates an account and starts a session in one call.
  Future<AuthSession> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final body = _object(
      await _client.post(
        _uri('/api/v1/auth/register'),
        headers: _publicJsonHeaders,
        body: jsonEncode({
          'email': email,
          'password': password,
          'username': displayName ?? email.split('@').first,
        }),
      ),
    );
    return AuthSession.fromJson(body);
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final body = _object(
      await _client.post(
        _uri('/api/v1/auth/login'),
        headers: _publicJsonHeaders,
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    return AuthSession.fromJson(body);
  }

  Future<void> logout() async {
    _object(await _client.post(_uri('/api/v1/auth/logout'), headers: _headers));
  }

  /// Validates the stored session token against the bridge.
  Future<AuthUser> me() async {
    final body = _object(
      await _client.get(_uri('/api/v1/auth/me'), headers: _headers),
    );
    return AuthUser.fromJson(
      Map<String, dynamic>.from(body['user'] as Map? ?? const {}),
    );
  }

  // ---- per-user state ------------------------------------------------------

  Future<List<FavoriteEntry>> favorites() async {
    final body = _object(
      await _client.get(_uri('/api/v1/favorites'), headers: _headers),
    );
    final rows = body['favorites'];
    if (rows is! List) return const [];
    return rows
        .map(
          (row) =>
              FavoriteEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> addFavorite(Track track) async {
    _object(
      await _client.put(
        _uri('/api/v1/favorites/${Uri.encodeComponent(track.id)}'),
        headers: _jsonHeaders,
        body: jsonEncode({'title': track.title, 'artist': track.artist}),
      ),
    );
  }

  Future<void> removeFavorite(Track track) async {
    _object(
      await _client.delete(
        _uri('/api/v1/favorites/${Uri.encodeComponent(track.id)}'),
        headers: _headers,
      ),
    );
  }

  Future<List<RecentEntry>> recent({int limit = 50}) async {
    final body = _object(
      await _client.get(
        _uri('/api/v1/recent', {'limit': '$limit'}),
        headers: _headers,
      ),
    );
    final rows = body['recent'];
    if (rows is! List) return const [];
    return rows
        .map(
          (row) => RecentEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> recordRecent(Track track) async {
    _object(
      await _client.post(
        _uri('/api/v1/recent'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'trackId': track.id,
          'title': track.title,
          'artist': track.artist,
        }),
      ),
    );
  }

  Future<List<UserPlaylist>> playlists() async {
    final body = _object(
      await _client.get(_uri('/api/v1/playlists'), headers: _headers),
    );
    final rows = body['playlists'];
    if (rows is! List) return const [];
    return rows
        .map(
          (row) => UserPlaylist.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<UserPlaylist> createPlaylist(String name) async {
    final body = _object(
      await _client.post(
        _uri('/api/v1/playlists'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': name}),
      ),
    );
    return UserPlaylist.fromJson(
      Map<String, dynamic>.from(body['playlist'] as Map),
    );
  }

  Future<void> updatePlaylist(UserPlaylist playlist) async {
    _object(
      await _client.put(
        _uri('/api/v1/playlists/${Uri.encodeComponent(playlist.id)}'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'name': playlist.name,
          'description': playlist.description,
          'trackIds': playlist.trackIds,
        }),
      ),
    );
  }

  Future<void> deletePlaylist(String id) async {
    _object(
      await _client.delete(
        _uri('/api/v1/playlists/${Uri.encodeComponent(id)}'),
        headers: _headers,
      ),
    );
  }

  Future<List<SearchHistoryEntry>> searchHistory({int limit = 20}) async {
    final body = _object(
      await _client.get(
        _uri('/api/v1/search-history', {'limit': '$limit'}),
        headers: _headers,
      ),
    );
    final rows = body['searches'];
    if (rows is! List) return const [];
    return rows
        .map(
          (row) => SearchHistoryEntry.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<void> recordSearch(String query) async {
    _object(
      await _client.post(
        _uri('/api/v1/search-history'),
        headers: _jsonHeaders,
        body: jsonEncode({'query': query}),
      ),
    );
  }

  Future<void> removeSearch(String query) async {
    _object(
      await _client.delete(
        _uri('/api/v1/search-history/${Uri.encodeComponent(query)}'),
        headers: _headers,
      ),
    );
  }

  Future<void> clearSearchHistory() async {
    _object(
      await _client.delete(_uri('/api/v1/search-history'), headers: _headers),
    );
  }

  Future<List<CatalogEntity>> followedArtists() =>
      _personalEntities('/api/v1/followed-artists', 'artists');
  Future<List<CatalogEntity>> savedAlbums() =>
      _personalEntities('/api/v1/saved-albums', 'albums');

  Future<List<CatalogEntity>> _personalEntities(String path, String key) async {
    final body = _object(await _client.get(_uri(path), headers: _headers));
    final rows = body[key];
    if (rows is! List) return const [];
    return rows
        .map(
          (row) =>
              CatalogEntity.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> followArtist(CatalogEntity artist) async =>
      _savePersonalEntity('/api/v1/followed-artists', artist);
  Future<void> unfollowArtist(String id) async =>
      _deletePersonalEntity('/api/v1/followed-artists', id);
  Future<void> saveAlbum(CatalogEntity album) async =>
      _savePersonalEntity('/api/v1/saved-albums', album);
  Future<void> unsaveAlbum(String id) async =>
      _deletePersonalEntity('/api/v1/saved-albums', id);

  Future<void> _savePersonalEntity(String path, CatalogEntity entity) async {
    _object(
      await _client.put(
        _uri('$path/${Uri.encodeComponent(entity.id)}'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': entity.name, 'artist': entity.artist}),
      ),
    );
  }

  Future<void> _deletePersonalEntity(String path, String id) async {
    _object(
      await _client.delete(
        _uri('$path/${Uri.encodeComponent(id)}'),
        headers: _headers,
      ),
    );
  }

  Future<TrackPage> tracks({
    String query = '',
    int pageSize = 50,
    String? pageToken,
  }) async {
    final value = _object(
      await _client.get(
        _uri('/api/v1/tracks', {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'pageSize': '$pageSize',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        }),
        headers: _headers,
      ),
    );
    final rows = value['files'] ?? value['tracks'] ?? value['data'];
    if (rows is! List) {
      throw const FormatException('Expected a files list in tracks response');
    }
    return _trackPage(value, rows);
  }

  Future<TrackPage> catalogTracks({
    String query = '',
    int pageSize = 50,
    String? pageToken,
  }) async {
    final value = _object(
      await _client.get(
        _uri('/api/v1/catalog/tracks', {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'pageSize': '$pageSize',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        }),
        headers: _headers,
      ),
    );
    final rows = value['files'];
    if (rows is! List) {
      throw const FormatException('Expected a files list in catalog response');
    }
    return _trackPage(value, rows);
  }

  Future<Track?> catalogTrack(String id) async {
    final cached = _cachedCatalogTrack(id);
    if (cached != null) return cached;
    try {
      final value = _object(
        await _client.get(
          _uri('/api/v1/catalog/tracks/${Uri.encodeComponent(id)}'),
          headers: _headers,
        ),
      );
      final track = value['track'];
      if (track is! Map) return null;
      final resolved = Track.fromJson(Map<String, dynamic>.from(track));
      _cacheCatalogTrack(resolved);
      return resolved;
    } on BridgeApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Track>> catalogTracksByIds(List<String> trackIds) async {
    final missingIds = <String>[];
    for (final id in trackIds) {
      if (_cachedCatalogTrack(id) == null && !missingIds.contains(id)) {
        missingIds.add(id);
      }
    }
    if (missingIds.isNotEmpty) {
      final value = _object(
        await _client.post(
          _uri('/api/v1/catalog/tracks/resolve'),
          headers: _jsonHeaders,
          body: jsonEncode({'trackIds': missingIds}),
        ),
      );
      final rows = value['files'];
      if (rows is! List) {
        throw const FormatException(
          'Expected a files list in track resolve response',
        );
      }
      for (final row in rows) {
        _cacheCatalogTrack(
          Track.fromJson(Map<String, dynamic>.from(row as Map)),
        );
      }
    }
    return trackIds.map(_cachedCatalogTrack).whereType<Track>().toList();
  }

  Future<PlaybackPollResult> pollPlayback({
    required PlaybackDeviceIdentity device,
    required PlaybackSnapshot? snapshot,
    required bool claim,
  }) async {
    final requestStartedAt = PlaybackMonotonicClock.now;
    final response = await _client.post(
      _uri('/api/v1/playback/poll'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'deviceId': device.id,
        'name': device.name,
        'platform': device.platform,
        'capabilities': const PlaybackCapabilities().toJson(),
        'visible': device.visible,
        'claim': claim,
        'snapshot': snapshot?.toJson(),
      }),
    );
    final responseReceivedAt = PlaybackMonotonicClock.now;
    final value = _object(response);
    return PlaybackPollResult.fromJson(
      value,
      clientRequestStartedAtMonotonic: requestStartedAt,
      clientResponseReceivedAtMonotonic: responseReceivedAt,
    );
  }

  Future<PlaybackSocketConnection> connectPlaybackSocket({
    required PlaybackDeviceIdentity device,
    required PlaybackSnapshot? snapshot,
    required bool claim,
  }) async {
    final apiUri = Uri.parse(_baseUrl);
    if (!const {'http', 'https'}.contains(apiUri.scheme)) {
      throw const FormatException('Unsupported playback Socket.IO URL');
    }
    final socket = socket_io.io(
      _baseUrl,
      socket_io.OptionBuilder()
          .setPath('/api/v1/playback/socket')
          .setTransports(['websocket'])
          .setAuth({'token': _token})
          .enableForceNewConnection()
          .disableAutoConnect()
          .disableReconnection()
          .setTimeout(8_000)
          .setAckTimeout(8_000)
          .build(),
    );
    final connection = PlaybackSocketConnection(
      socket,
      device: device,
      snapshot: snapshot,
      claim: claim,
    );
    try {
      await connection.connect();
    } on Object {
      await connection.close();
      rethrow;
    }
    return connection;
  }

  Future<RemotePlaybackState> playbackState(String deviceId) async {
    final value = _object(
      await _client.get(_uri('/api/v1/playback/state'), headers: _headers),
    );
    final rows = value['devices'];
    final rawSession = value['session'];
    return RemotePlaybackState(
      deviceId: deviceId,
      devices: rows is List
          ? rows
                .map(
                  (row) => PlaybackDevice.fromJson(
                    Map<String, dynamic>.from(row as Map),
                  ),
                )
                .toList()
          : const [],
      session: rawSession is Map
          ? RemotePlaybackSession.fromJson(
              Map<String, dynamic>.from(rawSession),
            )
          : null,
    );
  }

  Future<PlaybackTransfer> handoffPlayback(String deviceId) async {
    final value = _object(
      await _client.post(
        _uri('/api/v1/playback/handoff'),
        headers: _jsonHeaders,
        body: jsonEncode({'deviceId': deviceId}),
      ),
    );
    return PlaybackTransfer.fromJson(value);
  }

  Future<PlaybackTransfer> playbackTransfer(String transferId) async {
    final value = _object(
      await _client.get(
        _uri('/api/v1/playback/transfers/${Uri.encodeComponent(transferId)}'),
        headers: _headers,
      ),
    );
    return PlaybackTransfer.fromJson(value);
  }

  Future<void> renamePlaybackDevice(String deviceId, String name) async {
    _object(
      await _client.patch(
        _uri('/api/v1/playback/devices/${Uri.encodeComponent(deviceId)}'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': name}),
      ),
    );
  }

  Future<void> setPlaybackDeviceVisibility(
    String deviceId, {
    required bool visible,
  }) async {
    _object(
      await _client.patch(
        _uri('/api/v1/playback/devices/${Uri.encodeComponent(deviceId)}'),
        headers: _jsonHeaders,
        body: jsonEncode({'visible': visible}),
      ),
    );
  }

  Future<void> disconnectPlaybackDevice(String deviceId) async {
    _object(
      await _client.post(
        _uri(
          '/api/v1/playback/devices/${Uri.encodeComponent(deviceId)}/disconnect',
        ),
        headers: _jsonHeaders,
        body: jsonEncode({'deviceId': deviceId}),
      ),
    );
  }

  Future<void> forgetPlaybackDevice(String deviceId) async {
    _object(
      await _client.delete(
        _uri('/api/v1/playback/devices/${Uri.encodeComponent(deviceId)}'),
        headers: _headers,
      ),
    );
  }

  Future<String> sendPlaybackCommand(
    String action, {
    Map<String, dynamic> payload = const {},
    String? idempotencyKey,
    int? expectedRevision,
    int? expectedQueueRevision,
  }) async {
    final value = _object(
      await _client.post(
        _uri('/api/v1/playback/commands'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'action': action,
          'payload': payload,
          'idempotencyKey': ?idempotencyKey,
          'expectedRevision': ?expectedRevision,
          'expectedQueueRevision': ?expectedQueueRevision,
        }),
      ),
    );
    final commandId = value['commandId'];
    if (commandId is! String || commandId.isEmpty) {
      throw const FormatException(
        'Backend returned an invalid playback command ID',
      );
    }
    return commandId;
  }

  Future<PlaybackCommandStatus> playbackCommandStatus(String commandId) async {
    final value = _object(
      await _client.get(
        _uri('/api/v1/playback/commands/${Uri.encodeComponent(commandId)}'),
        headers: _headers,
      ),
    );
    return PlaybackCommandStatus.fromJson(value);
  }

  Future<void> cancelPlaybackCommand(String commandId) async {
    _object(
      await _client.delete(
        _uri('/api/v1/playback/commands/${Uri.encodeComponent(commandId)}'),
        headers: _headers,
      ),
    );
  }

  Future<Map<String, dynamic>> acknowledgePlaybackCommand({
    required String commandId,
    required String deviceId,
    required bool succeeded,
    String? error,
  }) async => _object(
    await _client.post(
      _uri('/api/v1/playback/commands/${Uri.encodeComponent(commandId)}/ack'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'deviceId': deviceId,
        'status': succeeded ? 'ok' : 'failed',
        'error': ?error,
      }),
    ),
  );

  Future<String?> trackLyrics(String id) async {
    try {
      final value = _object(
        await _client.get(
          _uri('/api/v1/catalog/tracks/${Uri.encodeComponent(id)}/lyrics'),
          headers: _headers,
        ),
      );
      final lyrics = value['lyrics'];
      if (lyrics == null) return null;
      if (lyrics is! String) {
        throw const FormatException('Expected lyrics text in track response');
      }
      final trimmed = lyrics.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on BridgeApiException catch (error) {
      if (error.statusCode == 404 && error.code == 'lyrics_not_found') {
        return null;
      }
      rethrow;
    }
  }

  TrackPage _trackPage(Map<String, dynamic> value, List<dynamic> rows) {
    final tracks = rows
        .map((row) => Track.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    for (final track in tracks) {
      _cacheCatalogTrack(track);
    }
    return TrackPage(
      files: tracks,
      nextPageToken: value['nextPageToken'] as String?,
    );
  }

  Track? _cachedCatalogTrack(String id) {
    final cached = _catalogTrackCache.remove(id);
    if (cached == null || !cached.expiresAt.isAfter(DateTime.now())) {
      return null;
    }
    _catalogTrackCache[id] = cached;
    return cached.track;
  }

  void _cacheCatalogTrack(Track track) {
    _catalogTrackCache.remove(track.id);
    _catalogTrackCache[track.id] = (
      track: track,
      expiresAt: DateTime.now().add(_catalogTrackCacheDuration),
    );
    while (_catalogTrackCache.length > _maxCatalogTrackCacheEntries) {
      _catalogTrackCache.remove(_catalogTrackCache.keys.first);
    }
  }

  Future<Map<String, dynamic>> searchCatalog(String query) async => _object(
    await _client.get(
      _uri('/api/v1/search', {'q': query.trim()}),
      headers: _headers,
    ),
  );

  Future<CatalogEntityPage> catalogArtists({
    String query = '',
    int pageSize = 100,
    String? pageToken,
  }) => _catalogEntityPage(
    '/api/v1/artists',
    'artists',
    query: query,
    pageSize: pageSize,
    pageToken: pageToken,
  );

  Future<CatalogEntityPage> catalogAlbums({
    String query = '',
    int pageSize = 100,
    String? pageToken,
  }) => _catalogEntityPage(
    '/api/v1/albums',
    'albums',
    query: query,
    pageSize: pageSize,
    pageToken: pageToken,
  );

  Future<List<CatalogEntity>> catalogGenres() async {
    final value = _object(
      await _client.get(_uri('/api/v1/genres'), headers: _headers),
    );
    final rows = value['genres'];
    if (rows is! List) {
      throw const FormatException('Expected a genres list in catalog response');
    }
    return rows
        .map(
          (row) =>
              CatalogEntity.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<CatalogEntityPage> _catalogEntityPage(
    String path,
    String key, {
    String query = '',
    int pageSize = 100,
    String? pageToken,
  }) async {
    final value = _object(
      await _client.get(
        _uri(path, {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'pageSize': '$pageSize',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        }),
        headers: _headers,
      ),
    );
    final rows = value[key];
    if (rows is! List) {
      throw FormatException('Expected a $key list in catalog response');
    }
    return CatalogEntityPage(
      items: rows
          .map(
            (row) =>
                CatalogEntity.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(),
      nextPageToken: value['nextPageToken'] as String?,
    );
  }

  Future<TrackPage> artistTracks(
    String artistId, {
    int pageSize = 100,
    String? pageToken,
  }) => _catalogEntityTracks(
    '/api/v1/artists/${Uri.encodeComponent(artistId)}/tracks',
    pageSize: pageSize,
    pageToken: pageToken,
  );

  Future<CatalogEntityPage> artistAlbums(String artistId) => _catalogEntityPage(
    '/api/v1/artists/${Uri.encodeComponent(artistId)}/albums',
    'albums',
  );

  Future<TrackPage> albumTracks(
    String albumId, {
    int pageSize = 100,
    String? pageToken,
  }) => _catalogEntityTracks(
    '/api/v1/albums/${Uri.encodeComponent(albumId)}/tracks',
    pageSize: pageSize,
    pageToken: pageToken,
  );

  Future<TrackPage> genreTracks(
    String genreId, {
    int pageSize = 100,
    String? pageToken,
  }) => _catalogEntityTracks(
    '/api/v1/genres/${Uri.encodeComponent(genreId)}/tracks',
    pageSize: pageSize,
    pageToken: pageToken,
  );

  Future<TrackPage> _catalogEntityTracks(
    String path, {
    int pageSize = 100,
    String? pageToken,
  }) async {
    final value = _object(
      await _client.get(
        _uri(path, {
          'pageSize': '$pageSize',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        }),
        headers: _headers,
      ),
    );
    final rows = value['files'];
    if (rows is! List) {
      throw const FormatException('Expected a files list in catalog response');
    }
    return _trackPage(value, rows);
  }

  Map<String, dynamic> _object(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? code;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) code = body['error'] as String?;
      } on FormatException {
        code = null;
      }
      throw BridgeApiException(response.statusCode, code);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object');
    }
    return decoded;
  }

  void dispose() => _client.close();
}

class PlaybackSocketConnection {
  PlaybackSocketConnection(
    this._socket, {
    required this._device,
    required PlaybackSnapshot? snapshot,
    required bool claim,
  }) : _initialSnapshot = snapshot,
       _initialClaim = claim {
    _socket.on('connect', (_) => unawaited(_register()));
    _socket.on('connect_error', _onConnectError);
    _socket.on('disconnect', _onDisconnect);
    _socket.on('session:error', (dynamic value) {
      _messages.add({'type': 'error', 'error': _errorCode(value)});
    });
    _socket.on('playback:changed', (dynamic value) {
      if (value is Map && value['session'] is Map) {
        final receivedAt = PlaybackMonotonicClock.now;
        final state = Map<String, dynamic>.from(value);
        final serverTimestamp = DateTime.tryParse(
          state['serverTimestamp']?.toString() ?? '',
        );
        _messages.add({
          'type': 'state',
          'result': {
            'serverRequestTimestamp': serverTimestamp?.toIso8601String(),
            'serverTimestamp': serverTimestamp?.toIso8601String(),
            'session': state['session'],
            'devices': const [],
            'commands': const [],
          },
          'serverTimeAtReceipt':
              PlaybackMonotonicClock.serverTimeAt(receivedAt)
                  ?.toIso8601String() ??
              serverTimestamp?.toIso8601String(),
          'clientResponseReceivedAtMonotonicMicros': receivedAt.inMicroseconds,
        });
      }
      requestSync();
    });
    _socket.on('playback:command:result', (dynamic value) {
      if (value is Map) {
        final result = PlaybackCommandStatus.fromJson(
          Map<String, dynamic>.from(value),
        );
        final waiter = _commandWaiters.remove(result.id);
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete(result);
        } else {
          _earlyCommandResults[result.id] = result;
          if (_earlyCommandResults.length > 100) {
            _earlyCommandResults.remove(_earlyCommandResults.keys.first);
          }
        }
        _messages.add({
          'type': 'command_result',
          ...Map<String, dynamic>.from(value),
        });
      }
    });
  }

  static final Random _random = Random.secure();

  final socket_io.Socket _socket;
  final PlaybackDeviceIdentity _device;
  final PlaybackSnapshot? _initialSnapshot;
  final bool _initialClaim;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> _ready =
      Completer<Map<String, dynamic>>();
  final Map<String, Completer<PlaybackCommandStatus>> _commandWaiters = {};
  final Map<String, PlaybackCommandStatus> _earlyCommandResults = {};
  bool _registered = false;
  bool _closed = false;

  Stream<Map<String, dynamic>> get stream => _messages.stream;
  bool get isConnected => _socket.connected;
  late final Map<String, dynamic> initialMessage;

  Future<void> connect() async {
    _socket.connect();
    initialMessage = await _ready.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () =>
          throw TimeoutException('Socket.IO device registration timed out.'),
    );
  }

  Future<void> _register() async {
    if (_closed) return;
    final firstConnection = !_registered;
    final requestStartedAt = PlaybackMonotonicClock.now;
    try {
      final response = await _emitAck('device:register', {
        'device': {
          'deviceId': _device.id,
          'name': _device.name,
          'platform': _device.platform,
          'capabilities': const PlaybackCapabilities().toJson(),
          'visible': _device.visible,
        },
        'snapshot': firstConnection ? _initialSnapshot?.toJson() : null,
        'claim': firstConnection && _initialClaim,
      });
      final responseReceivedAt = PlaybackMonotonicClock.now;
      _checkResponse(response);
      _registered = true;
      final message = {
        'type': firstConnection ? 'ready' : 'sync',
        'crossInstance': response['crossInstance'] == true,
        'result': response['result'],
        'clientRequestStartedAtMonotonicMicros':
            requestStartedAt.inMicroseconds,
        'clientResponseReceivedAtMonotonicMicros':
            responseReceivedAt.inMicroseconds,
      };
      if (!_ready.isCompleted) {
        _ready.complete({...message, 'type': 'ready'});
      } else {
        _messages.add(message);
      }
    } on Object catch (error, stackTrace) {
      _messages.add({'type': 'error', 'error': '$error'});
      if (!_ready.isCompleted) _ready.completeError(error, stackTrace);
      _socket.disconnect();
    }
  }

  void _onConnectError(dynamic error) {
    _messages.add({'type': 'error', 'error': _errorCode(error)});
    if (!_ready.isCompleted) {
      _ready.completeError(StateError(_errorCode(error)));
    }
  }

  void _onDisconnect(dynamic reason) {
    if (!_closed) {
      _messages.add({
        'type': 'disconnect',
        'error': reason?.toString() ?? 'socket_disconnected',
      });
    }
  }

  String _errorCode(dynamic value) {
    if (value is Map && value['error'] is String) {
      return value['error'] as String;
    }
    if (value is Map && value['message'] is String) {
      return value['message'] as String;
    }
    return value?.toString() ?? 'socket_error';
  }

  void _checkResponse(Map<String, dynamic> response) {
    if (response['ok'] != true) {
      throw StateError(
        response['error']?.toString() ?? 'socket_request_failed',
      );
    }
  }

  Future<Map<String, dynamic>> _emitAck(
    String event,
    Map<String, dynamic> payload,
  ) async {
    final response = await _socket
        .timeout(8_000)
        .emitWithAckAsync(event, payload);
    if (response is! Map) {
      throw const FormatException('Socket.IO returned an invalid response');
    }
    return Map<String, dynamic>.from(response);
  }

  void _emitSync(String event, Map<String, dynamic> payload) {
    if (!_socket.connected || _closed) return;
    final requestStartedAt = PlaybackMonotonicClock.now;
    unawaited(
      _emitAck(event, payload)
          .then((response) {
            final responseReceivedAt = PlaybackMonotonicClock.now;
            _checkResponse(response);
            _messages.add({
              'type': 'sync',
              'result': response['result'],
              'clientRequestStartedAtMonotonicMicros':
                  requestStartedAt.inMicroseconds,
              'clientResponseReceivedAtMonotonicMicros':
                  responseReceivedAt.inMicroseconds,
            });
          })
          .catchError((Object error) {
            _messages.add({'type': 'error', 'error': '$error'});
          }),
    );
  }

  void sendHeartbeat(PlaybackSnapshot? snapshot, {bool claim = false}) {
    _emitSync('device:heartbeat', {
      'snapshot': snapshot?.toJson(),
      'claim': claim,
    });
  }

  Future<void> sendHeartbeatAndWait(
    PlaybackSnapshot? snapshot, {
    bool claim = false,
  }) async {
    final response = await _emitAck('device:heartbeat', {
      'snapshot': snapshot?.toJson(),
      'claim': claim,
    });
    _checkResponse(response);
  }

  void requestSync() => _emitSync('playback:sync', const {});

  Future<String> sendPlaybackCommand(
    String action, {
    Map<String, dynamic> payload = const {},
    int? expectedRevision,
    int? expectedQueueRevision,
  }) async {
    final commandId = List.generate(
      32,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final response = await _emitAck('playback:command', {
      'action': action,
      'payload': payload,
      'commandId': commandId,
      'expectedRevision': ?expectedRevision,
      'expectedQueueRevision': ?expectedQueueRevision,
    });
    _checkResponse(response);
    final id = response['commandId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Socket.IO returned an invalid command ID');
    }
    return id;
  }

  Future<PlaybackCommandStatus> waitForCommandResult(
    String commandId, {
    Duration timeout = const Duration(seconds: 3),
  }) {
    final earlyResult = _earlyCommandResults.remove(commandId);
    if (earlyResult != null) return Future.value(earlyResult);
    final completer = Completer<PlaybackCommandStatus>();
    _commandWaiters[commandId] = completer;
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _commandWaiters.remove(commandId);
        throw TimeoutException('Socket.IO command acknowledgment timed out.');
      },
    );
  }

  Future<PlaybackTransfer> handoffPlayback(String deviceId) async {
    final response = await _emitAck('playback:transfer', {
      'deviceId': deviceId,
    });
    _checkResponse(response);
    return PlaybackTransfer.fromJson(response);
  }

  Future<Map<String, dynamic>> acknowledgePlaybackCommand({
    required String commandId,
    required bool succeeded,
    String? error,
  }) async {
    final response = await _emitAck('playback:command:ack', {
      'commandId': commandId,
      'status': succeeded ? 'ok' : 'failed',
      if (error != null)
        'error': error.length > 120 ? error.substring(0, 120) : error,
    });
    _checkResponse(response);
    return response;
  }

  Future<void> close() async {
    _closed = true;
    _socket.dispose();
    for (final waiter in _commandWaiters.values) {
      if (!waiter.isCompleted) {
        waiter.completeError(
          StateError(
            'Socket.IO connection closed before command acknowledgment.',
          ),
        );
      }
    }
    _commandWaiters.clear();
    _earlyCommandResults.clear();
    await _messages.close();
  }
}

class TrackPage {
  const TrackPage({required this.files, this.nextPageToken});

  final List<Track> files;
  final String? nextPageToken;
}

class CatalogEntity {
  const CatalogEntity({
    required this.id,
    required this.name,
    this.trackCount = 0,
    this.artist,
    this.artistId,
    this.year,
  });

  final String id;
  final String name;
  final int trackCount;
  final String? artist;
  final String? artistId;
  final int? year;

  factory CatalogEntity.fromJson(Map<String, dynamic> json) => CatalogEntity(
    id: json['id'] as String,
    name: json['name'] as String,
    trackCount: int.tryParse(json['trackCount']?.toString() ?? '') ?? 0,
    artist: json['artist'] as String?,
    artistId: json['artistId'] as String?,
    year: int.tryParse(json['year']?.toString() ?? ''),
  );
}

class CatalogEntityPage {
  const CatalogEntityPage({required this.items, this.nextPageToken});

  final List<CatalogEntity> items;
  final String? nextPageToken;
}

class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.trackIds = const [],
  });
  final String id;
  final String name;
  final String description;
  final List<String> trackIds;

  factory UserPlaylist.fromJson(Map<String, dynamic> json) => UserPlaylist(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Untitled playlist',
    description: json['description'] as String? ?? '',
    trackIds: (json['trackIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(),
  );

  UserPlaylist copyWith({
    String? name,
    String? description,
    List<String>? trackIds,
  }) => UserPlaylist(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    trackIds: trackIds ?? this.trackIds,
  );
}

class SearchHistoryEntry {
  const SearchHistoryEntry({required this.id, required this.query});
  final String id;
  final String query;
  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SearchHistoryEntry(
        id: json['id']?.toString() ?? json['query']?.toString() ?? '',
        query: json['query'] as String? ?? '',
      );
}

class BridgeApiException implements Exception {
  const BridgeApiException(this.statusCode, this.code);

  final int statusCode;
  final String? code;

  @override
  String toString() =>
      'Bridge returned HTTP $statusCode${code == null ? '' : ' ($code)'}';
}
