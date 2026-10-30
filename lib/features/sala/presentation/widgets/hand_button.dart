import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import 'circle_glyph.dart';
import 'motion.dart';

class HandButton extends StatelessWidget {
  final bool visible;
  final bool noteMode;
  final bool hasUnheardReply;
  final bool playingReply;
  final String language;
  final VoidCallback onTap;

  const HandButton({
    super.key,
    required this.visible,
    required this.noteMode,
    required this.hasUnheardReply,
    required this.playingReply,
    required this.language,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);

    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: Semantics(
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
                child: HerFade(
                  opacity: !visible
                      ? 0
                      : noteMode
                      ? 0.8
                      : 0.35,
                  span: const Duration(milliseconds: 1200),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: const Size.square(26),
                          painter: CircleGlyphPainter(
                            glyph: CircleGlyph.hand,
                            ink: colors.verde,
                          ),
                        ),
                        if (hasUnheardReply)
                          Positioned(
                            top: 1,
                            right: 1,
                            child: _replyDot(colors),
                          ),
                      ],
                    ),
                  ),
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
      animate: visible,
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
