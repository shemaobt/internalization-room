import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

const _aviso = 'Alguém deve vir olhar';

Future<void> _pumpCircle(
  WidgetTester tester,
  VoiceState voice, {
  Tongue? tongue,
  String? warning,
}) => tester.pumpWidget(
  MaterialApp(
    key: ValueKey('$voice-$tongue-$warning'),
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          size: 158,
          voice: voice,
          tongue: tongue,
          warning: warning,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

Iterable<Gradient> _gradients(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FacilitatorCircle),
        matching: find.byType(Container),
      ),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .map((paint) => paint.gradient)
    .whereType<Gradient>();

void main() {
  testWidgets('a warning does not paint over the wood of the mother tongue', (
    tester,
  ) async {
    await _pumpCircle(
      tester,
      VoiceState.speaking,
      tongue: Tongue.motherTongue,
      warning: _aviso,
    );

    expect(
      _gradients(tester),
      contains(BeadStyles.wood),
      reason:
          'o verde do aviso cobria a voz de quem soava, e a equipe perdia '
          'a única coisa que dizia qual língua estava tocando',
    );
  });

  testWidgets('a warning does not paint over the azul of the bridge language', (
    tester,
  ) async {
    await _pumpCircle(
      tester,
      VoiceState.speaking,
      tongue: Tongue.bridge,
      warning: _aviso,
    );

    expect(_gradients(tester), contains(BeadStyles.azul));
  });

  testWidgets(
    'the warning shows beside the circle, as a mark of its own on the '
    'semantics tree — never merged into the circle button',
    (tester) async {
      final handle = tester.ensureSemantics();

      for (final voice in [
        VoiceState.invite,
        VoiceState.listening,
        VoiceState.thinking,
        VoiceState.speaking,
        VoiceState.done,
      ]) {
        await _pumpCircle(tester, voice, warning: _aviso);
        expect(
          find.bySemanticsLabel(_aviso),
          findsOneWidget,
          reason:
              'a sala não tem texto (glossário): sem um nó de semântica '
              'próprio, um leitor de tela ouviria só "circulo" e o aviso de '
              '${voice.name} nunca chegaria a ser dito',
        );
        expect(
          find.bySemanticsLabel('circulo\n$_aviso'),
          findsNothing,
          reason:
              'o rótulo do aviso fundido dentro do botão do círculo é o '
              'mesmo bug que a marca deveria corrigir: um único nó lido como '
              '"circulo, AVISO" continua sem dizer que há dois avisos',
        );
      }
      handle.dispose();
    },
  );

  testWidgets('a room already halted does not also wear the warning mark', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    for (final voice in [
      VoiceState.needsPerson,
      VoiceState.offline,
      VoiceState.blocked,
    ]) {
      await _pumpCircle(tester, voice, warning: _aviso);
      expect(
        find.bySemanticsLabel(_aviso),
        findsNothing,
        reason:
            'um aviso é menor que qualquer parada; ${voice.name} já diz que '
            'a equipe deve esperar, e o aviso não soma nada a isso',
      );
    }
    handle.dispose();
  });

  testWidgets('no warning, no mark', (tester) async {
    final handle = tester.ensureSemantics();

    await _pumpCircle(tester, VoiceState.invite, warning: null);
    expect(find.bySemanticsLabel(_aviso), findsNothing);
    handle.dispose();
  });
}
