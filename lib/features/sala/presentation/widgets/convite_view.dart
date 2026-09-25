import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';

class ConviteView extends ConsumerWidget {
  const ConviteView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FacilitatorCircle(
          size: 196,
          voice: session.voice,
          reach: session.reach,
          beckon: session.awaitingFirstTouch,
          semanticLabel: switch (session) {
            _ when session.needsPerson => 'Um momento para uma pessoa',
            _ => 'Falar com o facilitador',
          },
          onTap: notifier.conviteTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
        ),
        const SizedBox(height: 52),
        SizedBox(
          height: 78,
          child: session.entradaOffered
              ? _Entrada(
                  live: session.entradaLive,
                  onTap: notifier.abrirEscolha,
                )
              : null,
        ),
      ],
    );
  }
}

class _Entrada extends ConsumerStatefulWidget {
  final bool live;
  final VoidCallback onTap;

  const _Entrada({required this.live, required this.onTap});

  @override
  ConsumerState<_Entrada> createState() => _EntradaState();
}

class _EntradaState extends ConsumerState<_Entrada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: ref.read(entradaSettleProvider),
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener((_) => setState(() {}));
    if (widget.live) _settle.forward();
  }

  @override
  void didUpdateWidget(_Entrada old) {
    super.didUpdateWidget(old);
    if (!widget.live) {
      _settle.reset();
    } else if (!old.live) {
      _settle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RoundActionButton(
    mood: widget.live && _settle.isCompleted
        ? ButtonMood.beckoning
        : ButtonMood.dimmed,
    size: 78,
    gradient: BeadStyles.wood,
    halo: ShemaBrand.wood,
    border: Border.all(color: SalaColors.of(context).cord, width: 2),
    semanticLabel: 'Entrar na passagem',
    onTap: widget.onTap,
  );
}
