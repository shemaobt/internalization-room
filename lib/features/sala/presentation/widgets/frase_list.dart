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
  final VoidCallback? onRetell;
  final String? mark;
  final bool nuance;
  final String? regravar;
  final bool regravarDormindo;
  final VoidCallback? onRegravar;
  final FraseRevisao? revisao;
  final String? estado;
  final bool estadoDormindo;
  final VoidCallback? onEstado;

  const FraseRow({
    required this.n,
    required this.parte,
    required this.share,
    required this.onHear,
    this.onRetell,
    this.mark,
    this.nuance = false,
    this.regravar,
    this.regravarDormindo = false,
    this.onRegravar,
    this.revisao,
    this.estado,
    this.estadoDormindo = false,
    this.onEstado,
  });
}

class FraseRevisao {
  final String ouvir;
  final bool tocando;
  final VoidCallback onOuvir;
  final String gravarDeNovo;
  final VoidCallback onGravarDeNovo;
  final String usarEsta;
  final VoidCallback onUsarEsta;

  const FraseRevisao({
    required this.ouvir,
    required this.tocando,
    required this.onOuvir,
    required this.gravarDeNovo,
    required this.onGravarDeNovo,
    required this.usarEsta,
    required this.onUsarEsta,
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
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: switch (row.n) {
                    final n? => Semantics(
                      button: true,
                      enabled: row.onRetell != null,
                      label: sceneRehearsalLabelFor(
                        'retellFrase',
                        language,
                        n: n,
                      ),
                      child: GestureDetector(
                        onTap: row.onRetell,
                        child: _FraseTile(row: row, language: language),
                      ),
                    ),
                    null => _FraseTile(row: row, language: language),
                  },
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
          if (row.revisao case final revisao?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RoundActionButton(
                    size: 48,
                    semanticLabel: revisao.ouvir,
                    toggled: revisao.tocando,
                    background: colors.card,
                    border: Border.all(color: colors.line),
                    onTap: revisao.onOuvir,
                    child: Icon(
                      revisao.tocando ? LucideIcons.square : LucideIcons.play,
                      size: 20,
                      color: colors.cord,
                    ),
                  ),
                  _Pill(
                    label: revisao.gravarDeNovo,
                    onTap: revisao.onGravarDeNovo,
                  ),
                  _Pill(label: revisao.usarEsta, onTap: revisao.onUsarEsta),
                ],
              ),
            ),
          if (row.estado case final estado?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: row.onEstado == null
                  ? Text(
                      estado,
                      style: TextStyle(color: colors.mut, fontSize: 14),
                    )
                  : _Pill(
                      label: estado,
                      onTap: row.onEstado,
                      dormindo: row.estadoDormindo,
                    ),
            ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dormindo;

  const _Pill({
    required this.label,
    required this.onTap,
    this.dormindo = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null && !dormindo,
      label: label,
      child: Opacity(
        opacity: onTap == null
            ? 0.35
            : dormindo
            ? 0.4
            : 1,
        child: GestureDetector(
          onTap: onTap ?? () {},
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.mut),
              ),
              child: Text(
                label,
                style: TextStyle(color: colors.mut, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
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
                        _Pill(
                          label: regravar,
                          onTap: row.onRegravar,
                          dormindo: row.regravarDormindo,
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
