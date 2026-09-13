import 'dart:io';
import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../services/user_prefs.dart';
import '../services/spotify_service.dart';
import '../theme/app_theme.dart';
import '../media/cache_service.dart';
import '../widgets/liquid_background.dart';
import '../build_info.dart';

/// Settings + identity. Name edit persists and reflects in header.
class ProfileScreen extends StatefulWidget {
  final String userName;
  const ProfileScreen({super.key, required this.userName});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _prefs = UserPrefs();
  final _storage = StorageService();
  String _name = '';
  String? _avatarUrl;
  int _liked = 0;
  int _playlists = 0;
  int _recent = 0;
  bool _offline = false;
  bool _notifications = true;
  bool _spotifyLinked = false;
  String? _spotifyId;

  @override
  void initState() {
    super.initState();
    _name = widget.userName;
    _loadStats();
    _loadSpotify();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Same shared avatar as the home header: standalone read with its own
  /// guard, so a corrupt stats entry can never blank the photo here
  /// while Home still shows it (or vice versa).
  bool _avatarError = false;
  Future<void> _refreshAvatar() async {
    try {
      final avatar = await _prefs.getAvatar();
      if (!mounted) return;
      if (avatar != _avatarUrl) {
        setState(() {
          _avatarUrl = avatar;
          _avatarError = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    await _refreshAvatar();
    try {
      final l = await _storage.getLikedSongs();
      final p = await _storage.getPlaylists();
      final r = await _storage.getRecentlyPlayed();
      if (!mounted) return;
      // Storage notifies on every play tick: rebuild only when something
      // actually changed so the screen never janks while music plays.
      if (l.length == _liked &&
          p.length == _playlists &&
          r.length == _recent) {
        return;
      }
      setState(() {
        _liked = l.length;
        _playlists = p.length;
        _recent = r.length;
      });
    } catch (_) {}
  }

  Future<void> _loadSpotify() async {
    try {
      final sp = SpotifyService();
      final linked = await sp.hasCredentials();
      final id = linked ? await sp.getClientId() : null;
      if (!mounted) return;
      setState(() {
        _spotifyLinked = linked;
        _spotifyId = id;
      });
    } catch (_) {}
  }

  /// Spotify Client ID/Secret editor. Keys stay on-device; no premium
  /// needed — a free app at developer.spotify.com/dashboard works.
  Future<void> _spotifyKeys() async {
    final sp = SpotifyService();
    final existing = await sp.getClientId();
    final idCtrl = TextEditingController(text: existing ?? '');
    final secretCtrl = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Spotify keys'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Free app at developer.spotify.com/dashboard → Create app. No premium needed. Keys never leave this device.',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                    hintText: 'Client ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    hintText: 'Client Secret (leave blank to keep)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'clear'),
              child: const Text('Clear',
                  style: TextStyle(color: Colors.red))),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    final id = idCtrl.text;
    final secret = secretCtrl.text;
    idCtrl.dispose();
    secretCtrl.dispose();
    if (action == 'clear') {
      await sp.clearCredentials();
      if (!mounted) return;
      setState(() {
        _spotifyLinked = false;
        _spotifyId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spotify keys removed')),
      );
      return;
    }
    if (action != 'save' || id.trim().isEmpty) return;
    if (secret.trim().isEmpty) {
      // Secret unreadable once saved: blank means keep — valid only
      // when the ID is unchanged and keys already exist.
      final unchanged = existing != null && id.trim() == existing;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(unchanged
                ? 'Spotify keys unchanged'
                : 'Client Secret required')),
      );
      return;
    }
    await sp.saveCredentials(id, secret);
    await _loadSpotify();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Spotify keys saved')),
    );
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _name);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Change name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              hintText: 'Your name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    await _prefs.setName(v);
    if (!mounted) return;
    setState(() => _name = v);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name updated. Restart to see flight again.')),
    );
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Reset name?'),
        content: const Text('You will see the setup screen again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Reset', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _prefs.clearName();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cleared. Restart app.')),
      );
    }
  }

  Future<void> _openOfflineContents() async {
    if (!mounted) return;
    final cache = CacheService();
    Future<void> refreshDialog(void Function(void Function()) setStateDialog) async {
      setStateDialog(() {});
    }

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            title: const Text('Offline Contents'),
            content: SizedBox(
              width: 360,
              height: 320,
              child: FutureBuilder<List<Playlist>>(
                future: _storage.getPlaylists(),
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  // Show any playlist with offline flags OR the system list with songs.
                  var playlists = snap.data!
                      .where((p) =>
                          p.isDownloaded ||
                          p.downloadedSongIds.isNotEmpty ||
                          (p.id == StorageService.downloadedPlaylistId &&
                              p.songs.isNotEmpty))
                      .toList();
                  if (playlists.isEmpty) {
                    return const Center(child: Text('No downloaded playlists'));
                  }
                  return ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (_, i) {
                      final p = playlists[i];
                      final isSys = p.id == StorageService.downloadedPlaylistId;
                      final offlineCount = isSys
                          ? p.songs.length
                          : p.downloadedSongIds.length;
                      return ListTile(
                        leading: const Icon(Icons.offline_bolt),
                        title: Text(p.name, maxLines: 1),
                        subtitle: Text(
                            '$offlineCount/${p.songs.length} tracks offline'),
                        trailing: IconButton(
                          icon:
                              const Icon(Icons.delete_outline, size: 18),
                          tooltip: isSys
                              ? 'Clear downloads'
                              : 'Remove offline copy (keeps playlist)',
                          onPressed: () async {
                            if (isSys) {
                              // Clear system downloads song by song to also
                              // clean global list + cache files.
                              final ids = p.songs.map((s) => s.id).toList();
                              for (final id in ids) {
                                final song = p.songs.firstWhere(
                                  (s) => s.id == id,
                                  orElse: () => p.songs.first,
                                );
                                await _storage
                                    .removeSongFromDownloadedPlaylist(id);
                                try {
                                  await cache.invalidate(song);
                                } catch (_) {}
                              }
                            } else {
                              // Preserve online playlist + songs; only clear
                              // offline flags/protection + orphaned globals.
                              final songs = List.of(p.songs);
                              await _storage.clearPlaylistDownload(p.id);
                              for (final s in songs) {
                                if (p.downloadedSongIds.contains(s.id)) {
                                  try {
                                    await cache.invalidate(s);
                                  } catch (_) {}
                                }
                              }
                            }
                            await refreshDialog(setStateDialog);
                          },
                        ),
                        onTap: () async {
                          // Re-read fresh playlist for the inner list.
                          final all = await _storage.getPlaylists();
                          final fresh = all.firstWhere(
                            (pl) => pl.id == p.id,
                            orElse: () => p,
                          );
                          if (!context.mounted) return;
                          await showDialog(
                            context: context,
                            builder: (_) => StatefulBuilder(
                              builder: (innerCtx, setInner) => AlertDialog(
                                backgroundColor: AppColors.card,
                                title: Text(fresh.name),
                                content: SizedBox(
                                  width: 300,
                                  height: 260,
                                  child: FutureBuilder<List<Playlist>>(
                                    future: _storage.getPlaylists(),
                                    builder: (c2, s2) {
                                      if (!s2.hasData) {
                                        return const SizedBox.shrink();
                                      }
                                      final cur = s2.data!.firstWhere(
                                        (pl) => pl.id == fresh.id,
                                        orElse: () => fresh,
                                      );
                                      if (cur.songs.isEmpty) {
                                        return const Center(
                                            child: Text(
                                                'No songs — offline cleared, playlist is normal again'));
                                      }
                                      return ListView.builder(
                                        itemCount: cur.songs.length,
                                        itemBuilder: (_, idx) {
                                          final s = cur.songs[idx];
                                          final curIsSys = cur.id ==
                                              StorageService
                                                  .downloadedPlaylistId;
                                          final isDl = curIsSys
                                              ? true
                                              : cur.downloadedSongIds
                                                  .contains(s.id);
                                          return ListTile(
                                            dense: true,
                                            title: Text(s.title,
                                                maxLines: 1),
                                            subtitle: Text(s.artist,
                                                maxLines: 1),
                                            trailing: isDl
                                                ? IconButton(
                                                    icon: const Icon(
                                                        Icons
                                                            .delete_outline,
                                                        size: 18),
                                                    tooltip:
                                                        'Remove download',
                                                    onPressed: () async {
                                                      if (curIsSys) {
                                                        await _storage
                                                            .removeSongFromDownloadedPlaylist(
                                                                s.id);
                                                      } else {
                                                        await _storage
                                                            .removeOfflineSongFromPlaylist(
                                                                cur.id, s.id);
                                                      }
                                                      try {
                                                        await cache
                                                            .invalidate(s);
                                                      } catch (_) {}
                                                      // Also drop from global downloaded list if orphaned.
                                                      try {
                                                        final rest =
                                                            await _storage
                                                                .getPlaylists();
                                                        final stillNeeded = rest.any(
                                                            (pl) =>
                                                                pl.downloadedSongIds
                                                                    .contains(
                                                                        s.id));
                                                        if (!stillNeeded) {
                                                          await _storage
                                                              .removeDownloadedSong(
                                                                  s.id);
                                                        }
                                                      } catch (_) {}
                                                      setInner(() {});
                                                      await refreshDialog(
                                                          setStateDialog);
                                                    },
                                                  )
                                                : const Icon(
                                                    Icons.cloud_off,
                                                    size: 18),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          await refreshDialog(setStateDialog);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    // Refresh profile stats after offline changes.
    _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final initial =
        _name.isNotEmpty ? _name.trim()[0].toUpperCase() : '?';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: 190),
              children: [
                const Text('Profile',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                GlassPanel(
                  radius: 24,
                  padding: const EdgeInsets.all(18),
                  opacity: 0.09,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 31,
                        backgroundColor: AppColors.mist,
                        backgroundImage: _avatarUrl != null
                            ? (_avatarUrl!.startsWith('http')
                                ? NetworkImage(_avatarUrl!)
                                : FileImage(File(_avatarUrl!))
                                    as ImageProvider)
                            : null,
                        onBackgroundImageError: (_, __) {
                          // Dead file / offline URL: fall back to the
                          // initial instead of a blank circle that would
                          // mismatch the home header.
                          if (mounted && !_avatarError) {
                            setState(() => _avatarError = true);
                          }
                        },
                        child: (_avatarUrl == null || _avatarError)
                            ? Text(initial,
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white))
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            Text('$_playlists playlists · $_liked liked',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft)),
                          ],
                        ),
                      ),
                      TextButton(
                          onPressed: _rename, child: const Text('Edit')),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _stat('$_recent', 'Recent'),
                    const SizedBox(width: 10),
                    _stat('$_liked', 'Liked'),
                    const SizedBox(width: 10),
                    _stat('$_playlists', 'Playlists'),
                  ],
                ),
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 20,
                  padding: EdgeInsets.zero,
                  opacity: 0.07,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Offline mode',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text('Prefer cached audio',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft)),
                        value: _offline,
                        onChanged: (v) =>
                            setState(() => _offline = v),
                      ),
                      Divider(
                          height: 1,
                          color: AppColors.line),
                      SwitchListTile(
                        title: const Text('Notifications',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text('Playback updates',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft)),
                        value: _notifications,
                        onChanged: (v) =>
                            setState(() => _notifications = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 20,
                  padding: EdgeInsets.zero,
                  opacity: 0.07,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.pets_outlined, size: 20),
                        title: const Text('Pet',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text('Not Available',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft)),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.mute),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.card,
                              title: const Text('Pet'),
                              content: const Text('Not Available'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 20,
                  padding: EdgeInsets.zero,
                  opacity: 0.07,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.music_note_outlined,
                            size: 20),
                        title: const Text('Spotify',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                            _spotifyLinked
                                ? 'Keys saved${_spotifyId != null ? ' · ${_spotifyId!.length > 6 ? '${_spotifyId!.substring(0, 6)}…' : _spotifyId}' : ''} — tap to update'
                                : 'Add keys to enable playlist clone',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft)),
                        trailing: Icon(
                            _spotifyLinked
                                ? Icons.check_circle
                                : Icons.chevron_right,
                            color: _spotifyLinked
                                ? Colors.white
                                : AppColors.mute),
                        onTap: _spotifyKeys,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassPanel(
                  radius: 20,
                  padding: EdgeInsets.zero,
                  opacity: 0.07,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.refresh, size: 20),
                        title: const Text('Reset name',
                            style: TextStyle(fontSize: 14)),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.mute),
                        onTap: _reset,
                      ),
                      Divider(
                          height: 1,
                          color: AppColors.line),
                      ListTile(
                        leading: const Icon(Icons.offline_bolt, size: 20),
                        title: const Text('Offline Contents',
                            style: TextStyle(fontSize: 14)),
                        subtitle: const Text('Manage downloaded music'),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.mute),
                        onTap: _openOfflineContents,
                      ),
                      Divider(
                          height: 1,
                          color: AppColors.line),
                      ListTile(
                        leading: const Icon(Icons.info_outline, size: 20),
                        title: const Text('About',
                            style: TextStyle(fontSize: 14)),
                        subtitle: Text(
                            'Mono · v1.0.1 · $buildStamp',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft)),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: AppColors.card,
                              title: const Text('About Atlas Music'),
                              content: const SingleChildScrollView(
                                child: Text(
                                  'Atlas Music is a music discovery app.\n\n'
                                  'What we do:\n'
                                  '• Discover songs via YouTube search with heuristic filters.\n'
                                  '• Show Popular and Recommended sections based on your listening history.\n'
                                  '• Play audio streams with ExoPlayer via youtube_explode_dart and Saavn fallback.\n\n'
                                  'How backend works:\n'
                                  '• Discovery: YouTube search + filters for official/title song, duration 60-420s, bad phrase blacklist.\n'
                                  '• Playback: MediaResolver picks YouTubeProvider or SaavnProvider, resolves streams with VisionOS client to avoid throttling.\n'
                                  '• Data: Local SharedPreferences for playlists, history, search history. No cloud account needed.\n'
                                  '• Offline: Audio cache stores recent tracks for offline replay.',
                                  style: TextStyle(color: AppColors.inkSoft),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _stat(String v, String label) {
    return Expanded(
      child: GlassPanel(
        radius: 18,
        padding: const EdgeInsets.symmetric(vertical: 14),
        opacity: 0.07,
        child: Column(
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}
