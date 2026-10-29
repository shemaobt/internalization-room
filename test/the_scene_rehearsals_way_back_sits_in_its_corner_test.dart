import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/back_to_passage_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _se = (name: 'the iPhone SE', size: Size(375, 667), bar: 20.0);
const _ipad = (name: 'the iPad', size: Size(820, 1180), bar: 24.0);

final _frases = [
  for (var n = 0; n < 4; n++)
    SceneFrase(
      fraseId: 'f${n + 1}',
      startsMs: n * 2500,
      endsMs: (n + 1) * 2500,
    ),
];

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? sentAt,
  List<SceneFrase>? frases,
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: 'sessao-1',
  n: n,
  sentAt: sentAt,
  frases: frases ?? _frases,
);

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
  int listed = 1,
  List<Scene> scenes = const [],
}) async {
  await tester.runAsync(_withRealLetters);
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation
    ..room.passageScenes = scenes;
  harness.room.sceneRehearsals.addAll([
    for (var n = 1; n <= listed; n++)
      _rehearsal(
        n: n,
        sentAt: switch (step) {
          SceneStep.translate || SceneStep.placesUnknown => null,
          _ => '2026-10-27T10:00:00+00:00',
        },
        frases: step == SceneStep.placesUnknown
            ? const [SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 12000)]
            : null,
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
  return container;
}

Iterable<Rect> _rectsOf(Type type) => find
    .descendant(
      of: find.byType(SceneRehearsalView),
      matching: find.byType(type),
    )
    .evaluate()
    .map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    });

void main() {
  for (final device in [_se, _ipad]) {
    testWidgets(
      'on ${device.name} the scene rehearsal opens its heading at her 9vh, '
      'under the way back in her corner, not at the top of the screen',
      (tester) async {
        await _onTheStep(
          tester,
          screen: device.size,
          bar: device.bar,
          step: SceneStep.translate,
        );
        final heading = tester.getRect(find.text('Ensaio da cena'));
        final wayBack = tester.getRect(find.byType(BackToPassageButton));

        expect(
          heading.top,
          closeTo(device.bar + device.size.height * 0.09, 0.01),
          reason:
              'o título ficava a 24 do topo, colado na barra, e o que vinha '
              'embaixo dele passava debaixo da volta',
        );
        expect(
          wayBack.center,
          Offset(
            device.size.width * 0.06 + 20,
            device.bar + device.size.height * 0.05 + 20,
          ),
          reason: 'a volta saiu do canto dela, a 5% e 6%',
        );
      },
    );

    for (final step in [SceneStep.translate, SceneStep.sent]) {
      testWidgets(
        'on ${device.name} the way back on the ${step.name} step covers no '
        'written line and no control, not the start of the listen line',
        (tester) async {
          await _onTheStep(
            tester,
            screen: device.size,
            bar: device.bar,
            step: step,
          );
          final wayBack = tester.getRect(find.byType(BackToPassageButton));
          final covered = [
            for (final type in [Text, RoundActionButton, SceneStrip])
              for (final rect in _rectsOf(type))
                if (rect.overlaps(wayBack)) (type, rect),
          ];

          expect(
            _rectsOf(SceneStrip),
            isNotEmpty,
            reason: 'a faixa do ensaio não estava na tela',
          );
          expect(
            covered,
            isEmpty,
            reason:
                'a volta cobria o começo da linha de escuta e a borda da '
                'faixa no SE',
          );
        },
      );
    }
  }

  for (final step in [SceneStep.record, SceneStep.translate, SceneStep.sent]) {
    testWidgets(
      'on the iPhone SE the ${step.name} step stands her 1.6rem above the '
      'session list, not flush on its heading',
      (tester) async {
        await _onTheStep(tester, screen: _se.size, bar: _se.bar, step: step);
        final area = tester.getRect(
          find
              .descendant(
                of: find.byType(SceneRehearsalView),
                matching: find.byType(Expanded),
              )
              .first,
        );
        final heading = tester.getRect(
          find.text('ENSAIOS DA CENA DESTA SESSÃO'),
        );

        expect(
          heading.top - area.bottom,
          closeTo(1.6 * 16, 0.01),
          reason:
              'a frase cortada na borda da rolagem encostava em «ENSAIOS DA '
              'CENA DESTA SESSÃO»',
        );
      },
    );
  }

  testWidgets(
    'on the iPhone SE a scene being recorded under its chip and over a long '
    'session list scrolls, instead of overflowing under the heading',
    (tester) async {
      final container = await _onTheStep(
        tester,
        screen: _se.size,
        bar: _se.bar,
        step: SceneStep.record,
        listed: 8,
        scenes: const [
          Scene(sceneId: 'S1', title: 'A fome em Belém'),
          Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
        ],
      );
      await tester.tap(byLabel('cena 1 A fome em Belém'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(byLabel('Gravar o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is Microphone,
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(container.read(salaSessionProvider).channel, isA<Microphone>());
      expect(
        tester.takeException(),
        isNull,
        reason:
            'o círculo, a pílula da cena e o estado do take estouravam a '
            'coluna quando o título desceu para os 9vh dela',
      );
    },
  );

  testWidgets(
    'on the iPhone SE at one and a half times the text size the scene '
    'heading takes the width under the way back, not over it',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _onTheStep(
        tester,
        screen: _se.size,
        bar: _se.bar,
        step: SceneStep.translate,
      );
      final heading = tester.getRect(find.text('Ensaio da cena'));
      final wayBack = tester.getRect(find.byType(BackToPassageButton));

      expect(
        heading.width,
        greaterThan(_se.size.width - 120),
        reason: 'o título não chegou a sair de entre as margens',
      );
      expect(
        heading.top,
        closeTo(wayBack.bottom, 0.01),
        reason:
            'o título largo descia só 46 do topo, sobre a volta, e a faixa '
            'de 46 ficava vazia',
      );
    },
  );

  testWidgets(
    'on the iPhone SE at a larger text size a scene rehearsal whose frase '
    'places cannot be read scrolls over a long session list, instead of '
    'overflowing',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _onTheStep(
        tester,
        screen: _se.size,
        bar: _se.bar,
        step: SceneStep.placesUnknown,
        listed: 8,
      );

      expect(find.text('terminei'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason:
            'a etapa sem os lugares das frases era a única que não rolava, '
            'e estourava sob o título nos 9vh dela',
      );
    },
  );
}
