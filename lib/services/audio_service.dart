import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import '../media/cache_service.dart';
import '../media/media_source.dart';
import '../media/resolver_strategy.dart';
import '../media/resolve_failure.dart';
import '../media/providers/youtube_provider.dart';
import '../media/providers/saavn_provider.dart';
import 'storage_service.dart';
import 'song_filter.dart';
import 'user_preferences.dart';
import 'youtube_service.dart';
import 'quick_picks.dart';

/// Playback brain. Knows queue, ExoPlayer, and cache — nothing else.
/// Audio bytes always arrive via [ResolverStrategy] as normalized
/// [MediaSource]s through one finite chain:
///
///   CACHE → provider 1 → provider 2 → provider 3 → FAIL
///
/// No provider-specific HTTP, parsing, or ranking logic lives here.
class AudioPlayerService extends ChangeNotifier {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  final AudioPlayer _player = AudioPlayer();

  /// Metadata only (related/search for autoplay). Streams come from providers.
  final YouTubeService _youtubeService = YouTubeService();
  final CacheService _cache = CacheService();
  final StorageService _storage = StorageService();
  final YouTubeProvider _youTube = YouTubeProvider();
  final SaavnProvider _saavn = SaavnProvider();
  // Chain is YouTube → Saavn. Piped was deleted (Phase B): its public
  // instances returned 502/525 network-wide — dead weight, not reliability.
  late final ResolverStrategy _strategy =
      ResolverStrategy([_saavn, _youTube]);

  // Singleton instance for notification action callbacks.
  static AudioPlayerService? _instance;
  static AudioPlayerService get instance {
    _instance ??= AudioPlayerService._internal();
    return _instance!;
  }
  AudioPlayerService._internal();

  List<Song> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  final Random _random = Random();
  ProcessingState _processingState = ProcessingState.idle;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _lastNotifiedSecond = -1;
  int _playGen = 0;
  Song? _currentSong;
  Timer? _stallTimer;
  DateTime? _lastSkipAt;
  DateTime? _songPlayStart;
  bool _handlingCompletion = false;
  String? _lastRetrySongId;
  int _retryCount = 0;
  Duration _lastStallPosition = Duration.zero;
  // Background resilience: the OS delivers position updates late while
  // backgrounded, so a single stalled window must never skip, and a
  // failed background load must heal itself instead of sitting paused.
  bool _appBackgrounded = false;
  Timer? _bgRetryTimer;
  int _bgRetryCount = 0;
  int _stallCount = 0;
  String? _stallSongId;
  // Background preload: resolve and cache next song while current plays.
  Song? _preloadedNextSong;
  MediaSource? _preloadedNextSource;
  bool _isPreloading = false;
  // Where the current queue came from. 'quickPicks'/'continuation' queues
  // never stop at the end: they grow personalized continuations instead.
  String _queueOrigin = 'default';
  bool _preparingContinuation = false;
  // Queue-end policy: search queues grow seed-based radio instead of
  // stopping (see _playSeedRadio). Playlists/albums/popular keep generic
  // autoplay. Set whenever a new queue is assigned.
  bool _autoplayOnEnd = true;
  // Single-flight gate for queue advancement. Concurrent triggers
  // (duplicate completed events, stall recovery, queue-end chains) must
  // never advance twice — that double advance is the random track skip
  // (e.g. 1 -> 3). Exactly one playNext chain owns the transition at a
  // time; the rest collapse. A user tap steals ownership.
  bool _advancing = false;
  // Seed-based search radio: the song the user tapped to start a search
  // queue. Every queue end fetches tracks similar to this seed.
  Song? _autoplaySeed;
  // Ids + videoIds of finished tracks, excluded from radio batches so the
  // chain never replays or duplicates. Capped to bound memory.
  Set<String> _playedIds = <String>{};
  /// Short human-readable reason for the most recent load failure,
  /// surfaced in toasts so failures are diagnosable, not generic.
  String? _lastFailure;
  String? get lastFailure => _lastFailure;

  void _noteFailure(String detail) {
    var d = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (d.length > 140) d = '${d.substring(0, 140)}…';
    _lastFailure = d.isEmpty ? null : d;
  }
  // How the last load failed. Transient (network/timeout/offline) means
  // the SAME song should be retried — the next one would fail identically.
  // Only a definitive format rejection counts as permanent (skip ahead).
  bool _lastLoadWasTransient = true;

  /// Called from the app lifecycle observer. Never throws.
  void setAppBackgrounded(bool backgrounded) {
    _appBackgrounded = backgrounded;
    _dlog('lifecycle backgrounded=$backgrounded song=${_currentSong?.id}');
  }

  /// Lifecycle breadcrumb log. Compiled OUT of release builds
  /// ([kDebugMode] only): zero production impact. Run `flutter run` and
  /// filter logcat for `ATLAS-PLAYER` to trace song load → play →
  /// preload → background → completion → next-song transitions.
  static void _dlog(String msg) {
    final line = 'ATLAS-PLAYER $msg';
    // ignore: avoid_print
    print(line);
    // TEMPORARY diagnostic mirror: some devices/emulators swallow stdout
    // so logcat shows nothing. Pull with:
    // adb exec-out run-as com.atlas.music.atlas_music cat cache/atlas_trace.log
    // (app cache dir; removed once the restart is root-caused).
    try {
      final f = File('${Directory.systemTemp.path}/atlas_trace.log');
      if (f.existsSync() && f.lengthSync() > 524288) return;
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $line\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  /// True while [songId] + [gen] still own the active player. Every async
  /// sequence that touches [_player] (loads, nudges, resumes, heals)
  /// captures both and bails the moment either changes — a stale command
  /// must never seek/stop/play a newer song's source.
  bool _stillCurrent(String? songId, int gen) =>
      gen == _playGen && songId != null && songId == _currentSong?.id;

  /// Record listen stats for the song that just finished or was skipped.
  void _recordPreviousListen({required bool skipped}) {
    final prev = _currentSong;
    final start = _songPlayStart;
    if (prev == null || start == null) return;
    final listenedMs = DateTime.now().difference(start).inMilliseconds;
    if (listenedMs < 1000) return;
    final durMs = prev.duration.inMilliseconds;
    final reallySkipped = skipped || (durMs > 0 && listenedMs < durMs * 0.8);
    _storage.recordListen(prev, listenedMs: listenedMs, skipped: reallySkipped);
  }

  void _startTracking(Song song) {
    _recordPreviousListen(skipped: true);
    _currentSong = song;
    _songPlayStart = DateTime.now();
  }

  void _markCompleted() {
    // Radio exclusion: a finished track must never come back in a later
    // radio batch (no replays, no duplicates).
    final cur = _currentSong;
    if (cur != null) {
      _playedIds.add(cur.id);
      _playedIds.add(cur.videoId ?? cur.id);
      if (_playedIds.length > 1000) {
        _playedIds = _playedIds.skip(500).toSet();
      }
    }
    _recordPreviousListen(skipped: false);
  }

  /// Double-fire guard: Bluetooth double-events, double taps, and pocket
  /// taps on notification buttons can land twice within milliseconds.
  /// Second hit inside window is a no-op (silent success, no toast).
  bool _skipGuard() {
    final now = DateTime.now();
    if (_lastSkipAt != null &&
        now.difference(_lastSkipAt!) < const Duration(milliseconds: 600)) {
      return false;
    }
    _lastSkipAt = now;
    return true;
  }

  AudioPlayer get player => _player;
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffleEnabled => _shuffle;
  LoopMode get loopMode => _loopMode;
  ProcessingState get processingState => _processingState;
  Duration get duration => _duration;
  Duration get position => _position;
  Song? get currentSong => _currentSong;

  AudioPlayerService() {
    _instance = this;
    _initSession();
    // TEMPORARY boot marker: proves which binary is on device.
    _dlog('BOOT atlas_music debug binary');
    _cache.sweep();
    // Listen to player state for notification updates.
    _player.playerStateStream.listen((state) {
    });
    _player.positionStream.listen((_) {
    });
    _player.positionStream.listen((position) {
      _position = position;
      // Stall watchdog keeps its own baseline in _lastStallPosition.
      // Do not overwrite it or cancel the timer on every tick, otherwise
      // the watchdog either never fires or always sees zero advancement.
      // Cap rebuilds at 1/sec: every tick rebuilds all watchers (grids,
      // sliders, buttons) and on slow phones that jank eats taps.
      if (position.inSeconds != _lastNotifiedSecond) {
        _lastNotifiedSecond = position.inSeconds;
        notifyListeners();
      }
      _maybePreloadNext(position);
    });

    _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      // Duration trace: a ~15s reported duration on a minutes-long song
      // means the source itself is truncated (native layer), not a Dart
      // restart — the key discriminator for the restart investigation.
      _dlog('duration ${_duration.inSeconds}s song=${_currentSong?.id}');
      notifyListeners();
    });

    _player.playerStateStream.listen((state) {
      _dlog('state ${state.processingState} playing=${state.playing} '
          'pos=${_position.inSeconds}s dur=${_duration.inSeconds}s '
          'song=${_currentSong?.id}');
      _processingState = state.processingState;
      // Drive the UI from the ACTUAL player state. On completion the player
      // still reports playing==true (nothing paused it), which left the UI
      // stuck on "playing" while the audio was silent. Force it false on
      // completed/idle so the play/pause control matches reality.
      _isPlaying = state.playing &&
          state.processingState != ProcessingState.completed;
      if (state.processingState == ProcessingState.completed) {
        if (_loopMode == LoopMode.one) {
          notifyListeners();
          return;
        }
        _handleCompletion();
      }
      notifyListeners();
    });
  }

  /// Completion handler that only advances when playback genuinely finished.
  /// A `completed` event with the position far from the end is premature
  /// (truncated range, network cut mid-stream — the classic ~15s stall).
  /// Premature => resume IN PLACE from the last known position, never a
  /// full reload: reloading restarts the song from 00:00 and, on a
  /// restricted network, burns the queue and strands playback paused.
  /// Bounded (2 in-place tries): a truly dead source skips ahead instead
  /// of looping. Genuine => record + playNext. The position check runs in
  /// background too — backgrounding alone must never read as finished.
  void _handleCompletion() {
    if (_handlingCompletion) return;
    final cur = _currentSong;
    if (cur == null) return;
    // Stale completed from the previous source tearing down always carries
    // pos ~0. It can land after the new load already finished (_isLoading
    // false), and the old guard then let it skip/reload the new song —
    // the 1->3 jump. A real completion is never at pos <2s, so ignore all.
    if (_position.inSeconds < 2) return;
    _handlingCompletion = true;
    // Ownership snapshot: a late/duplicate completed from a previous
    // source must not command the current one (see _stillCurrent).
    final eventGen = _playGen;

    final dur = _duration.inSeconds > 0 ? _duration : cur.duration;
    final pos = _position;
    _dlog('completed song=${cur.id} pos=${pos.inSeconds}s '
        'dur=${dur.inSeconds}s gen=$eventGen');
    // Genuine only when the position proves it: within 5s of the end or
    // past 80%. Anything earlier is an interrupted source, not an ending.
    bool genuine = true;
    if (dur.inSeconds > 0) {
      final nearEnd = pos >= dur - const Duration(seconds: 5);
      final pastMost = dur.inMilliseconds > 0 &&
          pos.inMilliseconds >= dur.inMilliseconds * 0.8;
      if (!nearEnd && !pastMost) {
        genuine = false;
      }
      // Truncated file check: ExoPlayer duration far shorter than metadata.
      final expected = cur.duration;
      if (expected.inSeconds > 0 &&
          _duration.inSeconds > 0 &&
          _duration.inSeconds + 10 < expected.inSeconds) {
        genuine = false;
      }
      // Heuristic for missing metadata: a player-reported duration <60s is almost always a truncated/preview stream, not a real end. Treat as premature to avoid the 00:00 restart loop.
      if (expected.inSeconds == 0 &&
          _duration.inSeconds > 0 &&
          _duration.inSeconds < 60) {
        genuine = false;
      }
      // Aggressive guard: any player-reported duration <60s is suspicious for a music track. Force premature handling to avoid treating a truncated preview as a genuine end.
      if (_duration.inSeconds > 0 &&
          _duration.inSeconds < 60) {
        genuine = false;
      }
    }

    if (!genuine) {
      // Premature completion: continue the SAME source from the SAME
      // position. Never stop/reload it — that is the 00:00 restart bug.
      // If the track stopped very early (<60s), it's almost certainly a
      // preview/truncated stream that will never recover. Skip ahead
      // instead of looping on the same broken source.
      if (pos.inSeconds < 60) {
        // Avoid restarting the same track on single-item queue (any loop mode)
        // which causes immediate 00:00 restart loop.
        final isSingleItem = _queue != null && _queue!.length <= 1;
        _handlingCompletion = false;
        _retryCount = 0;
        _lastRetrySongId = null;
        _markCompleted();
        if (isSingleItem) {
          // Search radio owns the future: a broken seed still yields
          // fresh similar tracks instead of a dead pause.
          if ((_queueOrigin == 'search' || _queueOrigin == 'searchRadio') &&
              _autoplayOnEnd) {
            playNext();
            return;
          }
          // Pause instead of re-loading the same broken source.
          Future.microtask(() async {
            try { await _player.pause(); } catch (_) {}
          });
          return;
        }
        playNext();
        return;
      }
      if (_lastRetrySongId == cur.id) {
        _retryCount++;
      } else {
        _lastRetrySongId = cur.id;
        _retryCount = 1;
      }
      if (_retryCount > 2) {
        _retryCount = 0;
        _lastRetrySongId = null;
        _handlingCompletion = false;
        _markCompleted();
        playNext();
        return;
      }
      final resumeAt = pos;
      _handlingCompletion = false;
      _dlog('premature attempt=$_retryCount song=${cur.id} '
          'resumeAt=${resumeAt.inSeconds}s');
      Future.microtask(() async {
        try {
          // Ownership check: user taps / newer loads own the player now.
          if (!_stillCurrent(cur.id, eventGen)) {
            _dlog('resume aborted (stale) song=${cur.id}');
            return;
          }
          await _activateSession();
          if (!_stillCurrent(cur.id, eventGen)) return;
          // Avoid seek on premature completion: seeking a truncated/preview
          // stream often resets to start, causing the 00:00 restart loop.
          // Reload the source with a fresh URL to recover from token expiry /
          // truncated stream instead of trying to resume in place.
          if (!_stillCurrent(cur.id, eventGen)) return;
          // Reload song to get fresh URL / fresh stream.
          await playSong(cur, index: _currentIndex);
          return;
          _dlog('resumed in place song=${cur.id}');
          _startStallTimer();
        } catch (_) {
          try {
            syncPlaybackState();
          } catch (_) {}
        }
      });
      return;
    }

    _retryCount = 0;
    _lastRetrySongId = null;
    _markCompleted();
    _dlog('genuine song=${cur.id} -> playNext');
    // Reset flag on next microtask so double-fired completed events
    // for the same song are ignored, but future songs can complete.
    Future.microtask(() => _handlingCompletion = false);
    // Small delay to avoid race with player state transition
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_stillCurrent(cur.id, eventGen)) {
        playNext();
      }
    });
  }

  /// Activates the audio session, never hanging: every await here talks
  /// to the platform and must be bounded, otherwise one stuck call would
  /// freeze playback startup (infinite spinner, "loads, nothing happens").
  Future<void> _activateSession() async {
    try {
      final session = await AudioSession.instance
          .timeout(const Duration(seconds: 5));
      await session
          .setActive(true)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        // Duck (brief volume dip), never full pause, on transient
        // focus loss (notification sounds, assistant blips). True made
        // every notification stop music then auto-resume seconds later.
        androidWillPauseWhenDucked: false,
      ));
    } catch (_) {
      // Audio still plays without a configured session on most devices.
    }
  }

  /// Returns true when audio actually started. False = silent FAIL
  /// (all paths exhausted) or superseded tap — caller decides whether
  /// to toast by checking the song is still current.
  /// [autoplayOnEnd] decides queue-end behavior for a newly assigned
  /// queue: true fetches related autoplay content (playlists, popular),
  /// false ends playback normally (search results).
  /// [queueOrigin] tags a newly assigned queue ('quickPicks', ...).
  /// Quick-Picks/continuation queues grow personalized continuations at
  /// the end instead of stopping or playing unrelated autoplay content.
  Future<bool> playSong(Song song,
      {List<Song>? queue,
      int? index,
      bool autoplayOnEnd = true,
      String? queueOrigin}) async {
    // Duplicate request for the song already loading (double-tap, retap
    // during a slow load): absorb it BEFORE bumping the generation. A
    // second sequence would stop the first one's source mid-play and
    // reload it — an audible restart from 00:00 seconds later when the
    // second resolve/setSource lands. The in-flight load owns playback.
    // (Deliberate replay of an already-PLAYING song still works: it is
    // not loading, so it falls through.) Retries use queue==null and are
    // unaffected.
    // Latest tap wins: rapid skip taps supersede in-flight loads instead
    // of racing them (two setAudioSource calls interleaved = dead buttons).
    // [gen] is this load's ownership token: every await boundary below
    // re-checks it, so a superseded load can never command the player.
    _lastFailure = null;
    final int gen = ++_playGen;
    bool stale() => gen != _playGen;
    _dlog('load song=${song.id} gen=$gen');
    // Assign synchronously (before the first await) so a second tap that
    // lands during stop() already sees the new index. Otherwise both taps
    // compute next from the same stale _currentIndex and the second tap
    // replays the first tap's song.
    if (queue != null) {
      // GLOBAL rules: queues never carry out-of-window (00:45–07:00) or
      // wrong-language songs — search, playlists, autoplay, everywhere.
      // Remap by id (callers may index an unfiltered stored list).
      // EXCEPTION: the explicitly tapped song always plays. Language and
      // duration filters govern recommendations and autoplay — never a
      // manual selection. The rest of the queue stays filtered.
      List<Song> filtered = queue;
      try {
        final lang = await UserPreferences().getLanguage();
        filtered = SongFilter.apply(queue, language: lang);
      } catch (_) {
        filtered = queue;
      }
      var at = filtered.indexWhere((s) => s.id == song.id);
      if (at < 0) {
        _dlog('manual override song=${song.id} bypasses queue filter');
        final fallback = List<Song>.from(filtered);
        final rawAt = queue.indexWhere((s) => s.id == song.id);
        at = (rawAt < 0 ? fallback.length : rawAt)
            .clamp(0, fallback.length);
        fallback.insert(at, song);
        filtered = fallback;
      }
      _queue = filtered;
      _currentIndex = at;
      _autoplayOnEnd = autoplayOnEnd;
      _queueOrigin = queueOrigin ?? 'default';
      _preparingContinuation = false;
      // A newly assigned queue owns the future: cancel any in-flight
      // automatic advance so it cannot advance this fresh queue twice.
      _advancing = false;
      // (Re)seed search radio on every manual search play; any other
      // fresh queue clears a stale search seed.
      if (_queueOrigin == 'search') {
        _autoplaySeed = song;
      } else if (_queueOrigin != 'searchRadio') {
        _autoplaySeed = null;
      }
    }
    // A new load attempt supersedes any pending background heal.
    _cancelBackgroundRetry();
    // If the SAME song is already playing past 5 s, absorb ANY reload
    // (preload, continuation, retry, background heal) — a second
    // setSource would reset position to 0 and cause the 17 s restart.
    if (_currentSong?.id == song.id &&
        _player.playing &&
        _position.inSeconds > 5) {
      _dlog('load absorbed active playback song=${song.id} pos=${_position.inSeconds}s');
      return true;
    }
    // Fresh song => reset retry budgets. Same-song retry (from
    // _handleCompletion or the background healer) keeps its count.
    if (_currentSong?.id != song.id) {
      _retryCount = 0;
      _lastRetrySongId = null;
      _bgRetryCount = 0;
      _cancelBackgroundRetry();
      _stallCount = 0;
      _stallSongId = null;
      _clearPreloadState();
      _preparingContinuation = false;
    }
    _currentSong = song;
    // Reset position/duration so stale values from previous track cannot
    // make a premature completed event look genuine (17s skip loop).
    _position = Duration.zero;
    _duration = Duration.zero;
    _lastNotifiedSecond = -1;
    _handlingCompletion = false;
    _startTracking(song);
    try {
      _cancelStallTimer();
      // Re-activate the session up front: after backgrounding the OS may
      // have taken focus, and starting without it leaves the new track
      // silently paused — the stuck-paused-next-song complaint.
      await _activateSession();
      if (stale()) {
        _dlog('load aborted after session song=${song.id} gen=$gen');
        return false;
      }
      // Cut old audio immediately so a skip feels instant even though the
      // next song still needs seconds of network. Bounded: an unbounded
      // stop wedged here forever is the stuck "tap does nothing" bug —
      // every manual selection must proceed to its own load.
      try {
        await _player.stop().timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (stale()) return false;
      _isLoading = true;
      notifyListeners();

      final report =
          PlaybackReport(song.title, songId: song.videoId ?? song.id);
      // Only a definitive format rejection counts as permanent. Everything
      // else (timeouts, DNS, throttling, truncation) is transient: retrying
      // the SAME song is correct, skipping ahead just strands playback on
      // a later song that fails identically.
      bool sawPermanentFormat = false;

      // 1. CACHE — offline-first replay, zero network.
      final cached = await _cache.getValid(song);
      if (stale()) return false;
      if (cached != null) {
        try {
          await _playFile(cached.path, song, stale);
          if (stale()) return false;
          _finishPlaying();
          return true;
        } catch (e) {
          // Cache playback failure is not necessarily permanent — the file
          // may still be valid. Only invalidate if the error is a format/codec
          // issue, not a transient network/timeout issue.
          final t = e.toString().toLowerCase();
          final isTransient = e is TimeoutException ||
              t.contains('timeout') ||
              t.contains('host lookup') ||
              t.contains('socket') ||
              t.contains('connection') ||
              t.contains('unreachable');
          if (isTransient) {
            // Transient error: keep cache, proceed to provider resolution.
            // Don't invalidate — the stream may work on retry or via a different path.
          } else {
            // Permanent format/corruption issue: invalidate and report.
            report.add(ResolveFailure(
              provider: null,
              stage: ResolveStage.playback,
              detail: 'cached file unplayable, evicted: $e',
              retryable: true,
            ));
            await _cache.invalidate(song);
          }
        }
      }

      // Network gate: avoid provider chain when offline and cache already tried.
      final online = await _hasConnectivity();
      if (!online) {
        if (_queue.length > 1) {
          // Skip to next track that might be cached rather than hanging.
          await playNext();
        }
        throw Exception('Offline and no cache');
      }

      // 2. RESOLVE through the provider chain.
      final source = await _strategy.resolveFirstValid(song, report);
      if (stale()) return false;
      _dlog(source == null
          ? 'resolve failed song=${song.id} attempts=${report.attempts.length}'
          : 'resolved song=${song.id} provider=${source.provider}');
      if (source == null) {
        // Nothing resolved at all: fail fast here instead of running a
        // second doomed resolve inside the download step.
        _lastLoadWasTransient = report.attempts.isEmpty ||
            report.attempts.any((a) => a.scope != FailureScope.song);
        // Last attempt, not first: the toast must show the final
        // fallback's error (YouTube), not the first provider's miss
        // (Saavn) — first-detail toasts blamed the wrong provider.
        _noteFailure(report.attempts.isNotEmpty
            ? report.attempts.last.detail
            : 'no playable source found');
        _isLoading = false;
        notifyListeners();
        _scheduleBackgroundRetry();
        return false;
      }

      // 3. STREAM first: fastest start, and the truncation guard above
      // refuses short snippets up front instead of playing them.
      try {
        await _playUrl(source, song, stale);
        if (stale()) return false;
        _finishPlaying();
        return true;
      } catch (e) {
        // Ownership abort is not a stream failure: a superseded load must
        // never trigger downloads, reports, or retries for a dead attempt.
        if (stale()) {
          _dlog('load superseded at stream song=${song.id} gen=$gen');
          return false;
        }
        _dlog('stream failed song=${song.id} err=$e');
        // ExoPlayer rejection — only a format/codec failure counts as
        // permanent; network failures stay transient (retry same song).
        final isNetwork = _isNetworkError(e);
        final t = e.toString().toLowerCase();
        final isFormat = !isNetwork &&
            (t.contains('format') ||
                t.contains('codec') ||
                t.contains('decoder') ||
                t.contains('mime') ||
                t.contains('unsupported') ||
                t.contains('extractor') ||
                t.contains('drm'));
        report.add(ResolveFailure(
          provider: source.provider,
          stage: ResolveStage.playback,
          detail:
              'ExoPlayer rejected stream [${_classifyPlayerError(e)}]: $e',
          retryable: !isFormat,
        ));
        if (isFormat) sawPermanentFormat = true;
        // Fall through to verified download.
      }

      // 4. DOWNLOAD the resolved source, verify it, play the file.
      // The commit size check rejects truncated and preview-length files,
      // so a short snippet can never pose as a song. The already-resolved
      // source downloads directly (no second manifest fetch); a fresh
      // chain is only a fallback.
      File? audioFile;
      try {
        audioFile = await _downloadSource(source, song, report);
        if (stale()) return false;
      } catch (e) {
        if (stale()) {
          _dlog('load superseded at download song=${song.id} gen=$gen');
          return false;
        }
        _dlog('download failed song=${song.id} err=$e');
        report.add(ResolveFailure(
          provider: source.provider,
          stage: ResolveStage.download,
          detail: 'download failed: $e',
          retryable: true,
        ));
        audioFile = null;
      }
      if (audioFile != null) {
        try {
          await _playFile(audioFile.path, song, stale);
          if (stale()) return false;
          _finishPlaying();
          return true;
        } catch (e) {
          // A size-verified local file failing to play is a player-state
          // issue, not a bad song: keep it transient so the same track
          // is retried instead of skipped.
          report.add(ResolveFailure(
            provider: source.provider,
            stage: ResolveStage.playback,
            detail: 'cached file playback failed: $e',
            retryable: true,
          ));
        }
      }

      // 4. FAIL with the full structured chain — never throw; keep state stable.
      if (stale()) return false;
      // Do not throw — instead report the failure to the user via the
      // playback report and keep the current song state stable.
      report.add(ResolveFailure(
        provider: null,
        stage: ResolveStage.playback,
        detail: 'all providers failed: ${report.toUserMessage()}',
        retryable: false,
      ));
      _lastLoadWasTransient = !sawPermanentFormat;
      _noteFailure(report.attempts.isNotEmpty
          ? report.attempts.last.detail
          : 'all providers failed');
      _dlog('load failed song=${song.id} transient=$_lastLoadWasTransient '
          'reason=$_lastFailure');
      _isLoading = false;
      notifyListeners();
      _scheduleBackgroundRetry();
      return false;
    } catch (e) {
      if (stale()) return false;
      _cancelStallTimer();
      _isLoading = false;
      notifyListeners();
      // Offline gate and unexpected errors: transient by definition.
      _lastLoadWasTransient = true;
      _noteFailure('$e');
      _scheduleBackgroundRetry();
      rethrow;
    }
  }

  /// One-shot self-heal for background loads: a failed autoplay in
  /// background used to sit paused on the next song until the user opened
  /// the app. Retries the same stuck track with backoff
  /// (6s/15s/30s/60s/120s, max 5 — background network restrictions can
  /// outlast a short window) while it never started playing; any success,
  /// new song, pause, or stop cancels. Never loops forever.
  void _scheduleBackgroundRetry() {
    if (!_appBackgrounded) return;
    if (_bgRetryCount >= 5) return;
    final song = _currentSong;
    if (song == null) return;
    _bgRetryTimer?.cancel();
    const delays = [6, 15, 30, 60, 120];
    final delay = delays[_bgRetryCount.clamp(0, delays.length - 1)];
    final q = List<Song>.from(_queue);
    final idx = _currentIndex;
    // Ownership snapshot: a user tap before the timer fires supersedes
    // the heal — playSong's own token then aborts the stale attempt.
    final healGen = _playGen;
    _dlog('heal scheduled song=${song.id} in ${delay}s');
    _bgRetryTimer = Timer(Duration(seconds: delay), () async {
      _bgRetryTimer = null;
      // Only heal a track that never started: still current, silent at 0.
      // Anything else is user intent or newer playback — leave alone.
      if (!_stillCurrent(song.id, healGen)) return;
      if (_player.playing || _position > Duration.zero) return;
      _dlog('heal firing song=${song.id}');
      _bgRetryCount++;
      try {
        // Preserve the queue's origin: a healed Quick Picks queue must
        // stay a never-ending queue, not degrade to generic autoplay.
        final keepOrigin = _queueOrigin;
        await playSong(song,
            queue: q.isNotEmpty ? q : null,
            index: q.isNotEmpty ? idx.clamp(0, q.length - 1) : null,
            autoplayOnEnd: _autoplayOnEnd,
            queueOrigin: keepOrigin);
      } catch (_) {}
    });
  }

  void _cancelBackgroundRetry() {
    _bgRetryTimer?.cancel();
    _bgRetryTimer = null;
  }

  /// When the current song is within [threshold] of its end, resolve and
  /// cache the next song so playNext can start instantly from file.
  void _maybePreloadNext(Duration position) {
    if (_isPreloading) return;
    if (_currentSong == null) return;
    if (_queue.isEmpty || _currentIndex < 0) return;
    if (_player.processingState == ProcessingState.completed) return;
    if (_player.processingState == ProcessingState.idle) return;

    final dur = _duration;
    if (dur.inSeconds <= 0) return;

    // Only trigger when within threshold of the end. 45s gives a slow
    // connection a full minute to finish the download before completion.
    final remaining = dur - position;
    if (remaining > const Duration(seconds: 45)) return;
    if (remaining < Duration.zero) return;

    // Already cached? Skip preload.
    final next = _computeNextSong();
    if (next == null) {
      // At the end of a never-ending queue: grow the continuation now so
      // the next song (and its file) already exists when this one ends.
      _prepareContinuation();
      return;
    }
    if (_preloadedNextSong?.id == next.id && _preloadedNextSource != null) return;

    _preloadNextSong(next);
  }

  /// Determine which song would play next, respecting shuffle/loop.
  Song? _computeNextSong() {
    if (_queue.isEmpty || _currentIndex < 0) return null;
    if (_shuffle &&
        _queue.length > 1 &&
        _queueOrigin != 'search' &&
        _queueOrigin != 'searchRadio') {
      int next;
      do { next = _random.nextInt(_queue.length); }
      while (next == _currentIndex);
      return _queue[next];
    }
    if (_currentIndex < _queue.length - 1) return _queue[_currentIndex + 1];
    if (_loopMode == LoopMode.all) return _queue.first;
    // Queue end and no repeat: will call _autoPlay, can't predict.
    return null;
  }

  /// Resolve and cache a single song without touching the player or
  /// any playback state. Fire-and-forget: errors are swallowed.
  Future<void> _preloadNextSong(Song song) async {
    if (_isPreloading) return;
    _isPreloading = true;
    _dlog('preload start song=${song.id}');
    try {
      // Already fully cached? Nothing to do.
      final cached = await _cache.getValid(song);
      if (cached != null) return;
      // Must be online to resolve a stream.
      if (!await _hasConnectivity()) return;

      final report = PlaybackReport(song.title, songId: song.videoId ?? song.id);
      final source = await _strategy.resolveFirstValid(song, report);
      if (source == null) return;
      _preloadedNextSong = song;
      _preloadedNextSource = source;

      // Download into cache so playNext reads file instantly.
      try {
        final tmp = _cache.stageFile(song);
        try {
          final resolver = source.provider == MediaProvider.saavn
              ? _saavn
              : _youTube;
          await resolver
              .download(source, tmp)
              .timeout(const Duration(seconds: 150));
        } catch (_) {
          try { if (await tmp.exists()) await tmp.delete(); } catch (_) {}
          final fresh = await _strategy.downloadFirstValid(
            song, tmp, report,
            budget: const Duration(seconds: 90),
          );
          if (fresh == null) return;
          await _cache.commit(song, tmp, fresh);
          return;
        }
        await _cache.commit(song, tmp, source);
      } catch (_) {}
    } catch (_) {}
  }

  /// Clear preload state so the next preload cycle targets the right song.
  void _clearPreloadState() {
    _preloadedNextSong = null;
    _preloadedNextSource = null;
    _isPreloading = false;
  }

  /// Grow a never-ending queue BEFORE the current song ends: build the
  /// personalized continuation and append it, then preload the first new
  /// file. Touches only [_queue] — the player and current song are left
  /// alone, so playback never stutters. Fire-and-forget.
  Future<void> _prepareContinuation() async {
    if (_preparingContinuation) return;
    if (_currentSong == null) return;
    if (!_autoplayOnEnd) return;
    if (_queueOrigin != 'quickPicks' && _queueOrigin != 'continuation') {
      return;
    }
    _resyncIndex();
    if (_currentIndex < _queue.length - 1) return; // not at the end
    _preparingContinuation = true;
    try {
      final anchor = _currentSong!;
      final songs = await _buildContinuation(count: 10);
      if (songs.isEmpty) return;
      // User moved on while we worked: discard, fresh cycle owns it.
      if (_currentSong?.id != anchor.id) return;
      _resyncIndex();
      if (_currentIndex < _queue.length - 1) return;
      _queue = [..._queue, ...songs];
      _queueOrigin = 'continuation';
      _dlog('continuation appended ${songs.length} after=${anchor.id}');
      notifyListeners();
      // Next song now known: resolve + cache its file immediately.
      _preloadNextSong(songs.first);
    } catch (_) {
    } finally {
      _preparingContinuation = false;
    }
  }

  /// Ranked personalized continuation from on-device behavior signals:
  /// session (strongest), meaningful listens/replays, likes, top
  /// artists/genres, selected prefs, and recent searches. Excludes
  /// everything already played in this queue. Never throws.
  Future<List<Song>> _buildContinuation({int count = 10}) async {
    try {
      final cur = _currentSong;
      if (cur == null) return const [];
      final recent = await _storage.getRecentlyPlayed();
      final stats = await _storage.getListeningStats();
      final topArtists = await _storage.getTopArtists(limit: 10);
      final topGenres = await _storage.getTopGenres(limit: 5);
      final liked = await _storage.getLikedSongs();
      final searches = await _storage.getSearchHistory();
      MusicLanguage lang = MusicLanguage.all;
      Set<String> selGenres = {};
      Set<String> selArtists = {};
      try {
        final prefs = UserPreferences();
        lang = await prefs.getLanguage();
        selGenres = await prefs.getGenres();
        selArtists = await prefs.getArtists();
      } catch (_) {}
      // Candidate queries follow the session first, long-term taste next.
      final queries = <String>[];
      if (cur.artist.isNotEmpty) queries.add('${cur.artist} album tracks');
      for (final s in recent.take(4)) {
        if (queries.length >= 4) break;
        if (s.artist.isNotEmpty &&
            s.artist.toLowerCase() != cur.artist.toLowerCase()) {
          queries.add('${s.artist} album tracks');
        }
      }
      for (final a in topArtists) {
        if (queries.length >= 5) break;
        if (a.toLowerCase() == cur.artist.toLowerCase()) continue;
        queries.add('$a album tracks');
      }
      for (final q in searches.take(2)) {
        if (queries.length >= 6) break;
        queries.add('$q official audio');
      }
      if (queries.isEmpty) queries.add('trending songs official audio');
      final pool = <Song>[];
      final seen = <String>{};
      await Future.wait(queries.take(6).map((q) async {
        try {
          final songs = await _youtubeService
              .search(q, limit: 10)
              .timeout(const Duration(seconds: 8));
          for (final s in SongFilter.apply(songs, language: lang)) {
            if (seen.add(s.videoId ?? s.id)) pool.add(s);
          }
        } catch (_) {}
      }));
      if (pool.isEmpty) return const [];
      final playedIds = <String>{
        ..._queue.map((s) => s.id),
        ..._queue.map((s) => s.videoId ?? s.id),
      };
      final sessionRecent = [
        cur,
        ...recent.where((s) => s.id != cur.id).take(4),
      ];
      final picks = QuickPicksEngine.rank(
        recent: sessionRecent,
        candidates: pool,
        stats: stats,
        topArtists: topArtists,
        topGenres: [...topGenres, ...selGenres],
        likedIds: liked.map((s) => s.id).toSet(),
        queueIds: playedIds,
        userLanguage: lang,
        searchHistory: searches,
        selectedArtists: selArtists.toList(),
        count: count,
        seedHint: cur.id.hashCode,
      );
      return picks.map((p) => p.song).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Queue-end for never-ending queues: play what the background prepare
  /// already appended, else build the continuation now and play it.
  /// Never stops, never pauses, never repeats the finished queue.
  Future<bool> _playContinuation() async {
    _resyncIndex();
    if (_currentIndex < _queue.length - 1) {
      final target = _queue[_currentIndex + 1];
      if (await _playWithRetry(target, _currentIndex + 1)) return true;
      if (_currentSong?.id != target.id) return true;
    }
    final songs = await _buildContinuation(count: 10);
    if (songs.isEmpty) {
      // Nothing to play: in background schedule the healer instead of
      // sitting paused — network may return before the user reopens.
      _scheduleBackgroundRetry();
      return false;
    }
    _resyncIndex();
    final base = _currentIndex + 1;
    _queue = [..._queue, ...songs];
    _queueOrigin = 'continuation';
    notifyListeners();
    final target = songs.first;
    if (await _playWithRetry(target, base)) return true;
    if (_currentSong?.id != target.id) return true;
    // Load failed after retries: heal in background, never sit paused.
    _scheduleBackgroundRetry();
    return false;
  }

  void _finishPlaying() {
    _isLoading = false;
    // Called only after play() resolved: mark playing now instead of
    // waiting on the stream event. A late playing=false teardown emission
    // otherwise pinned pet/UI to idle on fresh starts until a pause/play
    // nudge. Stream corrections afterward still apply.
    _isPlaying = true;
    _bgRetryCount = 0;
    _cancelBackgroundRetry();
    _dlog('playing song=${_currentSong?.id}');
    notifyListeners();
    _startStallTimer();
  }

  /// Background playback requires every source to carry a MediaItem tag.
  /// Without it the foreground service has nothing to bind to and the
  /// OS kills audio on screen-off / app background.
  MediaItem _mediaTag(Song song) {
    Uri? art;
    final thumb = song.thumbnailUrl.trim();
    if (thumb.startsWith('http')) {
      try {
        art = Uri.parse(thumb);
      } catch (_) {
        art = null;
      }
    }
    return MediaItem(
      id: song.videoId ?? song.id,
      title: song.title,
      artist: song.artist.isEmpty ? null : song.artist,
      artUri: art,
      duration: song.duration == Duration.zero ? null : song.duration,
    );
  }

  Map<String, String> _headersFor(MediaSource source) {    // googlevideo checks Origin/Referer consistency; plain CDNs/proxies
    // only need a browser UA.
    if (source.provider == MediaProvider.youTube && !source.isProxy) {
      return {
        'User-Agent': _ua,
        'Accept': '*/*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Origin': 'https://www.youtube.com',
        'Referer': 'https://www.youtube.com/',
        'Connection': 'keep-alive',
      };
    }
    return {'User-Agent': _ua};
  }

  /// Buckets player failures so the report says *why* (network vs
  /// format) instead of one opaque line. Heuristic on exception text.
  String _classifyPlayerError(Object e) {
    final t = e.toString().toLowerCase();
    if (t.contains('socket') ||
        t.contains('timeout') ||
        t.contains('timed out') ||
        t.contains('host lookup') ||
        t.contains('connection') ||
        t.contains('network') ||
        t.contains('unreachable') ||
        t.contains('certificate') ||
        t.contains('handshake')) {
      return 'network';
    }
    if (t.contains('format') ||
        t.contains('codec') ||
        t.contains('decoder') ||
        t.contains('mime') ||
        t.contains('unsupported') ||
        t.contains('extractor') ||
        t.contains('drm')) {
      return 'format';
    }
    return 'unknown';
  }

  /// Returns true when the error is a transient network issue (DNS,
  /// host lookup, connection) that should not count as a permanent
  /// provider failure.
  bool _isNetworkError(Object e) {
    final t = e.toString().toLowerCase();
    return t.contains('socket') ||
        t.contains('timeout') ||
        t.contains('host lookup') ||
        t.contains('connection') ||
        t.contains('network') ||
        t.contains('unreachable');
  }

  /// Online gate. Multi-host: single-host DNS failure (filtered
  /// networks, captive portals) must never read as offline when
  /// YouTube itself resolves. First hit wins, so the online path
  /// stays as fast as before.
  Future<bool> _hasConnectivity() async {
    const hosts = ['google.com', 'youtube.com', 'youtu.be'];
    for (final h in hosts) {
      try {
        final result = await InternetAddress.lookup(h)
            .timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Loads [source] into the ACTIVE player and starts it. [stale] is the
  /// owning load's token check: after the 30s setAudioSource await a
  /// newer tap may own the player, and playing then would blast the wrong
  /// (or a half-torn-down) source — so a superseded load throws instead.
  Future<void> _playUrl(
      MediaSource source, Song song, bool Function() stale) async {
    // If the SAME song is already playing past 5 s, absorb this load —
    // a second setSource would reset position to 0 and cause a restart.
    if (_currentSong?.id == song.id &&
        _player.playing &&
        _position.inSeconds > 5) {
      _dlog('_playUrl absorbed active playback song=${song.id} pos=${_position.inSeconds}s');
      return;
    }
    _dlog('setSource stream song=${song.id} provider=${source.provider}');
    // Streaming causes 15-20s restart loop for all providers.
    // Force download fallback for all providers.
    throw StateError('Streaming disabled, use download');

    await _player
        .setAudioSource(
          AudioSource.uri(Uri.parse(source.url),
              headers: _headersFor(source), tag: _mediaTag(song)),
        )
        .timeout(const Duration(seconds: 30));
    if (stale()) throw StateError('superseded during setAudioSource');
    // Truncation guard: refuse to START a stream whose container duration
    // is far shorter than the manifest promises (throttled range, preview
    // clip). Playing it would stop seconds in and look like a skip.
    // Unknown lengths are allowed — the guard only fires on contradiction.
    Duration? actual = _player.duration;
    if (actual == null || actual == Duration.zero) {
      actual = await _player.durationStream
          .firstWhere((d) => d != null && d > Duration.zero,
              orElse: () => null)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
    }
    // Preview guard: YouTube sometimes serves 15s previews. Reject any stream
    // with player-reported duration <60s. This forces download fallback and avoids
    // the 15s stop-and-restart loop. Metadata missing case is covered too.
    if (actual != null && actual.inSeconds > 0 && actual.inSeconds < 60) {
      throw StateError('preview/short stream (${actual.inSeconds}s) rejected');
    }
    final totalBytes = source.contentLength;
    final bps = source.bitrate;
    if (actual != null && totalBytes != null && totalBytes > 0 && bps != null && bps > 0) {
      final expectedSec = totalBytes * 8 / bps;
      if (expectedSec > 0 && actual.inSeconds < expectedSec * 0.6) {
        throw StateError(
            'truncated stream (${actual.inSeconds}s vs ~${expectedSec.round()}s expected)');
      }
    }
    await _player.play().timeout(const Duration(seconds: 15));
  }

  Future<void> _playFile(
      String path, Song song, bool Function() stale) async {
    // If the SAME song is already playing past 5 s, absorb this load.
    if (_currentSong?.id == song.id &&
        _player.playing &&
        _position.inSeconds > 5) {
      _dlog('_playFile absorbed active playback song=${song.id} pos=${_position.inSeconds}s');
      return;
    }
    _dlog('setSource file song=${song.id}');
    await _player
        .setAudioSource(AudioSource.file(path, tag: _mediaTag(song)))
        .timeout(const Duration(seconds: 30));
    if (stale()) throw StateError('superseded during setAudioSource');
    await _player.play().timeout(const Duration(seconds: 15));
  }

  /// Downloads an already-resolved [source] into the cache and returns the
  /// verified file. Uses the source's own provider first (no second
  /// manifest fetch); falls back to a fresh provider chain. The commit
  /// size check rejects truncated/preview files. Throws on failure.
  Future<File> _downloadSource(
      MediaSource source, Song song, PlaybackReport report) async {
    final tmp = _cache.stageFile(song);
    try {
      final resolver = source.provider == MediaProvider.saavn
          ? _saavn
          : _youTube;
      try {
        await resolver
            .download(source, tmp)
            .timeout(const Duration(seconds: 150));
      } catch (_) {
        // Direct download failed (expired URL, throttled itag): fresh
        // chain with new URLs before giving up.
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        final fresh = await _strategy.downloadFirstValid(
          song,
          tmp,
          report,
          budget: const Duration(seconds: 90),
        );
        if (fresh == null) throw StateError('no downloadable source');
        return await _cache.commit(song, tmp, fresh);
      }
      return await _cache.commit(song, tmp, source);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// If ExoPlayer reports playing but no audio position advances,
  /// the stream is stalled. Skip ahead instead of sitting silent.
  /// Fixed: baseline lives only here (positionStream no longer overwrites
  /// it or cancels the timer every tick). Early playback (<10s or unknown
  /// duration) re-schedules instead of disabling the watchdog forever.
  void _startStallTimer() {
    _cancelStallTimer();
    _lastStallPosition = _position;
    if (_duration.inSeconds == 0 ||
        _position < const Duration(seconds: 10)) {
      // Increase initial stall check to 60s to avoid false positive at ~15s
      _stallTimer = Timer(const Duration(seconds: 60), () {
        if (!_isPlaying) return;
        // Re-evaluate once playback has progressed; never judge a stall
        // during initial buffering.
        _startStallTimer();
      });
      return;
    }
    _stallTimer = Timer(const Duration(seconds: 60), () {
      // Avoid false positive while buffering, loading, idle, or paused.
      if (!_isPlaying ||
          _processingState == ProcessingState.buffering ||
          _processingState == ProcessingState.loading ||
          _processingState == ProcessingState.idle) {
        _startStallTimer();
        return;
      }
      final advanced =
          _position > _lastStallPosition + const Duration(seconds: 1);
      if (!advanced) {
        _recoverStall();
      } else {
        // Still advancing: keep watching with a fresh baseline.
        _stallCount = 0;
        _stallSongId = null;
        _startStallTimer();
      }
    });
  }

  /// First stalled window: the cause is usually transient (background
  /// throttling, brief network dip) and the NEXT song would stall too —
  /// so nudge the current track (re-activate session, seek, resume)
  /// instead of skipping. Second consecutive window: skip ahead — but
  /// ONLY in foreground. Background position telemetry arrives late, so
  /// a "stall" there is usually a stale reading, not dead audio: nudge
  /// again, never skip. Only genuine completion or explicit user skip
  /// advances the queue.
  void _recoverStall() {
    final cur = _currentSong;
    if (cur == null) return;
    if (_stallSongId == cur.id) {
      _stallCount++;
    } else {
      _stallSongId = cur.id;
      _stallCount = 1;
    }
    if (_stallCount >= 2 && !_appBackgrounded) {
      _stallCount = 0;
      _stallSongId = null;
      playNext();
      return;
    }
    if (_appBackgrounded) {
      // Reset the counter so background nudges never accumulate into a
      // skip; each window is judged on its own.
      _stallCount = 0;
      _stallSongId = null;
    }
    // Ownership snapshot: this nudge belongs to the current song only.
    // A user tap that lands while the nudge is queued must win — the
    // nudge aborts instead of seeking/playing the new song's source.
    final nudgeGen = _playGen;
    final nudgeId = cur.id;
    _dlog('stall nudge song=$nudgeId count=$_stallCount');
    Future.microtask(() async {
      try {
        if (!_stillCurrent(nudgeId, nudgeGen)) {
          _dlog('stall nudge aborted (stale) song=$nudgeId');
          return;
        }
        await _activateSession();
        if (!_stillCurrent(nudgeId, nudgeGen)) return;
        // Foreground position is live so re-seeking is safe. Background
        // position can be stale — seeking to it would jump the track
        // backwards, so just resume in place.
        if (!_appBackgrounded) {
          try {
            await _player
                .seek(_position)
                .timeout(const Duration(seconds: 10));
          } catch (_) {}
          if (!_stillCurrent(nudgeId, nudgeGen)) return;
        }
        if (!_stillCurrent(nudgeId, nudgeGen)) return;
        try {
          await _player.play().timeout(const Duration(seconds: 20));
        } catch (_) {
          syncPlaybackState();
        }
      } finally {
        // Reschedule only if still ours: a superseded nudge must not
        // revive a second watchdog over the new song's own timer.
        if (_stillCurrent(nudgeId, nudgeGen)) _startStallTimer();
      }
    });
  }

  void _cancelStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  /// Re-derives [_currentIndex] from [_currentSong] identity. Any drift
  /// (stale abort, queue swap underfoot) heals here instead of causing
  /// a skip to land on — and replay — the current song.
  void _resyncIndex() {
    final cur = _currentSong;
    if (cur == null || _queue.isEmpty) return;
    final at = _queue.indexWhere((s) => s.id == cur.id);
    if (at != -1) _currentIndex = at;
  }

  /// Loads [target] with bounded same-song retries on transient failures
  /// (network/timeout/offline). Without this, one background blip burns
  /// through the rest of the queue — every later song fails identically —
  /// and playback strands paused on the wrong song. Permanent format
  /// failures return false immediately so the caller can skip ahead.
  Future<bool> _playWithRetry(Song target, int index) async {
    int tries = 0;
    while (true) {
      bool ok;
      try {
        ok = await playSong(target, index: index);
      } catch (_) {
        ok = false;
      }
      if (ok) return true;
      // Superseded by a newer tap: stay silent, newer load owns audio.
      if (_currentSong?.id != target.id) return true;
      final maxTries = _appBackgrounded ? 3 : 2;
      if (!_lastLoadWasTransient || tries >= maxTries) return false;
      tries++;
      await Future.delayed(Duration(
          seconds: _appBackgrounded
              ? (tries == 1 ? 4 : tries == 2 ? 10 : 20)
              : (tries == 1 ? 2 : 5)));
      if (_currentSong?.id != target.id) return true;
    }
  }

  /// Returns true when a new song actually started. UI shows a toast
  /// on false so a failed skip is never silent.
  /// Single-flight: only one advance chain runs at a time. Concurrent
  /// triggers collapse instead of advancing twice (the random skip).
  /// [userInitiated] steals ownership from an in-flight automatic chain.
  Future<bool> playNext([int depth = 0, bool userInitiated = false]) async {
    // Small delay to let player settle before loading next track
    await Future.delayed(const Duration(milliseconds: 200));
    if (depth == 0 && !_skipGuard()) return true;
    if (depth == 0) {
      if (_advancing && !userInitiated) {
        _dlog('advance collapsed (already in flight)');
        return true;
      }
      _advancing = true;
    }
    try {
      _resyncIndex();
      if (depth > _queue.length + 1) return await _playQueueEnd();
      int? nextIndex;
      if (_shuffle &&
          _queue.length > 1 &&
          _queueOrigin != 'search' &&
          _queueOrigin != 'searchRadio') {
        // Random track other than the current one.
        do {
          nextIndex = _random.nextInt(_queue.length);
        } while (nextIndex == _currentIndex);
      } else if (_currentIndex < _queue.length - 1) {
        nextIndex = _currentIndex + 1;
      } else if (_loopMode == LoopMode.all && _queue.isNotEmpty) {
        nextIndex = 0; // repeat-all wraps to queue start.
      }
      if (nextIndex != null) {
        final target = _queue[nextIndex];
        _dlog('advance to=${target.id} idx=$nextIndex');
        if (await _playWithRetry(target, nextIndex)) {
          return true;
        }
        // Superseded by a newer tap: stay silent, newer load owns audio.
        if (_currentSong?.id != target.id) return true;
        // Permanently broken stream (or retries exhausted): skip ahead
        // instead of getting stuck.
        _currentIndex = nextIndex;
        return await playNext(depth + 1);
      }
      return await _playQueueEnd();
    } catch (_) {
      // Never crash from background queue advancement.
      return false;
    } finally {
      if (depth == 0) _advancing = false;
    }
  }

  /// Queue-end policy: never-ending queues (Quick Picks + their
  /// continuations) grow personalized continuations; search queues grow
  /// seed-based radio; playlists/albums/popular fetch related autoplay
  /// content.
  Future<bool> _playQueueEnd() async {
    if (_queueOrigin == 'quickPicks' || _queueOrigin == 'continuation') {
      return await _playContinuation();
    }
    if (_queueOrigin == 'search' || _queueOrigin == 'searchRadio') {
      return await _playSeedRadio();
    }
    if (!_autoplayOnEnd) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
    return await _autoPlay();
  }

  /// Seed-based radio for search queues: when a search queue ends, keep
  /// music going with tracks similar to the initially-tapped song. The
  /// batch is language/duration filtered, de-duplicated, and excludes
  /// queued, finished, and seed tracks. Origin becomes 'searchRadio' so
  /// the chain continues automatically after every completed track.
  /// Never throws; best-effort like all autoplay.
  Future<bool> _playSeedRadio() async {
    _resyncIndex();
    if (_currentIndex < _queue.length - 1) {
      final target = _queue[_currentIndex + 1];
      if (await _playWithRetry(target, _currentIndex + 1)) return true;
      if (_currentSong?.id != target.id) return true;
    }
    final seed = _autoplaySeed ?? _currentSong;
    if (seed == null) {
      _scheduleBackgroundRetry();
      return false;
    }
    List<Song> pool = const [];
    try {
      final vid = seed.videoId ?? seed.id;
      List<Song> cands =
          await _youtubeService.getRelatedVideos(vid, limit: 15);
      if (cands.isEmpty && seed.artist.isNotEmpty) {
        cands = await _youtubeService
            .search('${seed.artist} songs', limit: 10)
            .timeout(const Duration(seconds: 12));
      }
      if (cands.isEmpty && seed.title.isNotEmpty) {
        cands = await _youtubeService
            .search(seed.title, limit: 10)
            .timeout(const Duration(seconds: 12));
      }
      MusicLanguage lang = MusicLanguage.all;
      try {
        lang = await UserPreferences().getLanguage();
      } catch (_) {}
      pool = SongFilter.apply(cands, language: lang);
    } catch (_) {
      pool = const [];
    }
    final doneId = _currentSong?.id;
    final doneVid = _currentSong?.videoId ?? doneId;
    final seedId = seed.id;
    final seedVid = seed.videoId ?? seedId;
    final seen = <String>{};
    final batch = <Song>[];
    for (final s in pool) {
      final v = s.videoId;
      if (v == null || v.isEmpty) continue; // unplayable without a video
      if (s.title.trim().isEmpty) continue; // junk result
      if (!seen.add(v)) continue; // duplicate within this batch
      if (v == doneVid || s.id == doneId) continue; // just finished
      if (v == seedVid || s.id == seedId) continue; // the seed itself
      if (_playedIds.contains(s.id) || _playedIds.contains(v)) continue;
      if (_queue.any((q) => q.id == s.id || (q.videoId ?? q.id) == v)) {
        continue; // already queued
      }
      batch.add(s);
      if (batch.length >= 10) break;
    }
    if (batch.isEmpty) {
      // Nothing suitable: heal in background instead of sitting paused.
      _scheduleBackgroundRetry();
      return false;
    }
    _resyncIndex();
    final base = _currentIndex + 1;
    _queue = [..._queue, ...batch];
    _queueOrigin = 'searchRadio';
    notifyListeners();
    _dlog('search radio appended ${batch.length} seed=${seed.id}');
    final target = batch.first;
    if (await _playWithRetry(target, base)) return true;
    if (_currentSong?.id != target.id) return true;
    // Load failed after retries: heal in background, never sit paused.
    _scheduleBackgroundRetry();
    return false;
  }

  /// Keeps music going after the queue ends: related videos first,
  /// then songs by the same artist, then a title search. A failed
  /// autoplay restores the finished track's ended state instead of
  /// stranding playback paused on an unrelated song.
  Future<bool> _autoPlay() async {
    if (_currentSong == null) return false;
    final prevSong = _currentSong!;
    final prevQueue = List<Song>.from(_queue);
    final prevIndex = _currentIndex;
    final prevDur = _duration;
    try {
      final id = _currentSong!.videoId ?? _currentSong!.id;
      List<Song> next = await _youtubeService.getRelatedVideos(id, limit: 10);
      if (next.isEmpty && _currentSong!.artist.isNotEmpty) {
        next = await _youtubeService.search(
          '${_currentSong!.artist} songs',
          limit: 10,
        );
      }
      if (next.isEmpty) {
        next = await _youtubeService.search(_currentSong!.title, limit: 10);
      }
      // Exclude the just-finished track by BOTH id and video: a
      // related/search hit carrying the same video under a different id
      // string would otherwise replay it from 00:00 right after it ended.
      final doneId = _currentSong!.id;
      final doneVid = _currentSong!.videoId ?? doneId;
      next.removeWhere((s) =>
          s.id == doneId ||
          s.id == doneVid ||
          (s.videoId != null && s.videoId == doneVid));
      // GLOBAL rules cover autoplay/related content too. Autoplay should not be language restricted.
      try {
        next = SongFilter.apply(next, language: MusicLanguage.all);
      } catch (_) {}
      if (next.isNotEmpty) {
        _queue = next;
        _currentIndex = 0;
        if (await _playWithRetry(next.first, 0)) return true;
        // Autoplay load failed: restore the finished track so playback
        // ends normally instead of sitting paused on an unrelated song.
        _queue = prevQueue;
        _currentIndex = prevQueue.isEmpty
            ? -1
            : prevIndex.clamp(0, prevQueue.length - 1);
        _currentSong = prevSong;
        _duration = prevDur;
        _position = prevDur;
        _isPlaying = false;
        _isLoading = false;
        notifyListeners();
      }
      return false;
    } catch (_) {
      // Autoplay is best-effort, never crash playback state.
      return false;
    }
  }

  Future<bool> playPrevious() async {
    if (!_skipGuard()) return true;
    if (_queue.isEmpty) return false;
    _resyncIndex();
    int prevIndex;
    if (_currentIndex > 0) {
      prevIndex = _currentIndex - 1;
    } else if (_loopMode == LoopMode.all) {
      prevIndex = _queue.length - 1; // repeat-all wraps to queue end.
    } else {
      try {
        await seek(Duration.zero);
        return true;
      } catch (_) {
        return false;
      }
    }
    try {
      final target = _queue[prevIndex];
      final ok = await playSong(target, index: prevIndex);
      if (ok) {
        return true;
      }
      // Superseded by a newer tap: silent. Otherwise report failure.
      if (_currentSong?.id != target.id) return true;
      return false;
    } catch (_) {
      // Keep current track on failure instead of going silent.
      return false;
    }
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  /// Cycles off → all → one. Repeat-one is handled by the player itself;
  /// repeat-all is handled manually in [playNext]/[playPrevious] because
  /// the player only ever holds a single source.
  Future<void> cycleRepeatMode() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    try {
      await _player.setLoopMode(
        _loopMode == LoopMode.one ? LoopMode.one : LoopMode.off,
      );
    } catch (_) {
      // Cosmetic on failure; manual repeat logic still applies.
    }
    notifyListeners();
  }

  /// Pause is idempotent and never throws, so the Play/Pause button cannot
  /// get stuck after backgrounding. UI updates optimistically then re-syncs
  /// from the real player state.
  Future<void> pause() async {
    try {
      _cancelStallTimer();
      // Explicit user pause wins over any pending background heal.
      _cancelBackgroundRetry();
      if (!_isPlaying) {
        // Already paused: still sync in case native state drifted in background.
        syncPlaybackState();
        return;
      }
      _isPlaying = false;
      notifyListeners();
      // Bounded: a hung platform pause must not wedge the button handler.
      await _player.pause().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Ignore native errors; UI must stay responsive.
    } finally {
      syncPlaybackState();
    }
  }

  /// Resume re-activates the audio session (required after background) and
  /// never throws. Handles completed state by seeking to start.
  Future<void> resume() async {
    try {
      if (_currentSong == null) return;
      await _activateSession();
      // Do NOT seek to zero on completed state: seeking a preview/truncated
      // stream restarts playback from beginning and creates 15-20s loop.
      // Just resume from current position; if completed, just_audio will
      // restart naturally if loop mode is set.
      // Optimistic update for instant button feedback.
      _isPlaying = true;
      notifyListeners();
      _startStallTimer();
      await _player.play().timeout(const Duration(seconds: 20));
    } catch (_) {
      // Play failed (focus loss, timeout): sync reality so button stays live.
    } finally {
      syncPlaybackState();
    }
  }

  /// Re-syncs [_isPlaying]/[_processingState] from the underlying player.
  /// Call on app resume (foreground) to heal background drift where the
  /// native player paused but Dart state still said playing (or vice versa).
  void syncPlaybackState() {
    try {
      _processingState = _player.processingState;
      _isPlaying = _player.playing &&
          _player.processingState != ProcessingState.completed;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> stop() async {
    ++_playGen;
    try {
      _cancelStallTimer();
      _cancelBackgroundRetry();
      _clearPreloadState();
      _preparingContinuation = false;
      _bgRetryCount = 0;
      _recordPreviousListen(skipped: true);
      try {
        await _player.stop().timeout(const Duration(seconds: 5));
      } catch (_) {}
      _currentSong = null;
      _handlingCompletion = false;
      _retryCount = 0;
      _lastRetrySongId = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _lastNotifiedSecond = -1;
    } finally {
      notifyListeners();
    }
  }

  void setQueue(List<Song> songs, {int startIndex = 0}) {
    _queue = songs;
    _currentIndex = startIndex;
    _clearPreloadState();
    _preparingContinuation = false;
    notifyListeners();
  }

  Future<bool> downloadCurrentSong() async {
    final song = _currentSong;
    if (song == null) return false;
    return downloadCurrentSongForSong(song);
  }

  Future<bool> downloadCurrentSongForSong(Song song,
      {bool addToDownloadedPlaylist = true}) async {
    try {
      // If already cached, just record it — no network, no playback glitch.
      final cached = await _cache.getValid(song);
      if (cached != null) {
        await _storage.addDownloadedSong(song);
        if (addToDownloadedPlaylist) {
          await _storage.addSongToDownloadedPlaylist(song);
        }
        return true;
      }
      final report =
          PlaybackReport(song.title, songId: song.videoId ?? song.id);
      // Resolve once, then share the verified-download helper with
      // playback so explicit downloads validate identically.
      final source = await _strategy.resolveFirstValid(song, report);
      if (source == null) return false;
      try {
        await _downloadSource(source, song, report);
      } catch (_) {
        return false;
      }
      await _storage.addDownloadedSong(song);
      if (addToDownloadedPlaylist) {
        await _storage.addSongToDownloadedPlaylist(song);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _cancelStallTimer();
    _cancelBackgroundRetry();
    _player.dispose();
    _youtubeService.dispose();
    _youTube.dispose();
    _saavn.dispose();
    super.dispose();
  }
}