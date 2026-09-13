import 'song.dart';

class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? thumbnailUrl;
  final String? coverPath; // local file path for a custom user-chosen image
  final List<Song> songs;
  final DateTime createdAt;
  final String? source; // 'youtube', 'spotify', 'local'
  final bool isDownloaded;
  final Set<String> downloadedSongIds;
  final bool isSystemManaged;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.coverPath,
    this.thumbnailUrl,
    required this.songs,
    required this.createdAt,
    this.source,
    this.isDownloaded = false,
    Set<String>? downloadedSongIds,
    this.isSystemManaged = false,
  }) : downloadedSongIds = downloadedSongIds ?? {};

  factory Playlist.fromYouTube(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['title'] ?? 'Untitled Playlist',
      description: json['description'],
      thumbnailUrl: json['thumbnail'],
      songs: (json['songs'] as List?)
              ?.map((s) => Song.fromYouTube(s))
              .toList() ??
          [],
      createdAt: DateTime.now(),
      source: 'youtube',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'thumbnailUrl': thumbnailUrl,
      'coverPath': coverPath,
      'songs': songs.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'source': source,
      'isDownloaded': isDownloaded,
      'downloadedSongIds': downloadedSongIds.toList(),
      'isSystemManaged': isSystemManaged,
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Untitled',
      description: json['description'],
      thumbnailUrl: json['thumbnailUrl'],
      coverPath: json['coverPath'],
      songs: (json['songs'] as List?)
              ?.map((s) => Song.fromJson(s))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      source: json['source'],
      isDownloaded: json['isDownloaded'] ?? false,
      downloadedSongIds: (json['downloadedSongIds'] as List?)
              ?.map((e) => e as String)
              .toSet(),
      isSystemManaged: json['isSystemManaged'] ?? false,
    );
  }

  Playlist withCover(String? path) => Playlist(
        id: id,
        name: name,
        description: description,
        thumbnailUrl: thumbnailUrl,
        coverPath: path,
        songs: songs,
        createdAt: createdAt,
        source: source,
        isDownloaded: isDownloaded,
        downloadedSongIds: downloadedSongIds,
        isSystemManaged: isSystemManaged,
      );

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    String? thumbnailUrl,
    String? coverPath,
    List<Song>? songs,
    DateTime? createdAt,
    String? source,
    bool? isDownloaded,
    Set<String>? downloadedSongIds,
    bool? isSystemManaged,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      coverPath: coverPath ?? this.coverPath,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadedSongIds: downloadedSongIds ?? this.downloadedSongIds,
      isSystemManaged: isSystemManaged ?? this.isSystemManaged,
    );
  }
}