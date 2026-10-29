import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _se = (name: 'the iPhone SE', size: Size(375, 667), bar: 20.0);
const _ipad = (name: 'the iPad', size: Size(820, 1180), bar: 24.0);

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

Future<void> _withRealLetters() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      File(
        '$fonts/Roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
}

Future<ProviderContainer> _onTheStep(
  WidgetTester tester, {
  required Size screen,
  required double bar,
  required SceneStep step,
  List<Scene> scenes = const [],
  int listed = 10,
}) async {
  await tester.runAsync(_withRealLetters);
  final opensUnsent =
      step == SceneStep.translate || step == SceneStep.placesUnknown;
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation
    ..room.passageScenes = scenes;
  harness.room.sceneRehearsals.addAll([
    for (var n = 1; n <= listed; n++)
      SceneRehearsalRecord(
        rehearsalId: 'ensaio-da-cena-$n',
        sessionId: 'sessao-1',
        n: n,
        sentAt: opensUnsent && n == listed ? null : '2026-10-27T10:00:00+00:00',
        frases: _frases(placed: step != SceneStep.placesUnknown),
      ),
  ]);
  harness.room.sceneAudio = aSpokenWav(length: const Duration(seconds: 10));
  harness.playback.measured = const Duration(seconds: 10);
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
  addTearDown(tester.view.reset);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.tap(byLabel('ensaio da cena'));
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).sceneRehearsals.isNotEmpty,
  );
  if (step == SceneStep.sent) {
    notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
  }
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).scene.step == step,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  expect(container.read(salaSessionProvider).scene.step, step);
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
          screen: _se.size,
          bar: _se.bar,
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
          screen: _se.size,
          bar: _se.bar,
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
          screen: _se.size,
          bar: _se.bar,
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
          last.top >= 0 && last.bottom <= _se.size.height,
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
          screen: _ipad.size,
          bar: _ipad.bar,
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
}
