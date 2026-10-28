import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida;
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _backToPassage = 'Voltar para a passagem atual';
const _backToRecording = 'Voltar para a gravação';
const _recordEnsaio = 'Gravar o ensaio de vocês';
const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

Future<void> _pass(WidgetTester tester, [int beats = 10]) async {
  for (var i = 0; i < beats; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _onTheConversation(
  WidgetTester tester,
  SalaHarness harness,
) async {
  harness.room
    ..passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..nextMoment = const Moment(at: MomentAt.internalization, part: 2, parts: 3)
    ..passageScenes = _threeScenes;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  for (var i = 0; i < 30; i++) {
    if (container.read(salaSessionProvider).voice == VoiceState.invite) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 1500));
  return container;
}

Future<void> _onTheHome(WidgetTester tester) async {
  final container = await _onTheConversation(
    tester,
    SalaHarness(filaEmMemoria: true),
  );
  container.read(salaSessionProvider.notifier).goEnsaio();
  await _pass(tester, 20);
  expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
}

Future<void> _onThePlan(WidgetTester tester) async {
  final harness = SalaHarness(filaEmMemoria: true);
  final container = await _onTheConversation(tester, harness);
  final sessionId = container.read(salaSessionProvider).sessionId!;
  harness.room.sceneRehearsals.addAll([
    for (final (n, scene) in [(1, 'S1'), (2, 'S2'), (3, 'S3')])
      SceneRehearsalRecord(
        rehearsalId: '$sessionId-ensaio-$n',
        sessionId: sessionId,
        n: n,
        scene: scene,
        recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
        sentAt: '2026-10-22T10:00:00+00:00',
        durationMs: 7000,
        frases: const [SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 7000)],
        contentType: 'audio/wav',
        verified: true,
      ),
  ]);
  await tester.tap(byLabel(_recordEnsaio));
  await _pass(tester, 20);
  expect(find.text(_planLine), findsOneWidget);
}

Future<void> _onTheCheck(WidgetTester tester) async {
  final container = await aprovadaNaConferida(
    tester,
    SalaHarness(filaEmMemoria: true),
  );
  addTearDown(() => closeTheRoom(container));
  await _pass(tester);
  expect(container.read(salaSessionProvider).stage, SalaStage.retro);
}

void main() {
  for (final (screen, reach, back) in [
    ('recording home', _onTheHome, _backToPassage),
    ('plan', _onThePlan, _backToPassage),
    ('check', _onTheCheck, _backToRecording),
  ]) {
    testWidgets('the way back on the $screen is a bare chevron, not a disc', (
      tester,
    ) async {
      await reach(tester);

      expect(byLabel(back), findsOneWidget);
      expect(
        find.descendant(of: byLabel(back), matching: find.byType(DecoratedBox)),
        findsNothing,
        reason:
            'a volta vestia um disco de 44 px com sombra; a dela é o chevron nu',
      );
    });
  }
}
