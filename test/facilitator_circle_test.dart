import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool peerCue = false,
  bool noteMode = false,
  bool inPlace = false,
  bool turning = true,
}) => tester.pumpWidget(
  MaterialApp(
    key: inPlace
        ? const ValueKey('o mesmo círculo')
        : ValueKey('$voice-$peerCue-$noteMode'),
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          size: 158,
          voice: voice,
          peerCue: peerCue,
          noteMode: noteMode,
          turning: turning,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

Gradient? _disc(WidgetTester tester) {
  final painted = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byType(Container),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((paint) => paint.gradient)
      .whereType<Gradient>()
      .toList();
  return painted.isEmpty ? null : painted.first;
}

List<IconData> _glyphs(WidgetTester tester) => tester
    .widgetList<Icon>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Icon),
      ),
    )
    .map((mark) => mark.icon!)
    .toList();

Future<void> _pumpStillCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool inPlace = false,
}) => tester.pumpWidget(
  MaterialApp(
    key: inPlace
        ? const ValueKey('o mesmo círculo parado')
        : ValueKey('parado-$voice'),
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            size: 158,
            voice: voice,
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ),
  ),
);

Future<({Set<double> scales, Set<double> veils})> _overAMinuteOfFrames(
  WidgetTester tester,
) async {
  final scales = <double>{};
  final veils = <double>{};
  for (var frame = 0; frame < 44; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
    for (final moved in tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Transform),
      ),
    )) {
      scales.add(moved.transform.entry(0, 0));
    }
    for (final veil in tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Opacity),
      ),
    )) {
      veils.add(veil.opacity);
    }
  }
  return (scales: scales, veils: veils);
}

List<Duration> _periods(WidgetTester tester) => [
  for (final breath in tester.widgetList<Loop>(
    find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Loop),
    ),
  ))
    breath.period,
  for (final ring in tester.widgetList<Ripple>(
    find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Ripple),
    ),
  ))
    ring.period,
];

void main() {
  testWidgets(
    'a tablet that asks for less motion gets a circle that holds still',
    (tester) async {
      for (final voice in [
        VoiceState.invite,
        VoiceState.listening,
        VoiceState.speaking,
        VoiceState.needsPerson,
      ]) {
        await _pumpStillCircle(tester, voice);
        final drawn = await _overAMinuteOfFrames(tester);

        expect(
          drawn.scales.length,
          lessThan(2),
          reason:
              'nada na sala lia a preferência de movimento reduzido, e '
              '${voice.name} respirava, pulsava e jogava anéis para fora do '
              'mesmo jeito para quem desliga animações justamente porque esse '
              'movimento the faz mal',
        );
      }
    },
  );

  testWidgets(
    'the long wait keeps one slow breath of light, and still does not move',
    (tester) async {
      await _pumpStillCircle(tester, VoiceState.thinking);
      final drawn = await _overAMinuteOfFrames(tester);

      expect(
        drawn.scales.length,
        lessThan(2),
        reason: 'a espera para de crescer como todo o resto',
      );
      expect(
        drawn.veils.length,
        greaterThan(1),
        reason:
            'mas a espera é o trecho mais longo da sala e todos os olhos '
            'estão no círculo: uma tela completamente congelada ali lê como um '
            'aplicativo que morreu, então a luz continua respirando — que é a '
            'única coisa que se mexe sem mexer nada de lugar',
      );
    },
  );

  testWidgets(
    'a breath that dips below one is not mistaken for a breath that never moved',
    (tester) async {
      // turning: false freezes the arcs. Without it their own spin also reads
      // below 1, and this would pass even with a disc that never shrank.
      await _pumpCircle(tester, VoiceState.thinking, turning: false);
      final drawn = await _overAMinuteOfFrames(tester);

      expect(
        drawn.scales.any((scale) => scale < 1.0),
        isTrue,
        reason:
            'a espera desce a 0,97 a cada volta, e getMaxScaleOnAxis conta o '
            'eixo z parado em 1 como se fosse o maior — o encolhimento nunca '
            'aparecia',
      );
    },
  );

  testWidgets('the room moves at her tempos, not at twice her speed', (
    tester,
  ) async {
    const tempos = {
      VoiceState.listening: Duration(milliseconds: 3200),
      VoiceState.thinking: Duration(milliseconds: 2400),
      VoiceState.speaking: Duration(milliseconds: 3400),
    };

    for (final tempo in tempos.entries) {
      await _pumpCircle(tester, tempo.key);
      expect(
        _periods(tester),
        isNotEmpty,
        reason:
            '${tempo.key.name} precisa mesmo desenhar algo que se mexe, '
            'senão não há tempo nenhum para medir',
      );
      expect(
        _periods(tester),
        everyElement(tempo.value),
        reason:
            'tudo o que ${tempo.key.name} desenha andava perto do dobro '
            'do tempo dela, e o teste dela para qualquer animação é se '
            'aquilo desviaria o olho de alguém profundamente concentrado — '
            'com o anel numa velocidade e o disco em outra, o mais rápido é '
            'o que responde',
      );
    }
  });

  testWidgets(
    'a breath lands back where it started after her period, at its peak halfway there',
    (tester) async {
      const halves = {
        VoiceState.thinking: Duration(milliseconds: 1200),
        VoiceState.speaking: Duration(milliseconds: 1700),
      };
      const peaks = {VoiceState.thinking: 1.03, VoiceState.speaking: 1.02};
      const rests = {VoiceState.thinking: 0.97, VoiceState.speaking: 1.0};

      double scale() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(Loop),
              matching: find.byType(Transform),
            ),
          )
          .first
          .transform
          .entry(0, 0);

      for (final half in halves.entries) {
        await _pumpCircle(tester, half.key);
        await tester.pump(half.value);
        expect(
          scale(),
          closeTo(peaks[half.key]!, 1e-6),
          reason:
              '${half.key.name} respirava a meio caminho do pico na metade '
              'do período dela, não no pico — o ciclo inteiro só fecha no '
              'dobro do tempo que ela desenhou',
        );

        await tester.pump(half.value);
        expect(
          scale(),
          closeTo(rests[half.key]!, 1e-6),
          reason:
              'um período inteiro depois ${half.key.name} ainda estava '
              'subindo para o pico, em vez de já ter voltado ao ponto de '
              'partida — o dobro do tempo dela outra vez',
        );
      }
    },
  );

  testWidgets(
    'only a stop says itself with a mark; the room\'s own voices draw none',
    (tester) async {
      const marks = {
        VoiceState.needsPerson: LucideIcons.userCheck,
        VoiceState.offline: LucideIcons.cloudOff,
        VoiceState.blocked: LucideIcons.micOff,
      };

      for (final voice in marks.entries) {
        await _pumpCircle(tester, voice.key);
        expect(
          _glyphs(tester),
          [voice.value],
          reason:
              'uma parada pede algo de alguém, e ${voice.key.name} só se '
              'distinguia dos vizinhos pela cor — que é o que uma tela lida de '
              'longe perde primeiro',
        );
      }

      for (final voice in const [
        VoiceState.invite,
        VoiceState.listening,
        VoiceState.speaking,
        VoiceState.done,
        VoiceState.thinking,
      ]) {
        await _pumpCircle(tester, voice);
        expect(
          _glyphs(tester),
          isEmpty,
          reason:
              'a voz da própria sala não é um pedido: ${voice.name} se diz '
              'pela cor e pela respiração, e o alto-falante que ficou aqui um '
              'dia lia como um botão que a equipe devia apertar (João, 10/09)',
        );
      }
    },
  );

  testWidgets(
    'a question being left to a person shows the hand, never the sound of a voice',
    (tester) async {
      await _pumpCircle(tester, VoiceState.listening, noteMode: true);

      expect(
        _glyphs(tester),
        [LucideIcons.hand],
        reason:
            'o modo nota era só um disco azul, e azul é também a cor do '
            'microfone aberto: nada na tela dizia que aquela fala vai para o '
            'facilitador e não para a sala. E a pergunta só existe com o '
            'microfone aberto — pedi-la num convite mediria um degrau que a '
            'sala nunca pisa, e deixaria a escuta passar na frente da mão',
      );
    },
  );

  testWidgets(
    'a mark that replaces another crosses it slowly, and never cuts to it',
    (tester) async {
      await _pumpCircle(
        tester,
        VoiceState.listening,
        noteMode: true,
        inPlace: true,
      );
      expect(_glyphs(tester), [
        LucideIcons.hand,
      ], reason: 'o caso precisa começar na marca que vai sair');

      await _pumpCircle(
        tester,
        VoiceState.invite,
        peerCue: true,
        inPlace: true,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        _glyphs(tester),
        containsAll(const [LucideIcons.hand, LucideIcons.users]),
        reason:
            'meio segundo depois da deixa as duas marcas ainda dividem o '
            'disco: um corte seco no meio de uma tela sem palavra nenhuma é '
            'exatamente o piscar que a sala não pode ter',
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        _glyphs(tester),
        [LucideIcons.users],
        reason:
            'e um segundo depois só a nova ficou — a travessia acaba, não '
            'deixa a marca velha pendurada',
      );
    },
  );

  testWidgets(
    'a peer cue changes the glyph in the circle, never the circle itself',
    (tester) async {
      await _pumpCircle(tester, VoiceState.invite, peerCue: true);

      expect(
        _disc(tester),
        BeadStyles.telha(SalaColors.light),
        reason:
            'a sala mandava a equipe conversar entre si e apagava, nesse '
            'mesmo instante, o único alvo que ela aprendeu a tocar — o disco '
            'inteiro virava azul e a telha sumia justo quando ela precisa '
            'achar o círculo de volta',
      );
      expect(
        find.byIcon(LucideIcons.users),
        findsOneWidget,
        reason:
            'e quem diz que a vez é deles é o glifo, que é a única coisa '
            'que tem de mudar',
      );
    },
  );

  testWidgets(
    'a circle that changes voice under less motion is as still as one that opened there',
    (tester) async {
      await _pumpStillCircle(tester, VoiceState.thinking, inPlace: true);
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpStillCircle(tester, VoiceState.invite, inPlace: true);
      final depois = await _overAMinuteOfFrames(tester);

      expect(
        depois.scales.length,
        lessThan(2),
        reason:
            'a sala passa a sessão inteira trocando de voz no mesmo '
            'círculo, e nunca abre de novo numa voz — um convite que só fica '
            'parado quando a tela nasce nele é a preferência valendo no '
            'primeiro quadro da sessão e em nenhum outro',
      );

      await _pumpStillCircle(tester, VoiceState.thinking, inPlace: true);
      final voltando = await _overAMinuteOfFrames(tester);

      expect(
        voltando.veils.length,
        greaterThan(1),
        reason:
            'e a respiração de luz da espera tem de chegar quando a espera '
            'chega, que é sempre de dentro de outra voz',
      );
    },
  );
}
