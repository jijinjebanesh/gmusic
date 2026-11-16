import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gmusic/models/track.dart';
import 'package:gmusic/models/user.dart';
import 'package:gmusic/services/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults the backend bridge to the deployed server', () {
    expect(kDefaultBridgeUrl, 'https://gmusicbackend.vercel.app/');
  });

  test('favorites are isolated by account', () async {
    final preferences = await SharedPreferences.getInstance();
    final accountA = FavoritesController(preferences, 'account-a');
    final accountB = FavoritesController(preferences, 'account-b');

    await accountA.toggle('track-1');

    expect(accountA.state, contains('track-1'));
    expect(accountB.state, isEmpty);

    accountA.dispose();
    accountB.dispose();
  });

  test('favorite mutations persist until synchronized', () async {
    final preferences = await SharedPreferences.getInstance();
    final favorites = FavoritesController(preferences, 'account-a');
    const track = Track(
      id: 'track-1',
      name: 'song.mp3',
      streamUrl: 'https://example.test/stream',
    );

    final addition = await favorites.queueOperation(track: track, added: true);
    final firstAttempt = await favorites.syncPending((_) async {
      throw Exception('offline');
    });

    expect(firstAttempt, isFalse);
    expect(favorites.pendingOperations.single.id, addition.id);

    final secondAttempt = await favorites.syncPending((operation) async {
      expect(operation.added, isTrue);
    });

    expect(secondAttempt, isTrue);
    expect(favorites.pendingOperations, isEmpty);

    await favorites.mergeRemote([const FavoriteEntry(trackId: 'remote-track')]);
    expect(favorites.state, {'remote-track'});

    favorites.dispose();
  });
}
