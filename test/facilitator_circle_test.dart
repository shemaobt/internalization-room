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
}) =>
    tester.pumpWidget(MaterialApp(
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
            semanticLabel: 'circulo',
            onTap: () {},
          ),
        ),
      ),
    ));

/// The fill of the disc at the centre, which is the only painting in the circle that
/// carries a gradient — the rings around it are borders on nothing.
Gradient? _disc(WidgetTester tester) {
  final painted = tester
      .widgetList<Container>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .map((paint) => paint.gradient)
      .whereType<Gradient>()
      .toList();
  return painted.isEmpty ? null : painted.first;
}

/// Every mark the circle draws inside itself, in the order it draws them.
List<IconData> _glyphs(WidgetTester tester) => tester
    .widgetList<Icon>(find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Icon),
    ))
    .map((mark) => mark.icon!)
    .toList();

Future<void> _pumpStillCircle(WidgetTester tester, VoiceState voice) =>
    tester.pumpWidget(MaterialApp(
      key: ValueKey('parado-$voice'),
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
    ));

/// Every distinct scale the circle draws over a long stretch of frames, and every
/// distinct veil of light it draws under them.
Future<({Set<double> scales, Set<double> veils})> _overAMinuteOfFrames(
  WidgetTester tester,
) async {
  final scales = <double>{};
  final veils = <double>{};
  for (var frame = 0; frame < 44; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
    for (final moved in tester.widgetList<Transform>(find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Transform),
    ))) {
      scales.add(moved.transform.getMaxScaleOnAxis());
    }
    for (final veil in tester.widgetList<Opacity>(find.descendant(
      of: find.byType(FacilitatorCircle),
      matching: find.byType(Opacity),
    ))) {
      veils.add(veil.opacity);
    }
  }
  return (scales: scales, veils: veils);
}

/// How long every moving thing the circle draws takes to go once round.
List<Duration> _periods(WidgetTester tester) => [
      for (final breath in tester.widgetList<Loop>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Loop),
      )))
        breath.period,
      for (final ring in tester.widgetList<Ripple>(find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Ripple),
      )))
        ring.period,
    ];

void main() {
  testWidgets('a tablet that asks for less motion gets a circle that holds still',
      (tester) async {
    for (final voice in [
      VoiceState.invite,
      VoiceState.listening,
      VoiceState.speaking,
      VoiceState.needsPerson,
    ]) {
      await _pumpStillCircle(tester, voice);
      final drawn = await _overAMinuteOfFrames(tester);

      expect(drawn.scales.length, lessThan(2),
          reason: 'nada na sala lia a preferência de movimento reduzido, e '
              '${voice.name} respirava, pulsava e jogava anéis para fora do '
              'mesmo jeito para quem desliga animações justamente porque esse '
              'movimento the faz mal');
    }
  });

  testWidgets('the long wait keeps one slow breath of light, and still does not move',
      (tester) async {
    await _pumpStillCircle(tester, VoiceState.thinking);
    final drawn = await _overAMinuteOfFrames(tester);

    expect(drawn.scales.length, lessThan(2),
        reason: 'a espera para de crescer como todo o resto');
    expect(drawn.veils.length, greaterThan(1),
        reason: 'mas a espera é o trecho mais longo da sala e todos os olhos '
            'estão no círculo: uma tela completamente congelada ali lê como um '
            'aplicativo que morreu, então a luz continua respirando — que é a '
            'única coisa que se mexe sem mexer nada de lugar');
  });

  testWidgets('the room moves at her tempos, not at twice her speed', (tester) async {
    const tempos = {
      VoiceState.listening: Duration(milliseconds: 3200),
      VoiceState.thinking: Duration(milliseconds: 4600),
      VoiceState.speaking: Duration(milliseconds: 3400),
    };

    for (final tempo in tempos.entries) {
      await _pumpCircle(tester, tempo.key);
      expect(_periods(tester), isNotEmpty,
          reason: '${tempo.key.name} precisa mesmo desenhar algo que se mexe, '
              'senão não há tempo nenhum para medir');
      expect(_periods(tester), everyElement(tempo.value),
          reason: 'tudo o que ${tempo.key.name} desenha andava perto do dobro '
              'do tempo dela, e o teste dela para qualquer animação é se '
              'aquilo desviaria o olho de alguém profundamente concentrado — '
              'com o anel numa velocidade e o disco em outra, o mais rápido é '
              'o que responde');
    }
  });

  testWidgets('every voice the room has says itself with a mark, and the wait says nothing',
      (tester) async {
    const marks = {
      VoiceState.invite: LucideIcons.volume2,
      VoiceState.listening: LucideIcons.volume2,
      VoiceState.speaking: LucideIcons.volume2,
      VoiceState.done: LucideIcons.volume2,
      VoiceState.needsPerson: LucideIcons.userCheck,
      VoiceState.offline: LucideIcons.cloudOff,
      VoiceState.blocked: LucideIcons.micOff,
    };

    for (final voice in marks.entries) {
      await _pumpCircle(tester, voice.key);
      expect(_glyphs(tester), [voice.value],
          reason: 'fora do modo de conversa entre a equipe o círculo não tinha '
              'símbolo nenhum, e ${voice.key.name} só se distinguia dos '
              'vizinhos pela cor — que é o que uma tela lida de longe perde '
              'primeiro');
    }

    await _pumpCircle(tester, VoiceState.thinking);
    expect(_glyphs(tester), isEmpty,
        reason: 'a espera é o único estado sem marca: nada está acontecendo '
            'que a equipe possa fazer, e um símbolo ali seria um pedido');
  });

  testWidgets('a question being left to a person shows the hand, never the sound of a voice',
      (tester) async {
    await _pumpCircle(tester, VoiceState.invite, noteMode: true);

    expect(_glyphs(tester), [LucideIcons.hand],
        reason: 'o modo nota era só um disco azul, e azul é também a cor do '
            'microfone aberto: nada na tela dizia que aquela fala vai para o '
            'facilitador e não para a sala');
  });

  testWidgets('a mark that replaces another crosses it slowly, and never cuts to it',
      (tester) async {
    await _pumpCircle(tester, VoiceState.invite, inPlace: true);
    expect(_glyphs(tester), [LucideIcons.volume2],
        reason: 'o caso precisa começar na marca que vai sair');

    await _pumpCircle(tester, VoiceState.invite, peerCue: true, inPlace: true);
    await tester.pump(const Duration(milliseconds: 500));

    expect(_glyphs(tester), containsAll(const [LucideIcons.volume2, LucideIcons.users]),
        reason: 'meio segundo depois da deixa as duas marcas ainda dividem o '
            'disco: um corte seco no meio de uma tela sem palavra nenhuma é '
            'exatamente o piscar que a sala não pode ter');

    await tester.pump(const Duration(milliseconds: 700));
    expect(_glyphs(tester), [LucideIcons.users],
        reason: 'e um segundo depois só a nova ficou — a travessia acaba, não '
            'deixa a marca velha pendurada');
  });

  testWidgets('a peer cue changes the glyph in the circle, never the circle itself',
      (tester) async {
    await _pumpCircle(tester, VoiceState.invite, peerCue: true);

    expect(_disc(tester), BeadStyles.telha(SalaColors.light),
        reason: 'a sala mandava a equipe conversar entre si e apagava, nesse '
            'mesmo instante, o único alvo que ela aprendeu a tocar — o disco '
            'inteiro virava azul e a telha sumia justo quando ela precisa '
            'achar o círculo de volta');
    expect(find.byIcon(LucideIcons.users), findsOneWidget,
        reason: 'e quem diz que a vez é deles é o glifo, que é a única coisa '
            'que tem de mudar');
  });
}
