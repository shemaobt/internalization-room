import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/channel.dart';
import '../../domain/pausa.dart';
import '../../domain/scene_rehearsal.dart';
import 'scene_strip.dart';

final class PartStripRow {
  final String label;
  final Duration? length;
  final Envelope? envelope;
  final List<SceneFrase> told;
  final List<SceneFrase> stale;
  final Duration? pausa;
  final bool playing;
  final bool now;
  final bool unheard;
  final Paused? paused;

  const PartStripRow({
    required this.label,
    this.length,
    this.envelope,
    this.told = const [],
    this.stale = const [],
    this.pausa,
    this.playing = false,
    this.now = false,
    this.unheard = false,
    this.paused,
  });
}

class PartStrips extends StatelessWidget {
  final List<PartStripRow> rows;

  const PartStrips({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Column(
          children: [
            for (final (onde, row) in rows.indexed) ...[
              if (onde > 0) const SizedBox(height: 5),
              Opacity(
                opacity: row.now ? 1 : .7,
                child: Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 92),
                      child: row.unheard
                          ? Text.rich(
                              TextSpan(
                                text: row.label,
                                children: [
                                  TextSpan(
                                    text: ' ·',
                                    style: TextStyle(color: colors.telha),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.mut, fontSize: 12),
                            )
                          : Text(
                              row.label,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.mut, fontSize: 12),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: SceneStrip.height,
                        child: switch (row.length) {
                          final length? => LayoutBuilder(
                            builder: (context, constraints) => SceneStrip(
                              envelope: row.envelope,
                              length: length,
                              frases: row.told,
                              stale: row.stale,
                              pausa: row.pausa,
                              playing: row.playing,
                              paused: row.paused,
                              width: constraints.maxWidth,
                            ),
                          ),
                          null => null,
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
