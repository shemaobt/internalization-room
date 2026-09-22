import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

class HandButton extends StatelessWidget {
  final bool noteMode;
  final bool questionPending;
  final bool hasUnheardReply;
  final bool playingReply;
  final VoidCallback onTap;

  const HandButton({
    super.key,
    required this.noteMode,
    required this.questionPending,
    required this.hasUnheardReply,
    required this.playingReply,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final lit = noteMode || playingReply;

    return Semantics(
      button: true,
      label: switch ((
        playingReply,
        hasUnheardReply,
        noteMode,
        questionPending,
      )) {
        (true, _, _, _) => 'O facilitador está respondendo',
        (_, true, _, _) => 'Ouvir a resposta do facilitador',
        (_, _, true, _) => 'Cancelar a pergunta',
        (_, _, _, true) => 'Pergunta enviada, aguardando resposta',
        _ => 'Levantar a mão',
      },
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.card,
                  border: Border.all(color: colors.line, width: 1.5),
                  boxShadow: lit
                      ? [
                          BoxShadow(
                            color: ShemaBrand.azul.withValues(alpha: 0.35),
                            spreadRadius: 5,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  LucideIcons.hand,
                  size: 26,
                  color: lit ? ShemaBrand.azulInk : colors.mut,
                ),
              ),
              if (hasUnheardReply && !playingReply)
                Positioned(top: 10, right: 10, child: _quietDot()),
              if (questionPending && !hasUnheardReply && !playingReply)
                Positioned(top: 10, right: 10, child: _waitingDot()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quietDot() {
    return Loop(
      period: const Duration(milliseconds: 2600),
      builder: (context, t) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            ShemaBrand.areia,
            ShemaBrand.verdeClaro,
            0.35 + 0.3 * t,
          ),
        ),
      ),
    );
  }

  Widget _waitingDot() {
    return Container(
      width: 11,
      height: 11,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ShemaBrand.areia,
      ),
    );
  }
}
