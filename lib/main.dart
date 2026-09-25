import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/audio/room_audio_session.dart';
import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'features/sala/presentation/sala_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A `.env` that will not load, or one missing a value, is a broken build — and the
  // failure has to reach the room rather than the console. `Env`'s own throw is an
  // `Error`, which every catch between the network layer and the screen misses, so a
  // missing key used to loop the invite between offline and touch-me forever against a
  // healthy server. The room asks for a person instead, which is the one halted state
  // with a glyph, a spoken line and a way out.
  var built = true;
  try {
    await Env.load();
    built = Env.complete;
  } on Object {
    built = false;
  }
  await configureRoomAudio();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(ProviderScope(child: SalaApp(built: built)));
}

class SalaApp extends StatelessWidget {
  final bool built;

  const SalaApp({super.key, this.built = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Internalization Room',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => _LessMotion(child: child!),
      home: SalaScreen(built: built),
    );
  }
}

class _LessMotion extends StatefulWidget {
  final Widget child;

  const _LessMotion({required this.child});

  @override
  State<_LessMotion> createState() => _LessMotionState();
}

class _LessMotionState extends State<_LessMotion> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduced = View.of(
      context,
    ).platformDispatcher.accessibilityFeatures.reduceMotion;
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || reduced,
      ),
      child: widget.child,
    );
  }
}
