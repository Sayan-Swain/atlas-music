import 'package:shared_preferences/shared_preferences.dart';

enum MusicLanguage {
  all, hindi, english, spanish, korean, japanese, portuguese, french,
  punjabi, arabic, german, italian, indonesian, turkish, tamil, telugu,
  russian, bengali, thai, filipino, dutch, kannada, marathi
}

/// Persists the onboarding name + music preferences (language, genres, artists).
/// First launch asks once, later launches reuse it. Profile screen can update/clear.
class UserPrefs {
  static const _nameKey = 'user_name';
  static const _avatarKey = 'user_avatar';
  static const _languageKey = 'music_language';
  static const _genresKey = 'music_genres';
  static const _artistsKey = 'music_artists';
  static const _doneKey = 'onboarding_done';

  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_nameKey)?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<String?> getAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarKey);
  }

  Future<void> setAvatar(String? avatar) async {
    final prefs = await SharedPreferences.getInstance();
    if (avatar == null || avatar.isEmpty) {
      await prefs.remove(_avatarKey);
    } else {
      await prefs.setString(_avatarKey, avatar);
    }
  }

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

  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name.trim());
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

  Future<void> clearName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
  }

  /// Explicit completion stamp. Language "all" is a legit choice, so
  /// boot must never infer "not onboarded" from it (that re-prompted
  /// every reopen for All-language users).
  Future<bool> isOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_doneKey) ?? false;
  }

  Future<void> setOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doneKey, true);
  }

  Future<void> clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_languageKey);
    await prefs.remove(_genresKey);
    await prefs.remove(_artistsKey);
  }
}
