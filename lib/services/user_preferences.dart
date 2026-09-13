import 'package:shared_preferences/shared_preferences.dart';

enum MusicLanguage {
  all, hindi, english, spanish, korean, japanese, portuguese, french,
  punjabi, arabic, german, italian, indonesian, turkish, tamil, telugu,
  russian, bengali, thai, filipino, dutch, kannada, marathi
}

class UserPreferences {
  static const _languageKey = 'music_language';
  static const _genresKey = 'music_genres';
  static const _artistsKey = 'music_artists';

  Future<MusicLanguage> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_languageKey);
    if (value == null) return MusicLanguage.all;
    return MusicLanguage.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MusicLanguage.all,
    );
  }

  Future<Set<String>> getGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_genresKey);
    if (value == null) return <String>{};
    return value.split(',').toSet();
  }

  Future<Set<String>> getArtists() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_artistsKey);
    if (value == null) return <String>{};
    return value.split(',').toSet();
  }

  Future<void> setLanguage(MusicLanguage lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, lang.name);
  }

  Future<void> setGenres(Set<String> genres) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_genresKey, genres.join(','));
  }

  Future<void> setArtists(Set<String> artists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_artistsKey, artists.join(','));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_languageKey);
    await prefs.remove(_genresKey);
    await prefs.remove(_artistsKey);
  }
}
