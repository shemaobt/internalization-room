import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'a_pergunta_da_grade.dart' show pumpToPergunta;
import 'scenario_helpers.dart';

/// Whether [elemento] sits inside a [Positioned] child of its own
/// [FacilitatorCircle] — the warning mark's own box, never the disc's.
bool _sobUmaMarca(Element elemento) {
  var achou = false;
  elemento.visitAncestorElements((ancestral) {
    if (ancestral.widget is FacilitatorCircle) return false;
    if (ancestral.widget is Positioned) {
      achou = true;
      return false;
    }
    return true;
  });
  return achou;
}

/// The gradient the disc at the centre of the circle is painted with.
///
/// The rings around it carry borders and no gradient, so the disc is the only one, and
/// asking for exactly one is what keeps this from reading a ripple by mistake. The
/// warning mark also paints a gradient, so it is excluded by sitting under its own
/// [Positioned] box.
Gradient? _disco(WidgetTester tester) {
  final pintados = <Gradient>[
    for (final elemento
        in find
            .descendant(
              of: find.byType(FacilitatorCircle),
              matching: find.byType(Container),
            )
            .evaluate())
      if (!_sobUmaMarca(elemento))
        if ((elemento.widget as Container).decoration case BoxDecoration(
          :final gradient?,
        ))
          gradient,
  ];
  expect(
    pintados,
    hasLength(lessThan(2)),
    reason:
        'o corpo é o único desenho do círculo com gradiente; com dois '
        'este ajudante não sabe qual deles é o disco, e um StateError cru '
        'não diria isso a quem vier depois',
  );
  return pintados.isEmpty ? null : pintados.first;
}

Color _sombraDoDisco(WidgetTester tester) => find
    .descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Container),
    )
    .evaluate()
    .where((elemento) => !_sobUmaMarca(elemento))
    .map((elemento) => (elemento.widget as Container).decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoracao) => decoracao.gradient != null)
    .boxShadow!
    .first
    .color;

Future<void> _pumpCirculo(
  WidgetTester tester,
  VoiceState voice,
  ThemeData theme, {
  bool peerCue = false,
  bool noteMode = false,
  Halt halt = const NoHalt(),
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$halt-$peerCue-$noteMode-${theme.brightness}'),
    theme: theme,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          halt: halt,
          size: 150,
          voice: voice,
          peerCue: peerCue,
          noteMode: noteMode,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('gravando a tradução, o círculo é azul', (tester) async {
    final (container, _) = await pumpToPergunta(tester);

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 300));
    container.read(salaSessionProvider.notifier).retroTap();
    await tester.pump(const Duration(milliseconds: 300));

    final estado = container.read(salaSessionProvider);
    expect(estado.btPhase, BtPhase.capturing);
    expect(estado.voice, VoiceState.listening);

    expect(
      _disco(tester),
      BeadStyles.azul,
      reason:
          'esta é a metade que já estava certa: azul é a cor do contar '
          'em português, e distinguir a materna não pode custá-la',
    );
  });

  testWidgets('os outros estados do círculo ficam com as cores de antes', (
    tester,
  ) async {
    for (final tema in [
      (AppTheme.light, SalaColors.light),
      (AppTheme.dark, SalaColors.dark),
    ]) {
      final (theme, colors) = tema;
      final deAntes = {
        ('invite', VoiceState.invite, const NoHalt()): BeadStyles.telha(colors),
        ('speaking', VoiceState.speaking, const NoHalt()): BeadStyles.telha(
          colors,
        ),
        ('listening', VoiceState.listening, const NoHalt()): BeadStyles.azul,
        ('thinking', VoiceState.thinking, const NoHalt()): BeadStyles.clay(
          colors,
        ),
        ('done', VoiceState.done, const NoHalt()): BeadStyles.telha(colors),
      };

      for (final entrada in deAntes.entries) {
        final (nome, voz, parada) = entrada.key;
        // Sem quadro nenhum depois de montar: o barro do pensando usava a respiração
        // para clarear, e um `pump` a mais mudava a cor que `_disco()` lê. O disco
        // virou um widget fixo — só a opacidade, a escala e o brilho ao redor
        // respiram —, então o quadro que `pumpWidget` desenha já é qualquer outro.
        await _pumpCirculo(tester, voz, theme, halt: parada);
        expect(
          _disco(tester),
          entrada.value,
          reason:
              'um switch mexido vaza pelos ramos vizinhos, e '
              '$nome não tem nada a ver com a língua materna',
        );
      }

      await _pumpCirculo(tester, VoiceState.invite, theme, peerCue: true);
      expect(
        _disco(tester),
        BeadStyles.telha(colors),
        reason:
            'a deixa da equipe troca o glifo e nada mais: o disco '
            'continua sendo o mesmo alvo de telha do convite, nos dois '
            'temas',
      );
    }
  });

  testWidgets('a mão levantada só ganha o azul no convite, não no pronto', (
    tester,
  ) async {
    await _pumpCirculo(
      tester,
      VoiceState.invite,
      AppTheme.light,
      noteMode: true,
    );
    expect(
      _disco(tester),
      BeadStyles.azul,
      reason: 'o azul da mão continua sendo o do convite',
    );

    await _pumpCirculo(tester, VoiceState.done, AppTheme.light, noteMode: true);
    expect(
      _disco(tester),
      BeadStyles.telha(SalaColors.light),
      reason:
          'no pronto a mão levantada ficava azul como no convite; o azul da '
          'Marcia está escrito só para o convite, e o pronto mantém o '
          'círculo de telha do turno ao vivo',
    );
    expect(
      _sombraDoDisco(tester).withValues(alpha: 1),
      SalaColors.light.telha,
      reason: 'o azul da mão também vazava pela sombra do disco no pronto',
    );
  });

  testWidgets('uma parada bloqueante nunca é verde', (tester) async {
    await _pumpCirculo(
      tester,
      VoiceState.invite,
      AppTheme.light,
      halt: const Blocking(),
    );

    expect(
      _disco(tester),
      isNot(BeadStyles.verde),
      reason:
          'uma parada de verdade pede uma pessoa e recusa o gesto; um '
          'aviso de segundos atrás não desfaz isso, então o disco continua '
          'sendo o do corpo parado',
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find
                .descendant(
                  of: find.byType(FacilitatorCircle),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity,
      0,
      reason:
          'o círculo some sob o sinal da pessoa — o aviso nunca chega a '
          'competir com uma parada que já está na tela',
    );
  });

  testWidgets('nenhuma voz acende o disco verde de pronto', (tester) async {
    const vozes = [
      ('invite', VoiceState.invite, NoHalt()),
      ('listening', VoiceState.listening, NoHalt()),
      ('speaking', VoiceState.speaking, NoHalt()),
      ('done', VoiceState.done, NoHalt()),
    ];

    for (final (nome, voz, parada) in vozes) {
      await _pumpCirculo(tester, voz, AppTheme.light, halt: parada);

      expect(
        _disco(tester) == BeadStyles.verde,
        isFalse,
        reason:
            '$nome não acende o disco: a Marcia nunca desenhou um disco '
            'verde de pronto, e o aviso deixou de ser uma cor do disco '
            '(Henok, revertendo o PR #230)',
      );
    }
  });
}
