import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

class HandButton extends StatelessWidget {
  final bool noteMode;
  final bool hasUnheardReply;
  final bool playingReply;
  final VoidCallback onTap;

  const HandButton({
    super.key,
    required this.noteMode,
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
      label: switch ((playingReply, hasUnheardReply, noteMode)) {
        (true, _, _) => 'O facilitador está respondendo',
        (_, true, _) => 'Ouvir a resposta do facilitador',
        (_, _, true) => 'Cancelar a pergunta',
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
}
