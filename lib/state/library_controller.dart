import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';

class LibraryState {
  const LibraryState({
    this.tracks = const [],
    this.query = '',
    this.favoritesOnly = false,
    this.loading = false,
    this.loaded = false,
    this.driveConnected = false,
    this.catalogAvailable = false,
    this.indexStatus = 'not_started',
    this.indexScanned = 0,
    this.indexedCount = 0,
    this.failedCount = 0,
    this.nextPageToken,
    this.error,
  });

  final List<Track> tracks;
  final String query;
  final bool favoritesOnly;
  final bool loading;
  final bool loaded;
  final bool driveConnected;
  final bool catalogAvailable;
  final String indexStatus;
  final int indexScanned;
  final int indexedCount;
  final int failedCount;
  final String? nextPageToken;
  final String? error;

  LibraryState copyWith({
    List<Track>? tracks,
    String? query,
    bool? favoritesOnly,
    bool? loading,
    bool? loaded,
    bool? driveConnected,
    bool? catalogAvailable,
    String? indexStatus,
    int? indexScanned,
    int? indexedCount,
    int? failedCount,
    String? nextPageToken,
    bool clearPageToken = false,
    String? error,
    bool clearError = false,
  }) => LibraryState(
    tracks: tracks ?? this.tracks,
    query: query ?? this.query,
    favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    driveConnected: driveConnected ?? this.driveConnected,
    catalogAvailable: catalogAvailable ?? this.catalogAvailable,
    indexStatus: indexStatus ?? this.indexStatus,
    indexScanned: indexScanned ?? this.indexScanned,
    indexedCount: indexedCount ?? this.indexedCount,
    failedCount: failedCount ?? this.failedCount,
    nextPageToken: clearPageToken
        ? null
        : (nextPageToken ?? this.nextPageToken),
    error: clearError ? null : (error ?? this.error),
  );
}

class LibraryController extends AsyncNotifier<LibraryState> {
  @override
  Future<LibraryState> build() async => const LibraryState();

  DriveBridgeClient get _client {
    return ref.read(settingsControllerProvider.notifier).client();
  }

  Future<TrackPage> _fetchPage({
    String query = '',
    String? pageToken,
    bool? catalogAvailable,
  }) {
    final client = _client;
    final useCatalog =
        catalogAvailable ?? (state.value?.catalogAvailable ?? false);
    return useCatalog
        ? client.catalogTracks(
            query: query,
            pageSize: 100,
            pageToken: pageToken,
          )
        : client.tracks(query: query, pageSize: 100, pageToken: pageToken);
  }

  /// Loads the whole Drive listing and reports whether the backend's linked
  /// Google Drive account is available.
  Future<void> load() async {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.configured) {
      state = const AsyncData(LibraryState(error: 'Bridge not configured.'));
      return;
    }
    state = AsyncData(
      (state.value ?? const LibraryState()).copyWith(
        loading: true,
        clearError: true,
      ),
    );
    try {
      final client = _client;
      final status = await client.status();
      if (status['authorized'] != true) {
        state = const AsyncData(
          LibraryState(loaded: true, driveConnected: false),
        );
        return;
      }
      final driveStatus = await client.driveStatus();
      final index = driveStatus['index'] is Map
          ? Map<String, dynamic>.from(driveStatus['index'] as Map)
          : const <String, dynamic>{};
      final catalogAvailable = driveStatus['catalogAvailable'] == true;
      var indexStatus = index['status'] as String? ?? 'unavailable';
      var indexScanned = _asInt(index['scannedCount']);
      var indexedCount = _asInt(index['indexedCount']);
      var failedCount = _asInt(index['failedCount']);
      if (catalogAvailable && indexStatus == 'not_started') {
        final updated = await client.syncDriveBatch();
        indexStatus = updated['status'] as String? ?? indexStatus;
        indexScanned = _asInt(updated['scannedCount']);
        indexedCount = _asInt(updated['indexedCount']);
        failedCount = _asInt(updated['failedCount']);
      }
      final page = await _fetchPage(
        query: state.value?.query ?? '',
        catalogAvailable: catalogAvailable,
      );
      state = AsyncData(
        (state.value ?? const LibraryState()).copyWith(
          tracks: page.files,
          loading: false,
          loaded: true,
          driveConnected: true,
          catalogAvailable: catalogAvailable,
          indexStatus: indexStatus,
          indexScanned: indexScanned,
          indexedCount: indexedCount,
          failedCount: failedCount,
          nextPageToken: page.nextPageToken,
          clearPageToken: page.nextPageToken == null,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        (state.value ?? const LibraryState()).copyWith(
          loading: false,
          driveConnected: false,
          error: 'Library load failed: $error',
        ),
      );
    }
  }

  Future<void> search(String query) async {
    state = AsyncData(
      (state.value ?? const LibraryState()).copyWith(
        query: query,
        loading: true,
        clearError: true,
      ),
    );
    if (state.value?.driveConnected != true) {
      state = AsyncData(
        (state.value ?? const LibraryState()).copyWith(loading: false),
      );
      return;
    }
    try {
      final page = await _fetchPage(
        query: query,
        catalogAvailable: state.value?.catalogAvailable,
      );
      state = AsyncData(
        (state.value ?? const LibraryState()).copyWith(
          tracks: page.files,
          loading: false,
          nextPageToken: page.nextPageToken,
          clearPageToken: page.nextPageToken == null,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        (state.value ?? const LibraryState()).copyWith(
          loading: false,
          error: 'Search failed: $error',
        ),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        current.loading ||
        current.nextPageToken == null ||
        current.nextPageToken!.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loading: true, clearError: true));
    try {
      final page = await _fetchPage(
        query: current.query,
        pageToken: current.nextPageToken,
      );
      final tracks = [...current.tracks, ...page.files];
      final ids = <String>{};
      final deduplicated = tracks.where((track) => ids.add(track.id)).toList();
      state = AsyncData(
        current.copyWith(
          tracks: deduplicated,
          loading: false,
          nextPageToken: page.nextPageToken,
          clearPageToken: page.nextPageToken == null,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          loading: false,
          error: 'Could not load more tracks: $error',
        ),
      );
    }
  }

  Future<void> syncDrive() async {
    final current = state.value ?? const LibraryState();
    if (!current.driveConnected ||
        !current.catalogAvailable ||
        current.loading) {
      return;
    }
    state = AsyncData(current.copyWith(loading: true, clearError: true));
    try {
      final client = _client;
      final result = await client.syncDriveBatch();
      final page = await client.catalogTracks(
        query: current.query,
        pageSize: 100,
      );
      state = AsyncData(
        current.copyWith(
          tracks: page.files,
          loading: false,
          indexStatus: result['status'] as String? ?? current.indexStatus,
          indexScanned: _asInt(result['scannedCount']),
          indexedCount: _asInt(result['indexedCount']),
          failedCount: _asInt(result['failedCount']),
          nextPageToken: page.nextPageToken,
          clearPageToken: page.nextPageToken == null,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(loading: false, error: 'Drive sync failed: $error'),
      );
    }
  }

  Future<CatalogEntityPage> catalogArtists() => _client.catalogArtists();

  Future<CatalogEntityPage> catalogAlbums() => _client.catalogAlbums();

  Future<List<CatalogEntity>> catalogGenres() => _client.catalogGenres();

  Future<TrackPage> catalogEntityTracks(
    String kind,
    String id, {
    String? pageToken,
  }) {
    final client = _client;
    return switch (kind) {
      'artist' => client.artistTracks(id, pageToken: pageToken),
      'album' => client.albumTracks(id, pageToken: pageToken),
      'genre' => client.genreTracks(id, pageToken: pageToken),
      _ => throw ArgumentError.value(kind, 'kind', 'Unknown catalog entity'),
    };
  }

  void toggleFavoritesOnly() {
    state = AsyncData(
      (state.value ?? const LibraryState()).copyWith(
        favoritesOnly: !(state.value?.favoritesOnly ?? false),
      ),
    );
  }

  /// Fresh copy of a track (new stream ticket) so playback can continue after
  /// the 8-hour ticket expiry.
  Future<Track?> refreshTrack(String id) async {
    if (state.value?.catalogAvailable == true) {
      return _client.catalogTrack(id);
    }
    final page = await _client.tracks(pageSize: 100);
    for (final track in page.files) {
      if (track.id == id) return track;
    }
    return null;
  }
}

int _asInt(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;

final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(
  LibraryController.new,
);

/// Tracks visible in the UI: the library minus favorites filtering (the search
/// query is already applied server-side).
final visibleTracksProvider = Provider<AsyncValue<List<Track>>>((ref) {
  final library = ref.watch(libraryProvider);
  final favorites = ref.watch(favoritesControllerProvider);
  return library.whenData((state) {
    final base = state.favoritesOnly
        ? state.tracks.where((t) => favorites.contains(t.id)).toList()
        : state.tracks;
    return List.unmodifiable(base);
  });
});
