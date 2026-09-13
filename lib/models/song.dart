class Song {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration duration;
  final String? videoId;
  /// Uploader channel name (YouTube). Empty when unknown (cache,
  /// playlists). Recommendation filter trusts official channels.
  final String channel;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.duration,
    this.videoId,
    this.channel = '',
  });

  factory Song.fromYouTube(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artist: json['artist'] ?? 'Unknown',
      thumbnailUrl: json['thumbnail'] ?? '',
      duration: Duration(seconds: json['duration'] ?? 0),
      videoId: json['videoId'] ?? json['id'],
      channel: json['channel'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration.inSeconds,
      'videoId': videoId,
      'channel': channel,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artist: json['artist'] ?? 'Unknown',
      thumbnailUrl: json['thumbnailUrl'] ?? '',
      duration: Duration(seconds: json['duration'] ?? 0),
      videoId: json['videoId'],
      channel: json['channel'] ?? '',
    );
  }
}
