import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/room_audio_session.dart';
import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'features/sala/presentation/sala_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  await configureRoomAudio();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: SalaApp()));
}

class SalaApp extends StatelessWidget {
  const SalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Internalization Room',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const SalaScreen(),
    );
  }
}
