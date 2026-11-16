import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../models/user.dart';
import '../services/drive_bridge_client.dart';
import '../services/settings_store.dart';

/// Login state: the authenticated user (from the Atlas-backed session) plus
/// the in-flight operation and the last error.
class AuthState {
  const AuthState({this.user, this.working = false, this.error});

  final AuthUser? user;
  final bool working;
  final String? error;

  bool get authenticated => user != null;

  AuthState copyWith({
    AuthUser? user,
    bool? working,
    String? error,
    bool clearError = false,
    bool clearUser = false,
  }) => AuthState(
    user: clearUser ? null : (user ?? this.user),
    working: working ?? this.working,
    error: clearError ? null : (error ?? this.error),
  );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    state = AuthState(user: _ref.read(settingsControllerProvider).user);
  }

  final Ref _ref; // ignore: avoid_dynamic_calls

  SettingsController get _settings =>
      _ref.read(settingsControllerProvider.notifier);

  DriveBridgeClient _client() => _settings.client();

  /// Re-validates the stored session on app start. Only an explicit 401 clears
  /// it; bridge or database outages must not sign the user out.
  Future<void> restoreSession() async {
    if (!_ref.read(settingsControllerProvider).configured) return;
    state = state.copyWith(working: true, clearError: true);
    try {
      final user = await _client().me();
      await _settings.updateUser(user);
      state = state.copyWith(user: user, working: false);
      await _mergeRemoteFavorites();
    } on BridgeApiException catch (error) {
      if (error.statusCode == 401) {
        await logout();
        return;
      }
      state = state.copyWith(
        working: false,
        error:
            'Could not validate the saved session (HTTP ${error.statusCode}).',
      );
    } on Exception {
      state = state.copyWith(
        working: false,
        error:
            'Could not reach the bridge to validate the saved session. '
            'Your session has been kept; retry from Settings.',
      );
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(working: true, clearError: true);
    try {
      final session = await _client().login(
        email: email.trim(),
        password: password,
      );
      await _settings.setSession(session);
      state = state.copyWith(user: session.user, working: false);
      await _mergeRemoteFavorites();
      return true;
    } catch (error) {
      state = state.copyWith(
        working: false,
        error: _message(error, 'Sign-in failed'),
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = state.copyWith(working: true, clearError: true);
    try {
      final session = await _client().register(
        email: email.trim(),
        password: password,
        displayName: displayName,
      );
      await _settings.setSession(session);
      state = state.copyWith(user: session.user, working: false);
      await _mergeRemoteFavorites();
      return true;
    } catch (error) {
      state = state.copyWith(
        working: false,
        error: _message(error, 'Registration failed'),
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _client().logout();
    } on Object {
      // Local sign-out is what matters if the bridge is unreachable.
    }
    await _settings.clearSession();
    state = const AuthState();
  }

  /// Account favorites follow the user across devices: pull them in at login.
  Future<void> _mergeRemoteFavorites() async {
    final controller = _ref.read(favoritesControllerProvider.notifier);
    final client = _client();
    final bool pendingSynced;
    try {
      pendingSynced = await controller.syncPending((operation) {
        final track = Track(
          id: operation.trackId,
          name: operation.title,
          streamUrl: '',
          catalogTitle: operation.title,
          artists: operation.artist == null ? const [] : [operation.artist!],
        );
        return operation.added
            ? client.addFavorite(track)
            : client.removeFavorite(track);
      });
    } on Exception catch (error) {
      state = state.copyWith(
        error: 'Pending favorite changes could not be synchronized: $error',
      );
      return;
    }
    if (!pendingSynced) {
      state = state.copyWith(
        error:
            'Pending favorite changes could not be synchronized. '
            'They remain saved on this device.',
      );
      return;
    }
    try {
      final remote = await client.favorites();
      await controller.mergeRemote(remote);
    } on Exception catch (error) {
      state = state.copyWith(
        error: 'Favorites could not be synchronized: $error',
      );
    }
  }

  static String _message(Object error, String fallback) {
    final text = error.toString();
    if (text.contains('HTTP 401')) {
      return 'Incorrect email or password.';
    }
    if (text.contains('HTTP 409')) {
      return 'That account already exists — sign in instead.';
    }
    if (text.contains('HTTP 400')) {
      return 'Invalid email or password (8+ characters).';
    }
    if (text.contains('ClientException') || text.contains('SocketException')) {
      return 'Cannot reach the bridge — check the URL and that it is running on the PC.';
    }
    return fallback;
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
