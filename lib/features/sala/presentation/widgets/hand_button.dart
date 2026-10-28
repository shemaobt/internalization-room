import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import 'motion.dart';

class HandButton extends StatelessWidget {
  final bool noteMode;
  final bool hasUnheardReply;
  final bool playingReply;
  final String language;
  final VoidCallback onTap;

  const HandButton({
    super.key,
    required this.noteMode,
    required this.hasUnheardReply,
    required this.playingReply,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final lit = noteMode || playingReply;

    return Semantics(
      button: true,
      label: playingReply || hasUnheardReply
          ? handLabelFor('hearTheAnswer', language)
          : handLabelFor('leaveAQuestion', language),
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
                            color: colors.azul.withValues(alpha: 0.35),
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
                Positioned(top: 10, right: 10, child: _replyDot(colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyDot(SalaColors colors) {
    return Loop(
      period: const Duration(milliseconds: 2400),
      builder: (context, t) => Opacity(
        opacity: 1 - 0.25 * t,
        child: Transform.scale(
          scale: 1 + 0.35 * t,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.telha,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.9),
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
