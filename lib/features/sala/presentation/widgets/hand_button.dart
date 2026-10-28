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

    return Semantics(
      button: true,
      label: playingReply || hasUnheardReply
          ? handLabelFor('hearTheAnswer', language)
          : handLabelFor('leaveAQuestion', language),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedOpacity(
              opacity: noteMode ? 0.8 : 0.35,
              duration: const Duration(milliseconds: 1200),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(LucideIcons.hand, size: 26, color: colors.verde),
                    if (hasUnheardReply && !playingReply)
                      Positioned(top: 1, right: 1, child: _replyDot(colors)),
                  ],
                ),
              ),
            ),
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
