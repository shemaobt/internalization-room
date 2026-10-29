import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'every_way_back_is_her_bare_chevron_test.dart' show expectHerChevron;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _backInPortuguese = 'Voltar para a passagem atual';

List<double> _opacitiesOver(WidgetTester tester, String label) {
  final glyph = find
      .descendant(of: byLabel(label), matching: find.byType(CustomPaint))
      .evaluate()
      .single;
  final labelled = byLabel(label).evaluate().first;
  final over = <double>[];
  glyph.visitAncestorElements((ancestor) {
    if (ancestor == labelled) return false;
    final widget = ancestor.widget;
    if (widget is Opacity) over.add(widget.opacity);
    if (widget is AnimatedOpacity) over.add(widget.opacity);
    if (widget is FadeTransition) over.add(widget.opacity.value);
    return true;
  });
  return over;
}

void main() {
  testWidgets(
    'the way back is dimmed and takes no tap while the scene rehearsal sends',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ]
        ..room.nextMoment = const Moment(
          at: MomentAt.articulation,
          part: 1,
          parts: 3,
        )
        ..room.sceneRehearsals.add(
          SceneRehearsalRecord(
            rehearsalId: 'ensaio-da-cena-1',
            sessionId: 'sessao-1',
            n: 1,
            recordedAt: DateTime(2026, 10, 15, 14, 5),
            frases: const [
              SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 4000),
            ],
          ),
        );
      harness.playback.measured = const Duration(seconds: 20);
      tester.view
        ..physicalSize = const Size(820, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
      for (var i = 0; i < 30; i++) {
        if (container.read(salaSessionProvider).voice == VoiceState.invite) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.tap(byLabel('ensaio da cena'));
      for (var i = 0; i < 30; i++) {
        if (container.read(salaSessionProvider).scene.step ==
            SceneStep.translate) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      harness.room.holdNextTurn();
      await tester.tap(byLabel('terminei'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).stage, SalaStage.cena);
      expectHerChevron(
        tester,
        find.descendant(
          of: byLabel(_backInPortuguese),
          matching: find.byType(CustomPaint),
        ),
        const Color(0xFF777D45),
      );
      expect(_opacitiesOver(tester, _backInPortuguese), contains(0.2));
      expect(
        tester.widget<Semantics>(byLabel(_backInPortuguese)).properties.enabled,
        isFalse,
      );

      await tester.tap(byLabel(_backInPortuguese), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).stage, SalaStage.cena);

      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
