/// A logged-in GMusic user (stored in the Atlas `Users` collection).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.username,
    this.displayName,
    this.role = 'user',
  });

  final String id;
  final String email;
  final String? username;
  final String? displayName;
  final String role;

  String get label => displayName?.trim().isNotEmpty == true ? displayName!.trim() : email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String?,
        displayName: json['displayName'] as String?,
        role: json['role'] as String? ?? 'user',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'displayName': displayName,
        'role': role,
      };
}

/// Session returned by login/register; the token persists on the device and
/// re-authenticates until it expires (30 days, sliding) or the user logs out.
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String? ?? '',
        user: AuthUser.fromJson(Map<String, dynamic>.from(json['user'] as Map? ?? const {})),
      );
}

/// Per-user favorites and recent plays (Atlas collections `favorites` /
/// `recent_plays`), mirrored on device so both views work offline.
class FavoriteEntry {
  const FavoriteEntry({required this.trackId, this.title, this.artist, this.addedAt});

  final String trackId;
  final String? title;
  final String? artist;
  final DateTime? addedAt;

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) => FavoriteEntry(
        trackId: json['trackId'] as String? ?? '',
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? '')?.toLocal(),
      );
}

class RecentEntry {
  const RecentEntry({required this.trackId, this.title, this.artist, this.playedAt});

  final String trackId;
  final String? title;
  final String? artist;
  final DateTime? playedAt;

  factory RecentEntry.fromJson(Map<String, dynamic> json) => RecentEntry(
        trackId: json['trackId'] as String? ?? '',
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? '')?.toLocal(),
      );
}
