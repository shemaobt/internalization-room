import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
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

Color _borda(WidgetTester tester) => find
    .descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Container),
    )
    .evaluate()
    .where((elemento) => !_sobUmaMarca(elemento))
    .map((elemento) => (elemento.widget as Container).decoration)
    .whereType<BoxDecoration>()
    .singleWhere(
      (decoracao) => decoracao.gradient != null && decoracao.border != null,
    )
    .border!
    .top
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

    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      _borda(tester),
      const Color(0xFF89AAA3),
      reason:
          'gravando, o .cdot dela tem a borda var(--azul) '
          '(globals.css:380); o nosso era a conta azul cheia',
    );
  });

  testWidgets('cada estado do círculo veste a borda dela, nos dois temas', (
    tester,
  ) async {
    for (final (theme, telha, azul, areia) in [
      (
        AppTheme.light,
        const Color(0xFFBE4A01),
        const Color(0xFF89AAA3),
        const Color(0xFFC5C29F),
      ),
      (
        AppTheme.dark,
        const Color(0xFFD6612A),
        const Color(0xFF8FB1A9),
        const Color(0xFF6E6A57),
      ),
    ]) {
      final deAntes = {
        ('invite', VoiceState.invite, const NoHalt()): telha,
        ('speaking', VoiceState.speaking, const NoHalt()): telha,
        ('listening', VoiceState.listening, const NoHalt()): azul,
        ('thinking', VoiceState.thinking, const NoHalt()): areia,
        ('done', VoiceState.done, const NoHalt()): telha,
      };

      for (final entrada in deAntes.entries) {
        final (nome, voz, parada) = entrada.key;
        // Sem quadro nenhum depois de montar: o barro do pensando usava a respiração
        // para clarear, e um `pump` a mais mudava a cor que `_disco()` lê. O disco
        // virou um widget fixo — só a opacidade, a escala e o brilho ao redor
        // respiram —, então o quadro que `pumpWidget` desenha já é qualquer outro.
        await _pumpCirculo(tester, voz, theme, halt: parada);
        expect(
          _borda(tester),
          entrada.value,
          reason:
              'o .cdot dela troca só a borda por estado, com var(--telha), '
              'var(--azul) e o areia de base, que no escuro são D6612A, '
              '8FB1A9 e 6E6A57 (globals.css:6, :20, :376-384); em $nome o '
              'nosso pintava uma conta, azul claro até no escuro',
        );
      }

      await _pumpCirculo(tester, VoiceState.invite, theme, peerCue: true);
      expect(
        _borda(tester),
        telha,
        reason:
            'a deixa da equipe troca o glifo e nada mais: o anel continua '
            'sendo o telha do convite, nos dois temas',
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
      _borda(tester),
      const Color(0xFF89AAA3),
      reason: 'o azul da mão continua sendo o do convite',
    );

    await _pumpCirculo(tester, VoiceState.done, AppTheme.light, noteMode: true);
    expect(
      _borda(tester),
      const Color(0xFFBE4A01),
      reason:
          'no pronto a mão levantada ficava azul como no convite; o azul da '
          'Marcia está escrito só para o convite, e o pronto mantém o '
          'círculo de telha do turno ao vivo',
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
