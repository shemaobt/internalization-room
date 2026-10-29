import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/back_to_passage_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_scene_room.dart' show onTheSceneStep, theIPad, theSE;
import 'scenario_helpers.dart' show byLabel;

const _list = 'ensaios da cena desta sessão';

const _steps = [
  (name: 'record', step: SceneStep.record, scenes: <Scene>[]),
  (
    name: 'record under the question',
    step: SceneStep.record,
    scenes: [
      Scene(sceneId: 'S1', title: 'A fome em Belém'),
      Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
    ],
  ),
  (name: 'translate', step: SceneStep.translate, scenes: <Scene>[]),
  (name: 'places-unknown', step: SceneStep.placesUnknown, scenes: <Scene>[]),
  (name: 'sent', step: SceneStep.sent, scenes: <Scene>[]),
];

List<SceneFrase> _frases({required bool placed}) => [
  for (var n = 0; n < 12; n++)
    SceneFrase(
      fraseId: 'f${n + 1}',
      startsMs: n * 800,
      endsMs: n == 11 && !placed ? 12000 : (n + 1) * 800,
    ),
];

Future<ProviderContainer> _onTheStep(
  WidgetTester tester, {
  required Size screen,
  required double bar,
  required SceneStep step,
  List<Scene> scenes = const [],
  int listed = 10,
}) async {
  final opensUnsent =
      step == SceneStep.translate || step == SceneStep.placesUnknown;
  final container = await onTheSceneStep(
    tester,
    screen: screen,
    bar: bar,
    step: step,
    scenes: scenes,
    rehearsals: [
      for (var n = 1; n <= listed; n++)
        SceneRehearsalRecord(
          rehearsalId: 'ensaio-da-cena-$n',
          sessionId: 'sessao-1',
          n: n,
          sentAt: opensUnsent && n == listed
              ? null
              : '2026-10-27T10:00:00+00:00',
          frases: _frases(placed: step != SceneStep.placesUnknown),
        ),
    ],
  );
  expect(
    container.read(salaSessionProvider).sceneQuestionShown,
    scenes.length > 1,
  );
  return container;
}

final _vertical = find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down,
);

Finder _inTheScreen(Finder matching) =>
    find.descendant(of: find.byType(SceneRehearsalView), matching: matching);

void main() {
  for (final shown in _steps) {
    testWidgets(
      'on the ${shown.name} step the heading, the step and the session list '
      'scroll together as one page, not the list on its own under the step',
      (tester) async {
        await _onTheStep(
          tester,
          screen: theSE.size,
          bar: theSE.bar,
          step: shown.step,
          scenes: shown.scenes,
        );
        final page = find.ancestor(
          of: find.text('Ensaio da cena'),
          matching: _vertical,
        );

        expect(
          page,
          findsOneWidget,
          reason: 'o título ficava parado e só o passo rolava, embaixo dele',
        );
        expect(
          find.descendant(of: page, matching: byLabel(_list)),
          findsOneWidget,
          reason:
              'a lista da sessão ficava fora da página, presa embaixo do '
              'passo',
        );
      },
    );

    testWidgets(
      'on the ${shown.name} step the page is the only scroller on the '
      'screen, not one scroller inside another',
      (tester) async {
        await _onTheStep(
          tester,
          screen: theSE.size,
          bar: theSE.bar,
          step: shown.step,
          scenes: shown.scenes,
        );

        expect(
          _inTheScreen(_vertical),
          findsOneWidget,
          reason:
              'o passo de traduzir, o modo de escuta e a lista tinham cada '
              'um a sua rolagem dentro da tela',
        );
      },
    );

    testWidgets(
      'on the iPhone SE the ${shown.name} step over ten rehearsals and '
      'twelve frases overflows nothing, and the page scrolls to the last '
      'rehearsal',
      (tester) async {
        await _onTheStep(
          tester,
          screen: theSE.size,
          bar: theSE.bar,
          step: shown.step,
          scenes: shown.scenes,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'dez ensaios e doze frases estouravam a tela do SE',
        );

        await tester.drag(
          find.byType(SceneRehearsalView),
          const Offset(0, -4000),
        );
        await tester.pump(const Duration(milliseconds: 600));
        final last = tester.getRect(
          find
              .descendant(
                of: byLabel(_list),
                matching: find.byType(GestureDetector),
              )
              .last,
        );

        expect(tester.takeException(), isNull);
        expect(
          last.top >= 0 && last.bottom <= theSE.size.height,
          isTrue,
          reason:
              'o último ensaio da lista ficava escondido numa rolagem de um '
              'terço da tela: $last',
        );
      },
    );
  }

  for (final shown in [_steps[0], _steps[2]]) {
    testWidgets(
      'on the iPad the ${shown.name} step starts her .8rem under the heading, '
      'not centred in the height the heading leaves',
      (tester) async {
        await _onTheStep(
          tester,
          screen: theIPad.size,
          bar: theIPad.bar,
          step: shown.step,
          listed: 1,
        );
        final heading = tester.getRect(find.text('Ensaio da cena'));
        final lines = _inTheScreen(find.byType(Text)).evaluate().map((element) {
          final box = element.renderObject! as RenderBox;
          return box.localToGlobal(Offset.zero) & box.size;
        }).toList()..sort((a, b) => a.top.compareTo(b.top));
        final step = lines[1];

        expect(
          step.top - heading.bottom,
          closeTo(0.8 * 16, 0.01),
          reason:
              'o passo ficava no meio da altura que sobrava, longe do título',
        );
      },
    );
  }

  for (final shown in [_steps[0], _steps[2], _steps[4]]) {
    testWidgets('on the iPhone SE the way back leaves with the page on the '
        '${shown.name} step, so no line scrolls under it', (tester) async {
      await _onTheStep(
        tester,
        screen: theSE.size,
        bar: theSE.bar,
        step: shown.step,
      );
      tester
          .state<ScrollableState>(_inTheScreen(_vertical))
          .position
          .jumpTo(200);
      await tester.pump(const Duration(milliseconds: 100));
      final wayBack = tester.getRect(find.byType(BackToPassageButton));
      final covered = [
        for (final type in [Text, RoundActionButton, SceneStrip])
          for (final element in _inTheScreen(find.byType(type)).evaluate())
            if (tester
                .getRect(find.byElementPredicate((e) => e == element))
                .overlaps(wayBack))
              type,
      ];

      expect(
        wayBack.top,
        closeTo(theSE.bar + theSE.size.height * 0.05 - 2 - 200, 0.01),
        reason: 'a volta ficava parada no canto enquanto a página rolava',
      );
      expect(
        covered,
        isEmpty,
        reason: 'o círculo e as linhas passavam por baixo da volta',
      );
    });
  }
}
