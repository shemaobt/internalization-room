import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import 'shema_mark.dart';

class PersonSign extends ConsumerWidget {
  const PersonSign({super.key});

  static const _wash = Color.fromRGBO(137, 170, 163, .16);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      salaSessionProvider.select((session) => session.needsPerson),
    );
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 1600),
          curve: Curves.ease,
          child: Semantics(
            button: shown,
            label: shown
                ? circleLabelFor('needsPerson', ref.watch(roomLanguageProvider))
                : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: ref.read(salaSessionProvider.notifier).teamTapped,
              child: const ColoredBox(
                color: _wash,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShemaMark(size: 76, opacity: 0.8),
                    SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_Figure(), SizedBox(width: 14), _Figure()],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure();

  static const _line = BorderSide(color: ShemaBrand.verde, width: 1.4);

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border.fromBorderSide(_line),
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(17, 20.4),
                  bottom: Radius.elliptical(17, 13.6),
                ),
              ),
            ),
            Positioned(
              top: _line.width - 9,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(_line),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
