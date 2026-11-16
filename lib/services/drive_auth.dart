import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drive_bridge_client.dart';
import 'settings_store.dart';

class DriveAuthState {
  const DriveAuthState({
    this.checking = true,
    this.connected = false,
    this.sharedMode = false,
    this.working = false,
    this.message,
  });

  final bool checking;
  final bool connected;
  final bool sharedMode;
  final bool working;
  final String? message;

  DriveAuthState copyWith({
    bool? checking,
    bool? connected,
    bool? sharedMode,
    bool? working,
    String? message,
    bool clearMessage = false,
  }) => DriveAuthState(
    checking: checking ?? this.checking,
    connected: connected ?? this.connected,
    sharedMode: sharedMode ?? this.sharedMode,
    working: working ?? this.working,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Reads the Google Drive connection status from the configured backend.
class DriveAuthController extends StateNotifier<DriveAuthState> {
  DriveAuthController(this._ref) : super(const DriveAuthState()) {
    checkStatus();
  }

  final Ref _ref;

  Future<void> checkStatus() async {
    final settings = _ref.read(settingsControllerProvider);
    if (!settings.configured) {
      state = state.copyWith(
        checking: false,
        connected: false,
        sharedMode: false,
        message:
            'Configure the bridge and sign in to your GMusic account first.',
      );
      return;
    }
    state = state.copyWith(checking: true, clearMessage: true);
    try {
      final client = _client();
      final status = await client.status();
      final connected = status['authorized'] == true;
      state = state.copyWith(
        checking: false,
        connected: connected,
        sharedMode: status['driveMode'] == 'shared',
        clearMessage: true,
      );
    } on Object catch (error) {
      state = state.copyWith(
        checking: false,
        connected: false,
        message: 'Could not read Drive status from the backend: $error',
      );
    }
  }

  Future<Uri> startOAuth() async {
    state = state.copyWith(working: true, clearMessage: true);
    try {
      final url = await _client().startDriveOAuth();
      state = state.copyWith(working: false);
      return url;
    } on Object catch (error) {
      state = state.copyWith(
        working: false,
        message: 'Could not start Google Drive authorization: $error',
      );
      rethrow;
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(working: true, clearMessage: true);
    try {
      final result = await _client().disconnectDrive();
      state = state.copyWith(
        working: false,
        connected: false,
        message: result['revoked'] == false
            ? 'Drive was disconnected locally, but Google could not confirm token revocation.'
            : null,
        clearMessage: result['revoked'] != false,
      );
    } on Object catch (error) {
      state = state.copyWith(
        working: false,
        message: 'Could not disconnect Google Drive: $error',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sync() async {
    state = state.copyWith(working: true, clearMessage: true);
    try {
      final result = await _client().syncDriveBatch();
      state = state.copyWith(working: false);
      return result;
    } on Object catch (error) {
      state = state.copyWith(
        working: false,
        message: 'Drive sync failed: $error',
      );
      rethrow;
    }
  }

  DriveBridgeClient _client() {
    return _ref.read(settingsControllerProvider.notifier).client();
  }
}

final driveAuthControllerProvider =
    StateNotifierProvider<DriveAuthController, DriveAuthState>(
      DriveAuthController.new,
    );
