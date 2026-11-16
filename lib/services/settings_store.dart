import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../models/user.dart';
import 'drive_bridge_client.dart';

/// Injected in main(); every other provider reads it.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);
final apiHttpClientFactoryProvider = Provider<http.Client Function()>(
  (ref) =>
      () => http.Client(),
);

const _keyBridgeUrl = 'bridge_url';
const _keySessionToken = 'session_token';
const _keyUserJson = 'user_json';
const _keyThemeMode = 'theme_mode';
const _keyFavorites = 'favorites';
const _keyPendingFavoriteSync = 'pending_favorite_sync';

String _favoritesKey(String? userId) =>
    userId == null ? _keyFavorites : 'favorites_user_$userId';

String _pendingFavoriteSyncKey(String? userId) => userId == null
    ? _keyPendingFavoriteSync
    : 'pending_favorite_sync_user_$userId';

/// Default bridge; can be overridden at build/run time:
///   flutter run --dart-define=GMUSIC_BRIDGE_URL=http://127.0.0.1:43821
///   flutter run --dart-define=GMUSIC_SESSION_TOKEN=session_token_from_login
const String kDefaultBridgeUrl = String.fromEnvironment(
  'GMUSIC_BRIDGE_URL',
  defaultValue: 'https://gmusicbackend.vercel.app/',
);
const String kDefaultSessionToken = String.fromEnvironment(
  'GMUSIC_SESSION_TOKEN',
  defaultValue: '',
);

class SettingsState {
  const SettingsState({
    this.bridgeUrl = kDefaultBridgeUrl,
    this.sessionToken = '',
    this.user,
    this.themeMode = ThemeMode.dark,
  });

  final String bridgeUrl;
  final String sessionToken;
  final AuthUser? user;
  final ThemeMode themeMode;

  /// The app needs a reachable bridge and a live session token.
  bool get configured =>
      bridgeUrl.trim().isNotEmpty && sessionToken.trim().isNotEmpty;

  SettingsState copyWith({
    String? bridgeUrl,
    String? sessionToken,
    AuthUser? user,
    bool clearSession = false,
    ThemeMode? themeMode,
  }) => SettingsState(
    bridgeUrl: bridgeUrl ?? this.bridgeUrl,
    sessionToken: clearSession ? '' : (sessionToken ?? this.sessionToken),
    user: clearSession ? null : (user ?? this.user),
    themeMode: themeMode ?? this.themeMode,
  );
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this._prefs, this._httpClientFactory)
    : super(const SettingsState()) {
    state = SettingsState(
      bridgeUrl: _prefs.getString(_keyBridgeUrl) ?? kDefaultBridgeUrl,
      sessionToken: _prefs.getString(_keySessionToken) ?? kDefaultSessionToken,
      user: _decodeUser(_prefs.getString(_keyUserJson)),
      themeMode: _decodeThemeMode(_prefs.getString(_keyThemeMode)),
    );
  }

  final SharedPreferences _prefs;
  final http.Client Function() _httpClientFactory;
  DriveBridgeClient? _cachedClient;
  String? _cachedClientIdentity;

  Future<void> saveBridgeUrl(String bridgeUrl) async {
    final url = bridgeUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    state = state.copyWith(bridgeUrl: url);
    await _prefs.setString(_keyBridgeUrl, url);
  }

  /// Persists the session so the app re-authenticates on next start.
  Future<void> setSession(AuthSession session) async {
    state = state.copyWith(sessionToken: session.token, user: session.user);
    await _prefs.setString(_keySessionToken, session.token);
    await _prefs.setString(_keyUserJson, jsonEncode(session.user.toJson()));
  }

  Future<void> updateUser(AuthUser user) async {
    state = state.copyWith(user: user);
    await _prefs.setString(_keyUserJson, jsonEncode(user.toJson()));
  }

  Future<void> clearSession() async {
    state = state.copyWith(clearSession: true);
    await _prefs.remove(_keySessionToken);
    await _prefs.remove(_keyUserJson);
    _discardCachedClient();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_keyThemeMode, mode.name);
  }

  /// Bridge client carrying the current session token.
  DriveBridgeClient client() {
    final identity = '${state.bridgeUrl}\u0000${state.sessionToken}';
    if (_cachedClientIdentity != identity) {
      _discardCachedClient();
      _cachedClient = DriveBridgeClient(
        baseUrl: state.bridgeUrl,
        token: state.sessionToken,
        client: _httpClientFactory(),
      );
      _cachedClientIdentity = identity;
    }
    return _cachedClient!;
  }

  @override
  void dispose() {
    _discardCachedClient();
    super.dispose();
  }

  void _discardCachedClient() {
    _cachedClient?.dispose();
    _cachedClient = null;
    _cachedClientIdentity = null;
  }

  static AuthUser? _decodeUser(String? json) {
    if (json == null || json.isEmpty) return null;
    return AuthUser.fromJson(
      Map<String, dynamic>.from(jsonDecode(json) as Map),
    );
  }

  static ThemeMode _decodeThemeMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
}

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>(
      (ref) => SettingsController(
        ref.watch(sharedPreferencesProvider),
        ref.watch(apiHttpClientFactoryProvider),
      ),
    );

/// Favorite ids are scoped to the signed-in account; pending server mutations
/// are persisted separately so offline changes can be retried.
class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController(this._prefs, String? userId)
    : _storageKey = _favoritesKey(userId),
      _pendingStorageKey = _pendingFavoriteSyncKey(userId),
      super(_prefs.getStringList(_favoritesKey(userId))?.toSet() ?? const {});

  final SharedPreferences _prefs;
  final String _storageKey;
  final String _pendingStorageKey;

  bool contains(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final next = Set<String>.from(state);
    if (!next.remove(id)) next.add(id);
    state = next;
    await _prefs.setStringList(_storageKey, next.toList());
  }

  /// Replaces the account cache after pending mutations have been synchronized.
  Future<void> mergeRemote(List<FavoriteEntry> remote) async {
    final next = remote.map((entry) => entry.trackId).toSet();
    state = next;
    await _prefs.setStringList(_storageKey, next.toList());
  }

  List<FavoriteSyncOperation> get pendingOperations {
    final encoded = _prefs.getStringList(_pendingStorageKey) ?? const [];
    return encoded
        .map(
          (value) => FavoriteSyncOperation.fromJson(
            Map<String, dynamic>.from(jsonDecode(value) as Map),
          ),
        )
        .toList();
  }

  Future<FavoriteSyncOperation> queueOperation({
    required Track track,
    required bool added,
  }) async {
    final operation = FavoriteSyncOperation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      trackId: track.id,
      added: added,
      title: track.title,
      artist: track.artist,
    );
    final operations = pendingOperations
      ..removeWhere((pending) => pending.trackId == track.id)
      ..add(operation);
    await _savePending(operations);
    return operation;
  }

  Future<void> removePendingOperation(FavoriteSyncOperation operation) async {
    final operations = pendingOperations
      ..removeWhere((pending) => pending.id == operation.id);
    await _savePending(operations);
  }

  Future<bool> syncPending(
    Future<void> Function(FavoriteSyncOperation) synchronize,
  ) async {
    for (final operation in pendingOperations) {
      try {
        await synchronize(operation);
        await removePendingOperation(operation);
      } on Exception {
        return false;
      }
    }
    return true;
  }

  Future<void> _savePending(List<FavoriteSyncOperation> operations) async {
    await _prefs.setStringList(
      _pendingStorageKey,
      operations.map((operation) => jsonEncode(operation.toJson())).toList(),
    );
  }
}

class FavoriteSyncOperation {
  const FavoriteSyncOperation({
    required this.id,
    required this.trackId,
    required this.added,
    required this.title,
    required this.artist,
  });

  final String id;
  final String trackId;
  final bool added;
  final String title;
  final String? artist;

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackId': trackId,
    'added': added,
    'title': title,
    'artist': artist,
  };

  factory FavoriteSyncOperation.fromJson(Map<String, dynamic> json) =>
      FavoriteSyncOperation(
        id: json['id'] as String,
        trackId: json['trackId'] as String,
        added: json['added'] as bool,
        title: json['title'] as String,
        artist: json['artist'] as String?,
      );
}

final favoritesControllerProvider =
    StateNotifierProvider<FavoritesController, Set<String>>((ref) {
      final userId = ref.watch(
        settingsControllerProvider.select((settings) => settings.user?.id),
      );
      return FavoritesController(ref.watch(sharedPreferencesProvider), userId);
    });

/// Persist a mutation before sending it so a failed/offline request can be
/// retried on the next successful session restore.
Future<bool> syncFavoriteRemote({
  required FavoritesController favorites,
  required SettingsController settings,
  required bool added,
  required Track track,
}) async {
  final operation = await favorites.queueOperation(track: track, added: added);
  try {
    final client = settings.client();
    if (added) {
      await client.addFavorite(track);
    } else {
      await client.removeFavorite(track);
    }
    await favorites.removePendingOperation(operation);
    return true;
  } on Exception {
    return false;
  }
}
