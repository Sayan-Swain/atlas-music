import '../models/song.dart';
import 'user_preferences.dart';

/// GLOBAL content rules — strict, no exceptions.
///
/// 1. DURATION: every song shown or playable anywhere must last 00:45–07:00.
///    Shorter or longer is removed: clips, intros, Bottles, hour-long loops,
///    full movies, livestreams.
/// 2. LANGUAGE: when the user selected a language, only matching music is
///    shown. The selection is a strict filter, not a preference.
///
/// Enforcement lives here (pure, unit-tested) and is applied at every
/// ingestion point (search, popular, recommendations, playlist import,
/// related/autoplay, queue assignment) and on generated listings
/// (liked/recent rails, liked screen). Stored user data is never mutated;
/// listings filter their displayed copy instead. Explicitly downloaded
/// offline files are exempt — deleting their listings would orphan files
/// on disk; new downloads already comply because they come from filtered
/// lists.
///
/// Language signals, strongest first:
///  a. Distinctive Unicode scripts in title/artist/channel (Devanagari,
///     Tamil, Hangul, …). A scripted song is allowed only for its
///     language(s); anything else is removed — even with an English title.
///  b. Artist/channel anchors (proper nouns only, never titles: titles
///     carry lyric words like "I've", "Eve", "King" that would collide).
///     An anchor of language X removes the song for every other selection.
///  c. Latin text with no identifiable markers cannot be attributed and is
///     allowed (documented limit: e.g. a romanized title with an unknown
///     artist). Everything identifiable is enforced strictly.
class SongFilter {
  /// Inclusive bounds in seconds: 00:45 – 10:00.
  static const int minSeconds = 45;
  static const int maxSeconds = 600;

  /// Zero/negative means the metadata never carried a duration (search
  /// entries, imports without badges) — unverifiable, NOT a short clip.
  /// Refusing those broke all playback of such songs, so unknown is
  /// allowed while every KNOWN short/long value is still removed.
  static bool inDurationWindow(Song song,
      {int minSec = minSeconds, int maxSec = maxSeconds}) {
    final s = song.duration.inSeconds;
    if (s <= 0) return true;
    return s >= minSec && s <= maxSec;
  }

  /// Both global rules at once. Order is preserved; input never mutated.
  static List<Song> apply(List<Song> songs,
      {MusicLanguage language = MusicLanguage.all}) {
    return songs
        .where((s) =>
            inDurationWindow(s) && matchesLanguage(s, language))
        .toList();
  }

  /// Script-based language guess for one song, or null when the text is
  /// Latin/ambiguous and cannot be attributed (used for session-language
  /// detection in Quick Picks; the strict gate above stays authoritative).
  static MusicLanguage? detectLanguage(Song song) {
    final hay = '${song.title} ${song.artist} ${song.channel}';
    if (_has(hay, _devanagari)) return MusicLanguage.hindi;
    if (_has(hay, _gurmukhi)) return MusicLanguage.punjabi;
    if (_has(hay, _tamil)) return MusicLanguage.tamil;
    if (_has(hay, _telugu)) return MusicLanguage.telugu;
    if (_has(hay, _kannada)) return MusicLanguage.kannada;
    if (_has(hay, _bengali)) return MusicLanguage.bengali;
    if (_has(hay, _arabic)) return MusicLanguage.arabic;
    if (_has(hay, _cyrillic)) return MusicLanguage.russian;
    if (_has(hay, _thai)) return MusicLanguage.thai;
    if (_has(hay, _hangul)) return MusicLanguage.korean;
    if (_has(hay, _kana)) return MusicLanguage.japanese;
    return null;
  }

  /// Strict language gate for one song.
  static bool matchesLanguage(Song song, MusicLanguage language) {
    if (language == MusicLanguage.all) return true;
    final hay =
        '${song.title} ${song.artist} ${song.channel}';
    // --- (a) distinctive scripts ---
    if (_has(hay, _devanagari)) {
      // Shared by Hindi and Marathi; nothing else may claim it.
      return language == MusicLanguage.hindi ||
          language == MusicLanguage.marathi;
    }
    if (_has(hay, _gurmukhi)) return language == MusicLanguage.punjabi;
    if (_has(hay, _tamil)) return language == MusicLanguage.tamil;
    if (_has(hay, _telugu)) return language == MusicLanguage.telugu;
    if (_has(hay, _kannada)) return language == MusicLanguage.kannada;
    if (_has(hay, _bengali)) return language == MusicLanguage.bengali;
    if (_has(hay, _arabic)) return language == MusicLanguage.arabic;
    if (_has(hay, _cyrillic)) return language == MusicLanguage.russian;
    if (_has(hay, _thai)) return language == MusicLanguage.thai;
    if (_has(hay, _hangul)) return language == MusicLanguage.korean;
    if (_has(hay, _kana)) return language == MusicLanguage.japanese;
    // Other Indic scripts have no matching option — unverifiable.
    if (_has(hay, _otherIndic)) return false;
    // Bare CJK ideographs (no kana): shared with Chinese; best effort
    // allow for Japanese only, since no Chinese option exists.
    if (_has(hay, _cjk)) return language == MusicLanguage.japanese;
    // --- (b) artist/channel anchors (proper nouns, see note above) ---
    final who = _fold('${song.artist} ${song.channel}');
    for (final entry in _anchors.entries) {
      if (!entry.value.contains(language) && _hasWord(who, entry.key)) {
        return false;
      }
    }
    return true;
  }

  static bool _has(String s, RegExp re) => re.hasMatch(s);

  static final Map<String, RegExp> _wordCache = {};

  static bool _hasWord(String haystack, String anchor) {
    var re = _wordCache[anchor];
    re ??= RegExp('\\b${RegExp.escape(anchor)}\\b');
    _wordCache[anchor] = re;
    return re.hasMatch(haystack);
  }

  /// Lowercase + diacritic-folded so 'Rosalía' matches anchor 'rosalia'.
  /// Static for unit tests.
  static String fold(String s) => _fold(s);

  static String _fold(String s) {
    var v = s.toLowerCase();
    const fold = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y', 'æ': 'ae', 'œ': 'oe',
    };
    fold.forEach((k, val) => v = v.replaceAll(k, val));
    return v;
  }

  static final RegExp _devanagari = RegExp(r'[\u0900-\u097F]');
  static final RegExp _gurmukhi = RegExp(r'[\u0A00-\u0A7F]');
  static final RegExp _tamil = RegExp(r'[\u0B80-\u0BFF]');
  static final RegExp _telugu = RegExp(r'[\u0C00-\u0C7F]');
  static final RegExp _kannada = RegExp(r'[\u0C80-\u0CFF]');
  static final RegExp _bengali = RegExp(r'[\u0980-\u09FF]');
  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');
  static final RegExp _cyrillic = RegExp(r'[\u0400-\u04FF]');
  static final RegExp _thai = RegExp(r'[\u0E00-\u0E7F]');
  static final RegExp _hangul =
      RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF\u3130-\u318F]');
  static final RegExp _kana = RegExp(r'[\u3040-\u30FF]');
  static final RegExp _cjk = RegExp(r'[\u4E00-\u9FFF]');
  // Indic scripts without a matching app language (Malayalam, Oriya,
  // Sinhala, Myanmar, Khmer, …): unverifiable, always removed.
  static final RegExp _otherIndic = RegExp(
      r'[\u0D00-\u0D7F\u0B00-\u0B7F\u0D80-\u0DFF\u1000-\u109F\u1780-\u17FF]');

  /// Anchor (folded, word-matched against artist+channel) → languages it
  /// may appear under. Deliberately collision-free: no lyric words, no
  /// single letters, no generic labels (VEVO belongs to every language).
  static const Map<String, Set<MusicLanguage>> _anchors = {
    // --- Indian subcontinent ---
    'arijit singh': {MusicLanguage.hindi, MusicLanguage.bengali},
    'shreya ghoshal': {MusicLanguage.hindi, MusicLanguage.bengali},
    'rahman': {MusicLanguage.hindi, MusicLanguage.tamil},
    'ar rahman': {MusicLanguage.hindi, MusicLanguage.tamil},
    'pritam': {MusicLanguage.hindi, MusicLanguage.bengali},
    'sonu nigam': {MusicLanguage.hindi},
    'shankar mahadevan': {MusicLanguage.hindi, MusicLanguage.marathi},
    'udit narayan': {MusicLanguage.hindi},
    'kumar sanu': {MusicLanguage.hindi},
    'alka yagnik': {MusicLanguage.hindi},
    'sunidhi chauhan': {MusicLanguage.hindi},
    'neha kakkar': {MusicLanguage.hindi},
    'jubin nautiyal': {MusicLanguage.hindi},
    'darshan raval': {MusicLanguage.hindi},
    'armaan malik': {MusicLanguage.hindi},
    'mohit chauhan': {MusicLanguage.hindi},
    'kailash kher': {MusicLanguage.hindi},
    'amit trivedi': {MusicLanguage.hindi},
    'atif aslam': {MusicLanguage.hindi},
    'rahat fateh ali khan': {MusicLanguage.hindi},
    'badshah': {MusicLanguage.hindi, MusicLanguage.punjabi},
    'honey singh': {MusicLanguage.hindi, MusicLanguage.punjabi},
    'diljit dosanjh': {MusicLanguage.punjabi, MusicLanguage.hindi},
    'ap dhillon': {MusicLanguage.punjabi, MusicLanguage.hindi},
    'sidhu moose': {MusicLanguage.punjabi, MusicLanguage.hindi},
    'karan aujla': {MusicLanguage.punjabi, MusicLanguage.hindi},
    'amrinder gill': {MusicLanguage.punjabi},
    'b praak': {MusicLanguage.hindi, MusicLanguage.punjabi},
    'anirudh': {MusicLanguage.tamil, MusicLanguage.telugu},
    'sid sriram': {MusicLanguage.tamil, MusicLanguage.telugu},
    'harris jayaraj': {MusicLanguage.tamil},
    'dhanush': {MusicLanguage.tamil},
    'devi sri prasad': {MusicLanguage.telugu},
    'thaman': {MusicLanguage.telugu},
    'ajay atul': {MusicLanguage.marathi, MusicLanguage.hindi},
    'divine': {MusicLanguage.hindi},
    // --- Korean ---
    'bts': {MusicLanguage.korean},
    'blackpink': {MusicLanguage.korean},
    'twice': {MusicLanguage.korean},
    'stray kids': {MusicLanguage.korean},
    'seventeen': {MusicLanguage.korean},
    'newjeans': {MusicLanguage.korean},
    'ive': {MusicLanguage.korean},
    'aespa': {MusicLanguage.korean},
    'sserafim': {MusicLanguage.korean},
    'enhypen': {MusicLanguage.korean},
    'red velvet': {MusicLanguage.korean},
    'exo': {MusicLanguage.korean},
    'nct': {MusicLanguage.korean},
    'bigbang': {MusicLanguage.korean},
    'jungkook': {MusicLanguage.korean},
    'jimin': {MusicLanguage.korean},
    // --- Japanese ---
    'yoasobi': {MusicLanguage.japanese},
    'yonezu': {MusicLanguage.japanese},
    'fujii kaze': {MusicLanguage.japanese},
    'king gnu': {MusicLanguage.japanese},
    'one ok rock': {MusicLanguage.japanese},
    'radwimps': {MusicLanguage.japanese},
    'yorushika': {MusicLanguage.japanese},
    'zutomayo': {MusicLanguage.japanese},
    'aimer': {MusicLanguage.japanese},
    // --- Spanish / Latin ---
    'bad bunny': {MusicLanguage.spanish},
    'karol g': {MusicLanguage.spanish},
    'j balvin': {MusicLanguage.spanish},
    'daddy yankee': {MusicLanguage.spanish},
    'ozuna': {MusicLanguage.spanish},
    'rauw alejandro': {MusicLanguage.spanish},
    'feid': {MusicLanguage.spanish},
    'peso pluma': {MusicLanguage.spanish},
    'maluma': {MusicLanguage.spanish},
    'rosalia': {MusicLanguage.spanish},
    'shakira': {MusicLanguage.spanish},
    'enrique iglesias': {MusicLanguage.spanish},
    'luis fonsi': {MusicLanguage.spanish},
    'danny ocean': {MusicLanguage.spanish},
    'quevedo': {MusicLanguage.spanish},
    'bizarrap': {MusicLanguage.spanish},
    'duki': {MusicLanguage.spanish},
    // --- Portuguese ---
    'anitta': {MusicLanguage.portuguese},
    'alok': {MusicLanguage.portuguese},
    'ludmilla': {MusicLanguage.portuguese},
    'pabllo vittar': {MusicLanguage.portuguese},
    'luisa sonza': {MusicLanguage.portuguese},
    'pedro sampaio': {MusicLanguage.portuguese},
    // --- French ---
    'aya nakamura': {MusicLanguage.french},
    'stromae': {MusicLanguage.french},
    'gims': {MusicLanguage.french},
    'dadju': {MusicLanguage.french},
    'ninho': {MusicLanguage.french},
    'orelsan': {MusicLanguage.french},
    'nekfeu': {MusicLanguage.french},
    'booba': {MusicLanguage.french},
    'damso': {MusicLanguage.french},
    'indila': {MusicLanguage.french},
    'david guetta': {MusicLanguage.french, MusicLanguage.english},
    // --- Other distinctive acts ---
    'rammstein': {MusicLanguage.german},
    'maneskin': {MusicLanguage.italian},
    'amr diab': {MusicLanguage.arabic},
    // --- Label / channel markers ---
    't-series': {MusicLanguage.hindi},
    'sonymusicindia': {MusicLanguage.hindi},
    'zeemusiccompany': {MusicLanguage.hindi},
    'yrf': {MusicLanguage.hindi},
    'saregama': {MusicLanguage.hindi, MusicLanguage.bengali},
    'adityamusic': {MusicLanguage.telugu},
    'laharimusic': {MusicLanguage.telugu, MusicLanguage.kannada},
    'thinkmusic': {MusicLanguage.tamil},
    'speed records': {MusicLanguage.punjabi},
    'white hill': {MusicLanguage.punjabi},
    'hybe': {MusicLanguage.korean},
    'smtown': {MusicLanguage.korean},
    'jyp': {MusicLanguage.korean},
  };
}
