import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import 'shema_mark.dart';

class PersonSign extends ConsumerStatefulWidget {
  const PersonSign({super.key});

  @override
  ConsumerState<PersonSign> createState() => _PersonSignState();
}

class _PersonSignState extends ConsumerState<PersonSign>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: ref.read(salaSessionProvider).needsPerson ? 1 : 0,
  );
  late final _opacity = CurvedAnimation(parent: _fade, curve: Curves.ease);

  @override
  void dispose() {
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _tapped() {
    if (_fade.status.isForwardOrCompleted) {
      ref.read(salaSessionProvider.notifier).teamTapped();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = ref.watch(
      salaSessionProvider.select((session) => session.needsPerson),
    );
    ref.listen(
      salaSessionProvider.select((session) => session.needsPerson),
      (_, now) => now ? _fade.forward() : _fade.reverse(),
    );
    final colors = SalaColors.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !shown,
        child: FadeTransition(
          opacity: _opacity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tapped,
            child: ColoredBox(
              color: colors.personSignWash,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const ShemaMark(size: 76, opacity: 0.8),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Figure(colors.verde),
                      const SizedBox(width: 14),
                      _Figure(colors.verde),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final Color color;

  const _Figure(this.color);

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: color, width: 1.4);
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
              decoration: BoxDecoration(
                border: Border.fromBorderSide(line),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.elliptical(17, 20.4),
                  bottom: Radius.elliptical(17, 13.6),
                ),
              ),
            ),
            Positioned(
              top: line.width - 9,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(line),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
