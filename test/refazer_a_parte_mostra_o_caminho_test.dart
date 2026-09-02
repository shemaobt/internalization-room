import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/onde_mora_grade.dart';

Finder bySemanticsLabelWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// A team standing in front of a finding of missing content: the room offers one gesture,
/// not a choice between two voices.
Future<void> pumpRefazerAParte(
  WidgetTester tester, {
  VoidCallback? onOuvirMaterna,
  VoidCallback? onOuvirRetro,
  VoidCallback? onRefazerAParte,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Center(
        child: RefazerAParte(
          onOuvirMaterna: onOuvirMaterna ?? () {},
          onOuvirRetro: onOuvirRetro ?? () {},
          onRefazerAParte: onRefazerAParte ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('o botão único de falta tem a estação da ponte pendurada, como o '
      'caminho longo da grade', (tester) async {
    await pumpRefazerAParte(tester);

    expect(
      bySemanticsLabelWidget(micRetroLabel),
      findsNothing,
      reason:
          'não há escolha de voz aqui — um microfone só, que percorre '
          'as duas estações',
    );
    expect(bySemanticsLabelWidget(refazerParteLabel), findsOneWidget);
    expect(
      find.byKey(const Key('estacaoPendurada')),
      findsOneWidget,
      reason:
          'a mesma estação pendurada que a grade desenha sob o '
          'microfone da voz materna, mostrando que este botão também '
          'percorre a ponte depois dela',
    );
  });

  testWidgets('o microfone do botão único não é o azul da ponte', (
    tester,
  ) async {
    await pumpRefazerAParte(tester);

    final container = tester.widget<Container>(
      find.descendant(
        of: bySemanticsLabelWidget(refazerParteLabel),
        matching: find.byType(Container),
      ),
    );
    final decoracao = container.decoration as BoxDecoration;

    expect(
      decoracao.gradient,
      BeadStyles.wood,
      reason:
          'o mesmo visual que a grade já usa para o caminho longo — '
          'quem já viu a grade reconhece o gesto',
    );
    expect(
      decoracao.gradient,
      isNot(BeadStyles.azul),
      reason:
          'azul liso é o aspecto do caminho curto, e este botão nunca '
          'grava só a ponte',
    );
  });

  testWidgets('tocar o microfone único dispara só o caminho longo, uma vez', (
    tester,
  ) async {
    var chamadas = 0;
    var outrasChamadas = 0;
    await pumpRefazerAParte(
      tester,
      onRefazerAParte: () => chamadas++,
      onOuvirMaterna: () => outrasChamadas++,
      onOuvirRetro: () => outrasChamadas++,
    );

    await tester.tap(bySemanticsLabelWidget(refazerParteLabel));
    await tester.pump();

    expect(chamadas, 1);
    expect(outrasChamadas, 0);
  });

  testWidgets('os dois players continuam no botão único', (tester) async {
    var ouviuMaterna = false;
    var ouviuRetro = false;
    await pumpRefazerAParte(
      tester,
      onOuvirMaterna: () => ouviuMaterna = true,
      onOuvirRetro: () => ouviuRetro = true,
    );

    await tester.tap(bySemanticsLabelWidget(ouvirMaternaLabel));
    await tester.pump();
    await tester.tap(bySemanticsLabelWidget(ouvirRetroLabel));
    await tester.pump();

    expect(ouviuMaterna, isTrue);
    expect(ouviuRetro, isTrue);
  });
}
