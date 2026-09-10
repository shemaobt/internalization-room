import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

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

void main() {
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
