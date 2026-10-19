import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';

class FraseRow {
  final int? n;
  final int? parte;
  final double share;
  final VoidCallback? onHear;
  final String? mark;
  final bool nuance;
  final String? regravar;
  final VoidCallback? onRegravar;

  const FraseRow({
    required this.n,
    required this.parte,
    required this.share,
    required this.onHear,
    this.mark,
    this.nuance = false,
    this.regravar,
    this.onRegravar,
  });
}

class FraseList extends StatelessWidget {
  final List<FraseRow> rows;
  final String language;

  const FraseList({super.key, required this.rows, required this.language});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = SalaColors.of(context);
    final heading = sceneRehearsalLabelFor('frases', language);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          label: heading,
          child: ExcludeSemantics(
            child: Text(
              heading.toUpperCase(),
              style: TextStyle(
                color: colors.mut,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _FraseTile(row: row, language: language),
                ),
                if (row.n case final n?) ...[
                  const SizedBox(width: 12),
                  RoundActionButton(
                    size: 48,
                    semanticLabel: sceneRehearsalLabelFor(
                      'hearMine',
                      language,
                      n: n,
                    ),
                    background: colors.card,
                    border: Border.all(color: colors.line),
                    mood: row.onHear == null
                        ? ButtonMood.dimmed
                        : ButtonMood.lit,
                    onTap: () => row.onHear?.call(),
                    child: Icon(
                      LucideIcons.volume2,
                      size: 20,
                      color: colors.cord,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FraseTile extends StatelessWidget {
  final FraseRow row;
  final String language;

  const _FraseTile({required this.row, required this.language});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final n = row.n;
    final parte = row.parte;
    final mark = row.mark;
    final tom = row.nuance
        ? ShemaBrand.azul
        : mark == null
        ? colors.cord
        : colors.telha;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: row.nuance
                ? ShemaBrand.azul
                : mark == null
                ? colors.line
                : colors.telha,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: n == null
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.mut,
                      ),
                      child: Center(
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: colors.paper,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 28,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Bar(share: row.share, fill: tom),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (parte != null)
                        Text(
                          '${retroLabelFor('part', language)} $parte',
                          style: TextStyle(color: colors.mut, fontSize: 14),
                        ),
                      if (mark != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colors.telha),
                          ),
                          child: Text(
                            mark,
                            style: TextStyle(color: colors.telha, fontSize: 14),
                          ),
                        ),
                      if (row.regravar case final regravar?)
                        Semantics(
                          button: true,
                          enabled: row.onRegravar != null,
                          label: regravar,
                          child: Opacity(
                            opacity: row.onRegravar == null ? 0.35 : 1,
                            child: GestureDetector(
                              onTap: row.onRegravar,
                              child: ExcludeSemantics(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: colors.cord),
                                  ),
                                  child: Text(
                                    regravar,
                                    style: TextStyle(
                                      color: colors.cord,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double share;
  final Color fill;

  const _Bar({required this.share, required this.fill});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: colors.line,
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: share,
        child: Container(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}
