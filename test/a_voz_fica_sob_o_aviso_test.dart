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
  bool warning = false,
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
          warningLabel: _aviso,
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

Finder _warningMark() => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == _aviso,
);

void main() {
  testWidgets('a warning does not paint over the wood of the mother tongue', (
    tester,
  ) async {
    await _pumpCircle(
      tester,
      VoiceState.speaking,
      tongue: Tongue.motherTongue,
      warning: true,
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
      warning: true,
    );

    expect(_gradients(tester), contains(BeadStyles.azul));
  });

  testWidgets(
    'the warning shows beside the circle, said by its own VoiceOver label',
    (tester) async {
      for (final voice in [
        VoiceState.invite,
        VoiceState.listening,
        VoiceState.thinking,
        VoiceState.speaking,
        VoiceState.done,
      ]) {
        await _pumpCircle(tester, voice, warning: true);
        expect(
          _warningMark(),
          findsOneWidget,
          reason:
              'a sala não tem texto (glossário): sem uma marca com etiqueta '
              'própria, um aviso que chegasse em ${voice.name} não teria como '
              'ser dito',
        );
      }
    },
  );

  testWidgets('a room already halted does not also wear the warning mark', (
    tester,
  ) async {
    for (final voice in [
      VoiceState.needsPerson,
      VoiceState.offline,
      VoiceState.blocked,
    ]) {
      await _pumpCircle(tester, voice, warning: true);
      expect(
        _warningMark(),
        findsNothing,
        reason:
            'um aviso é menor que qualquer parada; ${voice.name} já diz que '
            'a equipe deve esperar, e o aviso não soma nada a isso',
      );
    }
  });

  testWidgets('no warning, no mark', (tester) async {
    await _pumpCircle(tester, VoiceState.invite, warning: false);
    expect(_warningMark(), findsNothing);
  });
}
