import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

Future<void> _pumpCirculo(
  WidgetTester tester,
  VoiceState voice,
  ThemeData theme, {
  bool peerCue = false,
  bool warning = false,
  Halt halt = const NoHalt(),
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$halt-$peerCue-$warning-${theme.brightness}'),
    theme: theme,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          halt: halt,
          size: 150,
          voice: voice,
          peerCue: peerCue,
          warning: warning ? 'aviso' : null,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

/// Whether the circle drew one of the glyphs a halted state wears — the userCheck,
/// the cloudOff/serverOff, or the micOff — the mark a warning must never cover.
bool _haltedGlyph(WidgetTester tester) => tester
    .widgetList<Icon>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Icon),
      ),
    )
    .any(
      (marca) => const [
        LucideIcons.userCheck,
        LucideIcons.cloudOff,
        LucideIcons.serverOff,
        LucideIcons.micOff,
      ].contains(marca.icon),
    );

void main() {
  testWidgets('gravando a tradução, o círculo é azul', (tester) async {
    final (container, _) = await pumpToPergunta(tester);

    await tester.tap(byLabel('Traduzir este trecho de novo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(byLabel('Tocar para gravar a tradução de novo'));
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
        ('done', VoiceState.done, const NoHalt()): BeadStyles.verde,
        ('needsPerson', VoiceState.invite, const Blocking(NothingKept())):
            BeadStyles.clay(colors),
        ('offline', VoiceState.offline, const NoHalt()): BeadStyles.clay(
          colors,
        ),
        ('blocked', VoiceState.blocked, const NoHalt()): BeadStyles.clay(
          colors,
        ),
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

  testWidgets('uma parada bloqueante nunca é verde, mesmo com o aviso ligado', (
    tester,
  ) async {
    await _pumpCirculo(
      tester,
      VoiceState.invite,
      AppTheme.light,
      halt: const Blocking(NothingKept()),
      warning: true,
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
      _haltedGlyph(tester),
      isTrue,
      reason:
          'e o corpo parado continua desenhando o seu ícone — o aviso '
          'nunca chega a competir com uma parada que já está na tela',
    );
  });

  testWidgets(
    'o disco só fica verde com o veredito limpo, o aviso nunca o acende',
    (tester) async {
      const vozes = [
        ('invite', VoiceState.invite, NoHalt()),
        ('listening', VoiceState.listening, NoHalt()),
        ('speaking', VoiceState.speaking, NoHalt()),
        ('done', VoiceState.done, NoHalt()),
        ('needsPerson', VoiceState.invite, Blocking(NothingKept())),
        ('offline', VoiceState.offline, NoHalt()),
      ];

      for (final (nome, voz, parada) in vozes) {
        for (final aviso in [true, false]) {
          await _pumpCirculo(
            tester,
            voz,
            AppTheme.light,
            halt: parada,
            warning: aviso,
          );
          final verde = voz == VoiceState.done && parada is NoHalt;

          expect(
            _disco(tester) == BeadStyles.verde,
            verde,
            reason: verde
                ? '$nome é o veredito limpo, e é a única voz que '
                      'ainda acende o disco de "pronto"'
                : '$nome com aviso=$aviso não acende o disco: o aviso '
                      'deixou de ser uma cor do disco (Henok, revertendo o '
                      'PR #230)',
          );

          if (parada is Blocking || voz == VoiceState.offline) {
            expect(
              _haltedGlyph(tester),
              isTrue,
              reason:
                  '$nome sempre desenha o seu ícone, com aviso ou '
                  'sem ele',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'o microfone bloqueado também vence o aviso — a terceira parada da lista',
    (tester) async {
      await _pumpCirculo(
        tester,
        VoiceState.blocked,
        AppTheme.light,
        warning: true,
      );

      expect(
        _disco(tester),
        isNot(BeadStyles.verde),
        reason:
            '_halted lista needsPerson, offline e blocked juntos; a '
            'matriz acima só cobre os dois primeiros, e um terceiro estado '
            'parado que a lista promete e o teste não olha é onde uma '
            'reordenação futura do corpo do círculo passaria despercebida',
      );
      expect(_haltedGlyph(tester), isTrue);
    },
  );

  // Caso 6 (Emenda 1, 07/09): a deixa ao vivo da equipe ("é sua vez de falar")
  // é um sinal de turno, e o aviso é uma notícia de fundo — a deixa vence o
  // verde da mesma forma que uma voz parada vence.
  testWidgets('a deixa da equipe não some atrás de um aviso', (tester) async {
    for (final aviso in [true, false]) {
      await _pumpCirculo(
        tester,
        VoiceState.invite,
        AppTheme.light,
        peerCue: true,
        warning: aviso,
      );

      expect(
        find.byIcon(LucideIcons.users),
        findsOneWidget,
        reason:
            'aviso=$aviso: a marca da deixa ao vivo não é negociável — '
            'sumir atrás de um aviso de fundo tira da equipe o único sinal '
            'de que é a vez dela de falar',
      );
    }
  });
}
