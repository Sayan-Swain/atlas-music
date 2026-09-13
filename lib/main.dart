import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/audio_service.dart';
import 'services/youtube_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Foreground-service setup: keeps audio alive in background / screen-off.
  // Notification-panel miniplayer display will be fixed separately later.
  await JustAudioBackground.init(
    androidNotificationChannelId:
        'com.atlas.music.atlas_music.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationChannelDescription: 'Media playback controls and info',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
    androidShowNotificationBadge: false,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0E0E12),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioPlayerService()),
        Provider(create: (_) => YouTubeService()),
      ],
      child: const AtlasMusicApp(),
    ),
  );
}
