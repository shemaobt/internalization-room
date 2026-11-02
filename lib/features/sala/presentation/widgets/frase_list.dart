import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/bt_finding.dart';
import '../../domain/facilitator_script.dart';
import 'bead_styles.dart';
import 'dashed_edge.dart';
import 'listen_glyph.dart';

class FraseRow {
  final int? n;
  final int? parte;
  final double share;
  final VoidCallback? onHear;
  final VoidCallback? onRetell;
  final String? mark;
  final BtFindingKind? achado;
  final bool aguardando;
  final bool regravada;
  final bool traduzindoDeNovo;
  final bool regravando;
  final String? regravar;
  final bool regravarDormindo;
  final bool regravarArmado;
  final VoidCallback? onRegravar;
  final VoidCallback? onRegravarFocusLeft;
  final FraseRevisao? revisao;
  final String? estado;
  final bool estadoDormindo;
  final bool estadoArmado;
  final VoidCallback? onEstado;
  final VoidCallback? onEstadoFocusLeft;

  const FraseRow({
    required this.n,
    required this.parte,
    required this.share,
    required this.onHear,
    this.onRetell,
    this.mark,
    this.achado,
    this.aguardando = false,
    this.regravada = false,
    this.traduzindoDeNovo = false,
    this.regravando = false,
    this.regravar,
    this.regravarDormindo = false,
    this.regravarArmado = false,
    this.onRegravar,
    this.onRegravarFocusLeft,
    this.revisao,
    this.estado,
    this.estadoDormindo = false,
    this.estadoArmado = false,
    this.onEstado,
    this.onEstadoFocusLeft,
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
                    child: CustomPaint(
                      size: const Size.square(20),
                      painter: ListenGlyphPainter(
                        glyph: revisao.tocando
                            ? ListenGlyph.stop
                            : ListenGlyph.play,
                        ink: colors.verde,
                      ),
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
              child: row.regravando
                  ? Semantics(
                      liveRegion: true,
                      child: Text(
                        estado,
                        style: TextStyle(color: colors.mut, fontSize: 14),
                      ),
                    )
                  : _Pill(
                      label: estado,
                      onTap: row.onEstado,
                      dormindo: row.estadoDormindo,
                      toggled: row.estadoArmado ? true : null,
                      semEsmaecer: true,
                      onFocusLeft: row.onEstadoFocusLeft,
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
  final bool? toggled;
  final bool semEsmaecer;
  final VoidCallback? onFocusLeft;

  const _Pill({
    required this.label,
    required this.onTap,
    this.dormindo = false,
    this.toggled,
    this.semEsmaecer = false,
    this.onFocusLeft,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null && !dormindo,
      toggled: toggled,
      label: label,
      onTap: onTap,
      onDidLoseAccessibilityFocus: onFocusLeft,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null
            ? semEsmaecer
                  ? 1
                  : 0.35
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
    final azul = row.achado != null && row.achado != BtFindingKind.addition;
    final tom = row.traduzindoDeNovo
        ? colors.telha
        : azul
        ? colors.azul
        : mark == null
        ? colors.verdeClaro.withValues(alpha: .85)
        : colors.telha;
    final borda = row.regravando
        ? colors.telha
        : azul
        ? colors.azul
        : row.traduzindoDeNovo
        ? colors.telha
        : mark == null || row.regravada && row.achado == null
        ? colors.areia
        : colors.telha;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color.fromRGBO(236, 234, 220, .05)
              : const Color.fromRGBO(255, 255, 255, .4),
          borderRadius: BorderRadius.circular(16),
          border: row.regravada ? null : Border.all(color: borda),
        ),
        foregroundDecoration: row.regravada
            ? DashedEdge(color: borda, radius: 16)
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: n == null
                  ? null
                  : DecoratedBox(
                      decoration: row.regravada
                          ? DashedEdge(color: colors.areia, radius: 14)
                          : BoxDecoration(
                              shape: BoxShape.circle,
                              color: row.aguardando
                                  ? colors.telha
                                  : colors.areia,
                            ),
                      child: Center(
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: row.regravada
                                ? colors.verdeClaro
                                : !row.aguardando
                                ? colors.ink
                                : Theme.of(context).brightness ==
                                      Brightness.dark
                                ? const Color(0xFF1E1B15)
                                : ShemaBrand.branco,
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
                      child: _Bar(
                        share: row.share,
                        fill: tom,
                        listras: row.regravada && row.achado == null
                            ? colors.areia.withValues(alpha: .9)
                            : null,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (parte != null)
                        Text(
                          '${retroLabelFor('part', language)} $parte',
                          style: TextStyle(
                            color: colors.verdeClaro,
                            fontSize: 14,
                          ),
                        ),
                      if (mark != null && row.regravada)
                        Text(
                          mark,
                          style: TextStyle(color: colors.telha, fontSize: 14),
                        )
                      else if (mark != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: azul ? colors.azul : colors.telha,
                            ),
                          ),
                          child: Text(
                            mark,
                            style: TextStyle(
                              color: azul ? colors.azul : colors.telha,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      if (row.regravar case final regravar?)
                        _Pill(
                          label: regravar,
                          onTap: row.onRegravar,
                          dormindo: row.regravarDormindo,
                          toggled: row.regravando || row.regravarArmado,
                          onFocusLeft: row.onRegravarFocusLeft,
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
  final Color? listras;

  const _Bar({required this.share, required this.fill, this.listras});

  @override
  Widget build(BuildContext context) {
    final listras = this.listras;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(199, 194, 159, .28),
        borderRadius: BorderRadius.circular(5),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: share,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: listras == null ? fill : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: listras == null
              ? null
              : CustomPaint(painter: _Listras(listras), size: Size.infinite),
        ),
      ),
    );
  }
}

class _Listras extends CustomPainter {
  final Color color;

  const _Listras(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    for (var at = 0.0; at < size.width; at += 6) {
      canvas.drawRect(Rect.fromLTWH(at, 0, 3, size.height), ink);
    }
  }

  @override
  bool shouldRepaint(_Listras oldDelegate) => oldDelegate.color != color;
}
