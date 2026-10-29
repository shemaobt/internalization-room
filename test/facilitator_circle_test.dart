import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool peerCue = false,
  bool noteMode = false,
  bool inPlace = false,
  bool canvas = false,
  double edgeWidth = 1.5,
  Halt halt = const NoHalt(),
}) => tester.pumpWidget(
  MaterialApp(
    key: inPlace
        ? const ValueKey('o mesmo círculo')
        : ValueKey('$voice-$halt-$peerCue-$noteMode-$canvas'),
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          halt: halt,
          size: 158,
          voice: voice,
          peerCue: peerCue,
          noteMode: noteMode,
          canvas: canvas,
          edgeWidth: edgeWidth,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

List<CircleGlyph> _glyphs(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<CircleGlyphPainter>()
    .map((mark) => mark.glyph)
    .toList();

Future<void> _pumpStillCircle(
  WidgetTester tester,
  VoiceState voice, {
  bool inPlace = false,
  bool canvas = false,
  Halt halt = const NoHalt(),
}) => tester.pumpWidget(
  MaterialApp(
    key: inPlace
        ? const ValueKey('o mesmo círculo parado')
        : ValueKey('parado-$voice-$halt-$canvas'),
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        body: Center(
          child: FacilitatorCircle(
            halt: halt,
            size: 158,
            voice: voice,
            canvas: canvas,
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
    if (breath.animate) breath.period,
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
      for (final (name, voice, halt) in [
        ('invite', VoiceState.invite, const NoHalt()),
        ('done', VoiceState.done, const NoHalt()),
        ('listening', VoiceState.listening, const NoHalt()),
        ('speaking', VoiceState.speaking, const NoHalt()),
        ('needsPerson', VoiceState.invite, const Blocking()),
      ]) {
        await _pumpStillCircle(tester, voice, halt: halt);
        final drawn = await _overAMinuteOfFrames(tester);

        expect(
          drawn.scales.length,
          lessThan(2),
          reason:
              'nada na sala lia a preferência de movimento reduzido, e '
              '$name respirava, pulsava e jogava anéis para fora do '
              'mesmo jeito para quem desliga animações justamente porque esse '
              'movimento the faz mal',
        );
      }
    },
  );

  testWidgets(
    'the long wait on her canvas keeps one slow breath of light, and still '
    'does not move',
    (tester) async {
      await _pumpStillCircle(tester, VoiceState.thinking, canvas: true);
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
      await _pumpCircle(tester, VoiceState.thinking);
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

  testWidgets('the circle at done breathes at the pace of the inviting one', (
    tester,
  ) async {
    await _pumpCircle(tester, VoiceState.invite);
    final convite = _periods(tester);
    expect(convite, isNotEmpty);

    await _pumpCircle(tester, VoiceState.done);
    final drawn = await _overAMinuteOfFrames(tester);

    expect(
      _periods(tester),
      convite,
      reason:
          'o pronto da Marcia reaproveita a respiração do convite; um disco '
          'parado de telha no lugar do verde ainda diria à equipe que a '
          'sala terminou',
    );
    expect(
      drawn.scales.length,
      greaterThan(1),
      reason: 'e respirar é mudar de tamanho, não só ter um relógio montado',
    );
  });

  testWidgets('the room moves at her tempos, not at twice her speed', (
    tester,
  ) async {
    const tempos = {
      VoiceState.listening: Duration(milliseconds: 3000),
      VoiceState.thinking: Duration(milliseconds: 4500),
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
        VoiceState.thinking: Duration(milliseconds: 2250),
        VoiceState.speaking: Duration(milliseconds: 1700),
      };
      const peaks = {VoiceState.thinking: 1.03, VoiceState.speaking: 1.03};
      const rests = {VoiceState.thinking: 0.97, VoiceState.speaking: 0.97};

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
    'on the conversation her loudspeaker sits in the circle in voice time, '
    'and nothing while the voice thinks',
    (tester) async {
      for (final (name, voice, peerCue, noteMode, halt, glyphs) in [
        (
          'invite',
          VoiceState.invite,
          false,
          false,
          const NoHalt(),
          [CircleGlyph.sound],
        ),
        (
          'listening',
          VoiceState.listening,
          false,
          false,
          const NoHalt(),
          [CircleGlyph.sound],
        ),
        (
          'speaking',
          VoiceState.speaking,
          false,
          false,
          const NoHalt(),
          [CircleGlyph.sound],
        ),
        (
          'done',
          VoiceState.done,
          false,
          false,
          const NoHalt(),
          [CircleGlyph.sound],
        ),
        (
          'thinking',
          VoiceState.thinking,
          false,
          false,
          const NoHalt(),
          <CircleGlyph>[],
        ),
        (
          'team talk',
          VoiceState.invite,
          true,
          false,
          const NoHalt(),
          [CircleGlyph.team],
        ),
        (
          'note',
          VoiceState.listening,
          false,
          true,
          const NoHalt(),
          [CircleGlyph.hand],
        ),
        (
          'halted',
          VoiceState.invite,
          false,
          false,
          const Blocking(),
          <CircleGlyph>[],
        ),
      ]) {
        await _pumpCircle(
          tester,
          voice,
          peerCue: peerCue,
          noteMode: noteMode,
          halt: halt,
          canvas: true,
        );
        expect(
          _glyphs(tester),
          glyphs,
          reason:
              '$name: o círculo dela desenha o som enquanto a voz fala ou '
              'ouve, e no turno parado fora da conversa da equipe; nada '
              'enquanto pensa (page.tsx:485-489, :1033)',
        );
      }
    },
  );

  testWidgets('off her canvas, the room\'s own voices draw no mark', (
    tester,
  ) async {
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
            'os círculos de checagem dela não desenham glifo nenhum '
            '(Drafting.tsx:2405, Rehearsal.tsx:903, ExternalCheck.tsx:426); '
            'fora do canvas, ${voice.name} se diz pela cor e pela respiração',
      );
    }
  });

  testWidgets(
    'a question being left to a person shows the hand, never the sound of a voice',
    (tester) async {
      await _pumpCircle(
        tester,
        VoiceState.listening,
        noteMode: true,
        canvas: true,
      );

      expect(
        _glyphs(tester),
        [CircleGlyph.hand],
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
        canvas: true,
      );
      expect(_glyphs(tester), [
        CircleGlyph.hand,
      ], reason: 'o caso precisa começar na marca que vai sair');

      await _pumpCircle(
        tester,
        VoiceState.invite,
        peerCue: true,
        inPlace: true,
        canvas: true,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        _glyphs(tester),
        containsAll(const [CircleGlyph.hand, CircleGlyph.team]),
        reason:
            'meio segundo depois da deixa as duas marcas ainda dividem o '
            'disco: um corte seco no meio de uma tela sem palavra nenhuma é '
            'exatamente o piscar que a sala não pode ter',
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        _glyphs(tester),
        [CircleGlyph.team],
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
        tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(FacilitatorCircle),
                matching: find.byType(Container),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .single
            .border!
            .top
            .color,
        const Color(0xFFBE4A01),
        reason:
            'a sala mandava a equipe conversar entre si e apagava, nesse '
            'mesmo instante, o único alvo que ela aprendeu a tocar — o disco '
            'inteiro virava azul e a telha sumia justo quando ela precisa '
            'achar o círculo de volta',
      );
      await _pumpCircle(tester, VoiceState.invite, peerCue: true, canvas: true);
      expect(
        _glyphs(tester),
        [CircleGlyph.team],
        reason:
            'e quem diz que a vez é deles é o glifo, que é a única coisa '
            'que tem de mudar',
      );
    },
  );

  testWidgets(
    'a peer cue at done shows the team glyph as it does at the invite',
    (tester) async {
      await _pumpCircle(tester, VoiceState.done, peerCue: true, canvas: true);

      expect(
        _glyphs(tester),
        [CircleGlyph.team],
        reason:
            'a Marcia desenha o glifo da equipe em todo turno ocioso, e o '
            'pronto é um deles; a deixa chegava junto com o pronto e o '
            'círculo ficava sem dizer que a vez era da equipe',
      );
    },
  );

  testWidgets(
    'a circle that changes voice under less motion is as still as one that opened there',
    (tester) async {
      await _pumpStillCircle(
        tester,
        VoiceState.thinking,
        inPlace: true,
        canvas: true,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpStillCircle(
        tester,
        VoiceState.invite,
        inPlace: true,
        canvas: true,
      );
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

      await _pumpStillCircle(
        tester,
        VoiceState.thinking,
        inPlace: true,
        canvas: true,
      );
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

  for (final canvas in [false, true]) {
    testWidgets(
      'a circle given a 2.2 edge draws its ring at 2.2 ${canvas ? 'on her canvas' : 'off her canvas'}, never a silent 1.5',
      (tester) async {
        for (final voice in VoiceState.values) {
          await _pumpCircle(tester, voice, canvas: canvas, edgeWidth: 2.2);
          await tester.pump(const Duration(milliseconds: 1500));
          final rings = tester
              .widgetList<Container>(
                find.descendant(
                  of: find.byType(FacilitatorCircle),
                  matching: find.byType(Container),
                ),
              )
              .map((box) => box.decoration)
              .whereType<BoxDecoration>()
              .where((paint) => paint.border != null && paint.gradient != null);

          expect(rings, isNotEmpty, reason: '$voice');
          expect(
            rings.map((ring) => ring.border!.top.width),
            everyElement(2.2),
            reason:
                'a borda pedida só chegava ao anel da checagem; o da tela '
                'dela desenhava 1,5 em silêncio ($voice)',
          );
        }
      },
    );
  }
}
