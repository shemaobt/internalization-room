import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart' show waitFor;
import 'scenario_helpers.dart' show byLabel;

const _record = 'Gravar o ensaio da cena';
const _saving = 'guardando o ensaio da cena…';
const _recording =
    'gravem o ensaio da cena na língua materna; toquem para parar';

const _herFill = {
  Brightness.light: [
    Color.fromRGBO(199, 194, 159, .18),
    Color.fromRGBO(199, 194, 159, .06),
  ],
  Brightness.dark: [
    Color.fromRGBO(110, 106, 87, .18),
    Color.fromRGBO(110, 106, 87, .05),
  ],
};

const _telha = {
  Brightness.light: Color(0xFFBE4A01),
  Brightness.dark: Color(0xFFD6612A),
};

Finder theRingNamed(String label) =>
    find.ancestor(of: byLabel(label), matching: find.byType(FacilitatorCircle));

BoxDecoration theEdgeOf(WidgetTester tester, String label) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: byLabel(label),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!
        as BoxDecoration;

int ripplesOf(String label) => find
    .descendant(of: byLabel(label), matching: find.byType(Ripple))
    .evaluate()
    .length;

const _sent = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: 'sessao-1',
  n: 1,
  sentAt: '2026-10-27T10:00:00+00:00',
);

Future<void> _pumpTheRoom(WidgetTester tester, SceneRoom room) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: room.container,
      child: const SalaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final (screen, side) in [(theSE, 172.5), (theIPad, 180.0)]) {
    for (final look in Brightness.values) {
      testWidgets(
        'on ${screen.name} in the ${look.name} look the record circle is her hollow check ring at $side, telha at rest, with no microphone drawn on it',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = look;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await onTheSceneStep(
            tester,
            screen: screen.size,
            bar: screen.bar,
            step: SceneStep.record,
            rehearsals: const [_sent],
          );

          expect(byLabel(_record), findsOneWidget);
          expect(
            theRingNamed(_record),
            findsOneWidget,
            reason:
                'o círculo de gravar era um disco vermelho com o microfone, não '
                'o anel da checagem dela',
          );
          expect(
            tester.widget<FacilitatorCircle>(theRingNamed(_record)).canvas,
            isFalse,
          );
          expect(
            tester.getSize(byLabel(_record)),
            Size.square(side),
            reason: 'o dela é min(46vw, 180px); o nosso tinha 180 em toda tela',
          );
          final edge = theEdgeOf(tester, _record);
          expect(edge.border, Border.all(color: _telha[look]!, width: 1.5));
          expect((edge.gradient! as RadialGradient).colors, _herFill[look]);
          expect(
            find.descendant(of: byLabel(_record), matching: find.byType(Icon)),
            findsNothing,
            reason: 'o anel dela não tem desenho dentro',
          );
        },
      );
    }
  }

  testWidgets(
    'while the team records, the record circle turns azul with her two ripples, not a red disc with a stop square',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
        await theSceneMicrophoneOpens(room);
      });
      await _pumpTheRoom(tester, room);

      expect(byLabel(_recording), findsOneWidget);
      expect(
        theEdgeOf(tester, _recording).border,
        Border.all(color: const Color(0xFF89AAA3), width: 1.5),
        reason: 'gravando, o anel dela fica azul',
      );
      expect(
        ripplesOf(_recording),
        2,
        reason: 'gravando, o dela abre duas ondas, a segunda 1,5 s depois',
      );
    },
  );

  testWidgets(
    'while the take is kept the record circle breathes her areia thinking ring and takes no tap, instead of a faded red disc',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.holdNextKeepBeforeTheRoomActs();
        room.harness.recorder.rehearsalSpeaks = Uint8List.fromList([
          for (var i = 0; i < 1200; i++) (i * 7) % 251,
        ]);
        await theSceneMicrophoneOpens(room);
        room.sala.sceneTap();
        await waitFor(
          'o take chegar à sala',
          () => room.asked('keepSceneRehearsal') > 0,
        );
      });
      await _pumpTheRoom(tester, room);

      expect(byLabel(_saving), findsOneWidget);
      expect(
        theEdgeOf(tester, _saving).border,
        Border.all(color: const Color(0xFFC5C29F), width: 1.5),
        reason: 'guardando, o dela pensa: a borda areia, a respiração de 4,5 s',
      );
      expect(
        tester.widget<Semantics>(byLabel(_saving)).properties.enabled,
        isFalse,
        reason: 'o dela fica desabilitado enquanto guarda',
      );
    },
  );
}
