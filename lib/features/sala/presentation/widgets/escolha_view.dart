import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';

class EscolhaView extends ConsumerWidget {
  const EscolhaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final podeEntrar =
        session.oferecida != null && session.voice == VoiceState.invite;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FacilitatorCircle(
          size: 196,
          voice: session.voice,
          semanticLabel: switch (session) {
            _ when session.livroInteiroFeito =>
              'Todas as passagens foram trabalhadas',
            _ when session.rodaPorLer => 'Tocar para procurar as passagens',
            _ => 'Ouvir a próxima passagem',
          },
          onTap: notifier.escolhaTap,
          onLongPress: notifier.resolveWithPerson,
        ),
        const SizedBox(height: 52),
        SizedBox(
          height: 78,
          child: podeEntrar
              ? AdvanceButton(
                  size: 78,
                  gradient: BeadStyles.wood,
                  halo: ShemaBrand.wood,
                  border: Border.all(color: colors.cord, width: 2),
                  semanticLabel: 'Entrar nesta passagem',
                  onTap: notifier.entrarNaOferecida,
                )
              : null,
        ),
        const SizedBox(height: 34),
        SizedBox(
          height: 12,
          width: 168,
          child: CustomPaint(
            painter: _RodaPainter(
              at: session.aOferecer,
              total: session.naRoda?.length ?? 0,
              color: colors.cord,
              mark: colors.telha,
            ),
          ),
        ),
      ],
    );
  }
}

/// Where the wheel is, and nothing else. Not how much of the book is done — progress lives
/// in the colar and nowhere else, so this is a position that disappears with the screen.
class _RodaPainter extends CustomPainter {
  final int at;
  final int total;
  final Color color;
  final Color mark;

  const _RodaPainter({
    required this.at,
    required this.total,
    required this.color,
    required this.mark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 1) return;
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
    final x = size.width * (at / (total - 1));
    canvas.drawCircle(Offset(x, y), 4, Paint()..color = mark);
  }

  @override
  bool shouldRepaint(_RodaPainter old) =>
      old.at != at || old.total != total || old.mark != mark;
}
