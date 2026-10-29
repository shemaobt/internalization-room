import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _onTheConversationOfAnEndedPassage() async {
  final harness = SalaHarness()..room.done = true;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor(
    'the passage to stand at done',
    () => it.estado.sessionId != null && it.estado.voice == VoiceState.done,
  );
  await settle();
  return it;
}

Future<Sala> _relaunched(Sala it) async {
  final session = it.estado.sessionId;
  final (harness, container) = await relaunch(it.harness, it.container);
  final again = Sala(harness, container);
  await again.sala.openTheRoom();
  await waitFor(
    'the relaunch to land on its session',
    () =>
        again.estado.sessionId == session &&
        again.estado.station is Canvas &&
        !again.estado.awaitingTheGuide,
  );
  await settle();
  return again;
}

void main() {
  test('the way back from the recording finds the ended passage still at done, '
      'not at the invite', () async {
    final it = await _onTheConversationOfAnEndedPassage();
    expect(it.estado.orangeDotLook, OrangeDotLook.bright);

    it.sala.openTheEnsaioFinal();
    await waitFor('the recording to open', () => it.estado.station is Ensaio);
    await settle();
    it.sala.leaveTheRecording();
    await settle();

    expect(it.estado.station, isA<Canvas>());
    expect(
      it.estado.voice,
      VoiceState.done,
      reason: 'a volta da gravação deixava a conversa encerrada no convite',
    );
    expect(
      it.estado.orangeDotLook,
      OrangeDotLook.bright,
      reason: 'o ponto laranja voltava apagado',
    );
  });

  test('a relaunch in the Rehearsal of a passage the room has ended lands at '
      'done, not at the invite', () async {
    final it = await umEnsaioGravado(const [Duration(seconds: 5)]);
    it.harness.room.done = true;

    final again = await _relaunched(it);

    expect(
      again.estado.voice,
      VoiceState.done,
      reason: 'o relançamento abria a conversa encerrada no convite',
    );
    expect(again.estado.orangeDotLook, OrangeDotLook.bright);
  });

  test(
    'a relaunch on the conversation of a passage the room has ended lands at '
    'done, not at the invite',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'the opening to be said',
        () =>
            it.estado.sessionId != null && it.estado.voice == VoiceState.invite,
      );
      await settle();
      harness.room.done = true;

      final again = await _relaunched(it);

      expect(
        again.estado.voice,
        VoiceState.done,
        reason: 'o relançamento abria a conversa encerrada no convite',
      );
      expect(again.estado.orangeDotLook, OrangeDotLook.bright);
    },
  );

  test('a relaunch onto an ended session the tablet keeps no row for lands at '
      'done, not at the invite', () async {
    const held = 'sessao-guardada';
    final harness = SalaHarness()..room.done = true;
    (harness.currentSession as FakeCurrentSessionLedger).held =
        const CurrentSession(
          sessionId: held,
          book: 'Ruth',
          pericope: 'P01',
          language: testLanguage,
        );
    harness.room.openedSessions.add(held);
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);

    await it.sala.openTheRoom();
    await waitFor(
      'the relaunch to land on its session',
      () =>
          it.estado.sessionId == held &&
          it.estado.station is Canvas &&
          !it.estado.awaitingTheGuide,
    );
    await settle();

    expect(
      it.estado.voice,
      VoiceState.done,
      reason: 'o relançamento abria a conversa encerrada no convite',
    );
    expect(it.estado.orangeDotLook, OrangeDotLook.bright);
  });

  test('an approved passage the room has ended reopens on its conversation at '
      'done, not at the invite', () async {
    final harness = SalaHarness()..room.done = true;
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
        ],
        checked: true,
      )
      ..takes.add(
        const TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      )
      ..takeAudio['gravacao-1'] = Uint8List.fromList([7, 7, 7, 7]);
    final home = Directory.systemTemp.createTempSync('sala-aprovada');
    addTearDown(() => home.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
      sessionId: 'sessao-aprovada',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File('${home.path}/p1.m4a')..writeAsBytesSync([1])).path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);

    await it.sala.abrirEscolha();
    await settle();
    await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'the approved passage to land on its conversation',
      () =>
          it.estado.station is Canvas &&
          it.estado.sessionId == 'sessao-aprovada' &&
          !it.estado.awaitingTheGuide,
    );
    await settle();

    expect(it.estado.btRascunhoAprovado, isNotNull);
    expect(
      it.estado.voice,
      VoiceState.done,
      reason: 'a passagem aprovada reabria no convite',
    );
    expect(it.estado.orangeDotLook, OrangeDotLook.bright);
  });

  test('leaving the back-translation reads the room again, so the home offers '
      'to bring back what the room now names', () async {
    final it = await umEnsaioGravado(const [Duration(seconds: 5)]);
    it.sala.startRetro();
    await waitFor(
      'the back-translation to open',
      () => it.estado.stage == SalaStage.retro,
    );
    await settle();
    expect(it.estado.toBringBack, isEmpty);
    it.harness.room.retroSoFar = const BackTranslationProgress(
      segments: [],
      bringBack: [1],
    );

    it.sala.leaveTheBackTranslation();
    await settle();

    expect(it.estado.station, const Ensaio());
    expect(
      it.estado.toBringBack,
      [1],
      reason:
          'a casa das gravações ficava com o que lera antes da tradução, '
          'sem o trazer de volta que a sala acendera',
    );
  });
}
