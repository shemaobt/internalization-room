import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_question.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart';

const _instruction =
    'Toquem no círculo para gravar o ensaio da cena; toquem de novo para parar.';
const _hint = 'gravem o ensaio da cena na língua materna; toquem para parar';
const _retryWords = 'falhou — toque para tentar de novo';

Future<void> _pumpTheRoom(WidgetTester tester, SceneRoom room) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: room.container,
      child: const SalaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

List<String?> _written(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(SceneRehearsalView),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

void main() {
  testWidgets(
    'the record step writes her instruction under the title and her hint '
    'under the circle, not only for VoiceOver',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
      });
      await _pumpTheRoom(tester, room);

      expect(
        _written(tester),
        ['Ensaio da cena', _instruction, _hint],
        reason:
            'o passo de gravar só escrevia o título; a instrução e a dica '
            'dela eram só rótulos do VoiceOver',
      );
    },
  );

  testWidgets(
    'while the team records, the line under the circle reads «gravando» '
    'with the take\'s clock, not the word alone',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
        await theSceneMicrophoneOpens(room);
      });
      await _pumpTheRoom(tester, room);

      expect(find.text('gravando · 0:00'), findsOneWidget);
      expect(find.text('gravando'), findsNothing);

      await tester.pump(const Duration(seconds: 3));

      expect(
        find.text('gravando · 0:03'),
        findsOneWidget,
        reason: 'o passo de gravar escrevia «gravando» sem o relógio dela',
      );
    },
  );

  testWidgets(
    'while the team records, the step ends at the clock line, with no blank '
    'kept under it for words that are not there',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
        await theSceneMicrophoneOpens(room);
      });
      await _pumpTheRoom(tester, room);

      final step = find
          .descendant(
            of: find.byType(SceneRehearsalView),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      final content = find
          .descendant(of: step, matching: find.byType(Column))
          .first;
      expect(
        tester.getRect(content).bottom,
        closeTo(tester.getRect(find.text('gravando · 0:00')).bottom, 0.5),
        reason:
            'um espaço de 24 pontos ficava embaixo do relógio, separando-o de '
            'nada',
      );
    },
  );

  testWidgets(
    'while the take is kept VoiceOver hears «guardando o ensaio da cena…» '
    'once, from the circle, not again from the line under it',
    (tester) async {
      final semantics = tester.ensureSemantics();
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

      expect(find.text('guardando o ensaio da cena…'), findsOneWidget);
      expect(
        find.bySemanticsLabel('guardando o ensaio da cena…'),
        findsOneWidget,
        reason:
            'o VoiceOver lia «guardando…» duas vezes, no nome do círculo e na '
            'linha escrita embaixo',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'in English the record step writes her English instruction and hint, '
    'not the Portuguese ones',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
      });
      room.container.read(roomLanguageProvider.notifier).choose('en');
      await _pumpTheRoom(tester, room);

      expect(
        _written(tester),
        [
          'Scene rehearsal',
          'Tap the circle to record the scene rehearsal; tap again to stop.',
          'record the scene rehearsal in your own language; tap to stop',
        ],
        reason: 'em inglês a instrução e a dica dela ficavam só no VoiceOver',
      );
    },
  );

  testWidgets(
    'while the team is asked which scene, neither the instruction nor the '
    'hint is written, only her question',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest(
          SalaHarness()
            ..room.passageScenes = const [
              Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
              Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
            ],
        );
        await theScreenOpens(room);
      });
      await _pumpTheRoom(tester, room);

      expect(find.text('Qual cena vocês vão ensaiar?'), findsOneWidget);
      expect(
        find.text(_instruction),
        findsNothing,
        reason: 'a pergunta dela vem sem a instrução de gravar',
      );
      expect(
        find.text(_hint),
        findsNothing,
        reason: 'a pergunta dela vem sem o círculo e sem a dica',
      );
    },
  );

  for (final language in ['pt', 'en']) {
    testWidgets(
      'on a phone, in $language, a failed take under a picked scene and the '
      "session's list scrolls, and every written line comes on screen whole",
      (tester) async {
        tester.view
          ..physicalSize = const Size(375, 667)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late SceneRoom room;
        await tester.runAsync(() async {
          room = await atRest(
            SalaHarness()
              ..room.passageScenes = const [
                Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
                Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
              ],
          );
          room.harness.room.sceneRehearsals.addAll([
            for (var n = 1; n <= 3; n++)
              SceneRehearsalRecord(
                rehearsalId: 'ensaio-da-cena-$n',
                sessionId: room.state.sessionId!,
                n: n,
                recordedAt: DateTime.utc(2026, 10, 28, 10, n),
                sentAt: '2026-10-28T11:0$n:00+00:00',
              ),
          ]);
          await theScreenOpens(room);
        });
        await tester.pump(const Duration(seconds: 1));
        room.sala.pickTheScene('S1');
        expect(room.state.scene.picked, 'S1');
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() async {
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
          room.harness.room.failSceneWith = const NetworkFailed('sem rede');
          room.harness.room.finishHeldKeep();
          await waitFor(
            'o ensaio ficar esperando',
            () => room.state.scene.keep is NotKept,
          );
        });
        room.container.read(roomLanguageProvider.notifier).choose(language);
        await _pumpTheRoom(tester, room);

        expect(room.state.scene.step, SceneStep.record);
        expect(room.state.scene.keep, isA<NotKept>());
        expect(room.state.sceneRehearsals, hasLength(3));
        expect(find.byType(SceneChip), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'a tela transbordava');
        const screen = Rect.fromLTWH(0, 0, 375, 667);
        final written = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SceneRehearsalView),
                matching: find.byType(Text),
              ),
            )
            .toList();
        expect(
          written.map((text) => text.data),
          contains(
            language == 'pt' ? _retryWords : 'failed — tap to try again',
          ),
        );
        for (final text in written) {
          final line = find.byWidget(text);
          await tester.ensureVisible(line);
          await tester.pump(const Duration(milliseconds: 100));
          final rect = tester.getRect(line);
          final paragraph = tester.renderObject(line);
          expect(
            rect.left >= 0 &&
                rect.right <= screen.right &&
                rect.top >= 0 &&
                rect.bottom <= screen.bottom,
            isTrue,
            reason: 'uma linha escrita saía da tela: ${text.data} $rect',
          );
          expect(
            tester
                .hitTestOnBinding(rect.center)
                .path
                .any((entry) => entry.target == paragraph),
            isTrue,
            reason:
                'uma linha escrita ficava cortada ou coberta: ${text.data} $rect',
          );
        }
      },
    );
  }
}
