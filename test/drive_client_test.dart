import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gmusic/services/drive_bridge_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'starts Google OAuth only from the trusted Google authorization host',
    () async {
      final client = DriveBridgeClient(
        baseUrl: 'http://127.0.0.1:43821',
        token: 'token-123',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/drive/oauth/start');
          expect(request.headers['Authorization'], isNotEmpty);
          return http.Response(
            jsonEncode({
              'url': 'https://accounts.google.com/o/oauth2/auth?scope=drive.readonly',
            }),
            200,
          );
        }),
      );
      expect(
        await client.startDriveOAuth(),
        Uri.parse(
          'https://accounts.google.com/o/oauth2/auth?scope=drive.readonly',
        ),
      );
    },
  );

  test('rejects a backend OAuth URL outside Google Accounts', () async {
    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821',
      token: 'token-123',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'url': 'https://attacker.example/oauth'}),
          200,
        ),
      ),
    );
    expect(client.startDriveOAuth(), throwsA(isA<FormatException>()));
  });

  test('parses a tracks page into Track objects', () async {
    final payload = {
      'files': [
        {
          'id': 'f1',
          'name': 'Song One - Artist One.flac',
          'mimeType': 'audio/flac',
          'size': '1234',
          'modifiedTime': '2026-11-05T01:51:19.831Z',
          'streamUrl': 'http://127.0.0.1:43821/stream/tk1',
        },
        {
          'id': 'f2',
          'name': 'Song Two.mp3',
          'mimeType': 'audio/mpeg',
          'size': null,
          'streamUrl': 'http://127.0.0.1:43821/stream/tk2',
        },
      ],
      'nextPageToken': null,
    };

    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821/',
      token: 'token-123',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/tracks');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(request.url.queryParameters['pageSize'], '100');
        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final page = await client.tracks(pageSize: 100);
    expect(page.files, hasLength(2));
    expect(page.nextPageToken, isNull);
    final first = page.files.first;
    expect(first.title, 'Song One');
    expect(first.artist, 'Artist One');
    expect(first.size, 1234);
    expect(first.streamUrl, endsWith('/stream/tk1'));
  });

  test('throws on non-2xx from the bridge', () async {
    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821',
      token: 'token-123',
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    expect(
      client.status(),
      throwsA(
        isA<BridgeApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('reads normalized catalog metadata and preserves pagination', () async {
    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821',
      token: 'token-123',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/catalog/tracks');
        expect(request.url.queryParameters['q'], 'blue note');
        expect(request.url.queryParameters['pageToken'], 'next');
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'catalog-1',
                'name': 'unknown-name.flac',
                'title': 'Normalized title',
                'artists': ['Artist One', 'Artist Two'],
                'album': 'Blue Note',
                'albumArtist': 'Artist One',
                'genres': ['Jazz'],
                'year': 1965,
                'trackNumber': 3,
                'discNumber': 1,
                'durationMs': 205000,
                'metadataStatus': 'indexed',
                'streamUrl': 'http://127.0.0.1:43821/stream/ticket',
              },
            ],
            'nextPageToken': 'next-page',
          }),
          200,
        );
      }),
    );

    final page = await client.catalogTracks(
      query: 'blue note',
      pageToken: 'next',
    );
    final track = page.files.single;
    expect(page.nextPageToken, 'next-page');
    expect(track.title, 'Normalized title');
    expect(track.artist, 'Artist One, Artist Two');
    expect(track.album, 'Blue Note');
    expect(track.genres, ['Jazz']);
    expect(track.duration, const Duration(seconds: 205));
  });

  test('search returns matching tracks, artists, and albums', () async {
    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821',
      token: 'search-session',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/search');
        expect(request.url.queryParameters['q'], 'blue note');
        expect(request.headers['authorization'], 'Bearer search-session');
        return http.Response(
          jsonEncode({
            'tracks': [
              {
                'id': 'search-track',
                'name': 'Blue Note.mp3',
                'title': 'Blue Note',
                'artists': ['Artist'],
                'streamUrl': 'http://127.0.0.1:43821/stream/ticket',
              },
            ],
            'artists': [
              {'id': 'search-artist', 'name': 'Artist', 'trackCount': 3},
            ],
            'albums': [
              {
                'id': 'search-album',
                'name': 'Blue Note',
                'artist': 'Artist',
                'trackCount': 8,
              },
            ],
            'nextPageToken': null,
          }),
          200,
        );
      }),
    );

    final result = await client.searchCatalog(' blue note ');

    expect(result['tracks'], hasLength(1));
    expect(result['artists'], hasLength(1));
    expect(result['albums'], hasLength(1));
  });

  test(
    'loads artist entities and genre track pages from the catalog',
    () async {
      final client = DriveBridgeClient(
        baseUrl: 'http://127.0.0.1:43821',
        token: 'token-123',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/artists') {
            return http.Response(
              jsonEncode({
                'artists': [
                  {'id': 'artist-key', 'name': 'Artist', 'trackCount': 4},
                ],
                'nextPageToken': null,
              }),
              200,
            );
          }
          expect(request.url.path, '/api/v1/genres/jazz/tracks');
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'genre-track',
                  'name': 'Song.mp3',
                  'title': 'Song',
                  'artists': ['Artist'],
                  'streamUrl': 'http://127.0.0.1:43821/stream/ticket',
                },
              ],
              'nextPageToken': null,
            }),
            200,
          );
        }),
      );

      final artists = await client.catalogArtists();
      final tracks = await client.genreTracks('jazz');
      expect(artists.items.single.name, 'Artist');
      expect(artists.items.single.trackCount, 4);
      expect(tracks.files.single.title, 'Song');
    },
  );

  test(
    'playlist mutations use the authenticated persistent API contract',
    () async {
      final client = DriveBridgeClient(
        baseUrl: 'http://127.0.0.1:43821',
        token: 'user-session',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer user-session');
          if (request.method == 'GET') {
            expect(request.url.path, '/api/v1/playlists');
            return http.Response(
              jsonEncode({
                'playlists': [
                  {
                    'id': 'p1',
                    'name': 'Road trip',
                    'description': 'Long drives',
                    'trackIds': ['t1'],
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST') {
            expect(request.url.path, '/api/v1/playlists');
            expect(jsonDecode(request.body), {'name': 'Road trip'});
            return http.Response(
              jsonEncode({
                'playlist': {'id': 'p2', 'name': 'Road trip', 'trackIds': []},
              }),
              201,
            );
          }
          if (request.method == 'PUT') {
            expect(request.url.path, '/api/v1/playlists/p1');
            expect(jsonDecode(request.body), {
              'name': 'Road trip',
              'description': 'Long drives',
              'trackIds': ['t2', 't1'],
            });
            return http.Response('{}', 200);
          }
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/playlists/p1');
          return http.Response('{}', 200);
        }),
      );

      final rows = await client.playlists();
      expect(rows.single.description, 'Long drives');
      expect(rows.single.trackIds, ['t1']);
      expect((await client.createPlaylist('Road trip')).id, 'p2');
      await client.updatePlaylist(rows.single.copyWith(trackIds: ['t2', 't1']));
      await client.deletePlaylist('p1');
      client.dispose();
    },
  );

  test('search history and personal saves use per-user API routes', () async {
    final requests = <http.Request>[];
    final client = DriveBridgeClient(
      baseUrl: 'http://127.0.0.1:43821',
      token: 'user-session',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/v1/search-history' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'searches': [
                {'id': 's1', 'query': 'Blue Note'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/followed-artists' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'artists': [
                {'id': 'artist-1', 'name': 'Artist'},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/saved-albums' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'albums': [
                {'id': 'album-1', 'name': 'Album', 'artist': 'Artist'},
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );

    expect((await client.searchHistory()).single.query, 'Blue Note');
    await client.recordSearch('Blue Note');
    await client.removeSearch('Blue Note');
    await client.clearSearchHistory();
    expect((await client.followedArtists()).single.id, 'artist-1');
    await client.followArtist(
      const CatalogEntity(id: 'artist-1', name: 'Artist'),
    );
    await client.unfollowArtist('artist-1');
    expect((await client.savedAlbums()).single.name, 'Album');
    await client.saveAlbum(
      const CatalogEntity(id: 'album-1', name: 'Album', artist: 'Artist'),
    );
    await client.unsaveAlbum('album-1');
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer user-session',
      ),
      isTrue,
    );
    expect(
      requests
          .map((request) => request.url.toString())
          .any((uri) => uri.endsWith('/api/v1/search-history/Blue%20Note')),
      isTrue,
    );
    client.dispose();
  });
}
