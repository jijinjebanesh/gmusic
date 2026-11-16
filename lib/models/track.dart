/// A single track in the GMusic library.
///
/// [Track] mirrors a Drive file and its normalized catalog metadata.
class Track {
  const Track({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.mimeType,
    this.size,
    this.modifiedTime,
    this.duration,
    this.catalogTitle,
    this.artists = const [],
    this.album,
    this.albumArtist,
    this.genres = const [],
    this.year,
    this.trackNumber,
    this.discNumber,
    this.metadataStatus,
    this.localPath,
  });

  final String id;
  final String name;
  final String streamUrl;

  /// Bearer headers are impossible in a browser <img>, so artwork is fetched
  /// through the same stream ticket with `/stream/` rewritten to `/art/`.
  String? get artUrl {
    final marker = streamUrl.indexOf('/stream/');
    if (marker < 0) return null;
    return streamUrl.replaceFirst('/stream/', '/art/', marker);
  }

  final String? mimeType;
  final int? size;
  final String? modifiedTime;
  final Duration? duration;
  final String? catalogTitle;
  final List<String> artists;
  final String? album;
  final String? albumArtist;
  final List<String> genres;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String? metadataStatus;
  final String? localPath;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toUpperCase();
  }

  String get title => catalogTitle?.trim().isNotEmpty == true
      ? catalogTitle!.trim()
      : parseTitle(name);
  String? get artist =>
      artists.isNotEmpty ? artists.join(', ') : parseArtist(name);

  /// Drive has no duration for a file until it has been played once, so this
  /// comes back from the audio engine after loading.
  Track copyWith({Duration? duration, String? localPath}) => Track(
    id: id,
    name: name,
    streamUrl: streamUrl,
    mimeType: mimeType,
    size: size,
    modifiedTime: modifiedTime,
    duration: duration ?? this.duration,
    catalogTitle: catalogTitle,
    artists: artists,
    album: album,
    albumArtist: albumArtist,
    genres: genres,
    year: year,
    trackNumber: trackNumber,
    discNumber: discNumber,
    metadataStatus: metadataStatus,
    localPath: localPath ?? this.localPath,
  );

  factory Track.fromJson(Map<String, dynamic> json) {
    final rawArtists = json['artists'];
    final rawGenres = json['genres'];
    final durationMs = int.tryParse(json['durationMs']?.toString() ?? '');
    return Track(
      id: json['id'] as String,
      name: json['name'] as String,
      streamUrl: json['streamUrl'] as String,
      mimeType: json['mimeType'] as String?,
      size: int.tryParse(json['size']?.toString() ?? ''),
      modifiedTime: json['modifiedTime'] as String?,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      catalogTitle: json['title'] as String?,
      artists: rawArtists is List
          ? rawArtists.map((value) => value.toString()).toList()
          : const [],
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
      genres: rawGenres is List
          ? rawGenres.map((value) => value.toString()).toList()
          : const [],
      year: int.tryParse(json['year']?.toString() ?? ''),
      trackNumber: int.tryParse(json['trackNumber']?.toString() ?? ''),
      discNumber: int.tryParse(json['discNumber']?.toString() ?? ''),
      metadataStatus: json['metadataStatus'] as String?,
      localPath: json['localPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'streamUrl': streamUrl,
    'mimeType': mimeType,
    'size': size,
    'modifiedTime': modifiedTime,
    'durationMs': duration?.inMilliseconds,
    'title': catalogTitle,
    'artists': artists,
    'album': album,
    'albumArtist': albumArtist,
    'genres': genres,
    'year': year,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'metadataStatus': metadataStatus,
    'localPath': localPath,
  };

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Splits "Title - Artist1 & Artist2.flac" into its parts. Falls back to the
/// whole stem as the title when the name has no " - " separator.
String parseTitle(String fileName) {
  final stem = stripExtension(fileName);
  final split = splitName(stem);
  return split.$1;
}

String? parseArtist(String fileName) {
  final stem = stripExtension(fileName);
  return splitName(stem).$2;
}

String stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return fileName.trim();
  return fileName.substring(0, dot).trim();
}

(String, String?) splitName(String stem) {
  // The separator is " - " (space, hyphen, space): album-style names like
  // "Aalaporaan Thamizhan - Sathyaprakash & A. R. Rahman".
  final index = stem.indexOf(' - ');
  if (index < 0) {
    // "Song -" or "Song -" style leftovers keep the trailing dashes out of
    // the displayed title.
    final cleaned = stem.replaceAll(RegExp(r'\s*[-–—]\s*$'), '').trim();
    return (cleaned.isEmpty ? stem : cleaned, null);
  }
  final title = stem.substring(0, index).trim();
  final artist = stem.substring(index + 3).trim();
  if (title.isEmpty) return (stem, null);
  return (title, artist.isEmpty ? null : artist);
}
