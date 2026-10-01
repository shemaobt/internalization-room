import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;
import 'um_ensaio_de_tres_partes.dart';

class _DiskThatRefusesTheTake extends TakeUploadQueue {
  _DiskThatRefusesTheTake({required super.room, super.home});

  bool asked = false;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String sessionId,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
  }) async {
    asked = true;
    throw const FileSystemException('disco cheio');
  }
}

String get _stranded => strandedTakeAsset(testLanguage);

Future<(SalaHarness, ProviderContainer, _DiskThatRefusesTheTake Function())>
_inTheRehearsalOverAFullDisk() async {
  _DiskThatRefusesTheTake? disk;
  final harness = SalaHarness(
    takesOverride: (room, home) =>
        disk = _DiskThatRefusesTheTake(room: room, home: () async => home),
  );
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  sala.goEnsaio();
  sala.ensaioTap();
  await waitFor(
    'a parte começar a ser gravada',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
  );
  sala.ensaioTap();
  await waitFor(
    'a parte ficar gravada',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
  );
  return (harness, container, () => disk!);
}

Future<(ProviderContainer, SalaSessionState Function())> _reopensOnPartTwoOfTwo(
  SalaHarness harness,
) async {
  final home = Directory.systemTemp.createTempSync('sala-1172');
  addTearDown(() => home.deleteSync(recursive: true));
  final p1 = File('${home.path}/p1.m4a')..writeAsBytesSync([1, 2, 3]);
  final p2 = File('${home.path}/p2.m4a')..writeAsBytesSync([4, 5, 6]);
  harness.playback.lengths[p1.path] = const Duration(seconds: 10);
  harness.playback.lengths[p2.path] = const Duration(seconds: 10);
  harness.room.retroSoFar = const BackTranslationProgress(
    segments: [
      SegmentView(
        segmentId: 'trecho-1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 6000,
      ),
    ],
  );
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: p1.path,
        takeId: 'gravacao-1',
      ),
      KeptTake(
        scopeId: KeptScope.parte(2),
        path: p2.path,
        takeId: 'gravacao-2',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await sala.abrirEscolha();
  await settle();
  await sala.goConversa(pericope: 'P01');
  await waitFor(
    'a primeira parte entrar no ar no seu cursor',
    () =>
        read().stage == SalaStage.retro &&
        read().btPhase == BtPhase.playing &&
        read().btCursor == const Duration(seconds: 6) &&
        harness.playback.sounding,
  );
  harness.playback.finishPlayback();
  await waitFor('a primeira parte terminar', () => read().btParteFronteira);
  return (container, read);
}

void main() {
  test('a Guide line that arrives while a part plays waits for the part to '
      'end, then plays', () async {
    final (harness, container, disk) = await _inTheRehearsalOverAFullDisk();
    final sala = container.read(salaSessionProvider.notifier);

    sala.takeKeep();
    sala.playTheRehearsal();
    await waitFor('a parte tocar', () => harness.playback.sounding);
    await waitFor('o disco recusar a parte', () => disk().asked);
    await settle();

    expect(
      harness.voice.assets,
      isNot(contains(_stranded)),
      reason: 'uma linha nunca interrompe uma parte: ela espera o Canal livre',
    );
    expect(harness.playback.sounding, isTrue);

    harness.playback.finishPlayback();
    await waitFor(
      'a linha tocar depois da parte',
      () => harness.voice.assets.contains(_stranded),
    );
  });

  test('the scissors between part two being asked for and its opening sit on '
      'part two\'s Cursor, never on part one\'s position', () async {
    final harness = SalaHarness();
    final (container, read) = await _reopensOnPartTwoOfTwo(harness);
    final sala = container.read(salaSessionProvider.notifier);

    harness.playback.holdNextOpening();
    sala.ouvirGravacao();
    await waitFor('a segunda parte ser pedida', () => read().btParte == 1);
    sala.cortarTrecho();

    expect(read().btCursor, Duration.zero);
    expect(
      read().btCorte,
      read().btCursor,
      reason:
          'antes da abertura a Cabeça é o Cursor da parte 2; os 6 s eram '
          'da parte 1',
    );
    harness.playback.finishHeldOpening();
  });

  test(
    'a part that fails to play leaves the Channel silent, keeps the Cursor, '
    'calls nobody and its bead answers a tap; failing again calls a person',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a primeira parte tocar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            it.harness.playback.sounding,
      );
      final cursor = it.estado.btCursor;
      final asked = it.harness.playback.played.length;

      it.harness.playback.failPlayback();
      await settle();

      expect(it.estado.stage, SalaStage.retro);
      expect(it.estado.needsPerson, isFalse);
      expect(it.harness.room.personsAsked, 0);
      expect(it.estado.channel, const Silence());
      expect(it.estado.btCursor, cursor);

      it.sala.ouvirOTrechoPendente();
      await waitFor(
        'a conta pedir a parte de novo',
        () => it.harness.playback.played.length > asked,
      );

      it.harness.playback.failPlayback();
      await waitFor('a sala chamar uma pessoa', () => it.estado.needsPerson);
    },
  );

  test('a question armed and cancelled after the Watch painted the passage '
      'done leaves the circle on done, and a tap opens no turn', () async {
    final harness = SalaHarness(
      settleDelay: const Duration(milliseconds: 40),
      watchesWithoutAHalt: true,
    );
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    expect(read().voice, VoiceState.invite);

    sala.handTap();
    expect(read().noteMode, isTrue);
    harness.room.done = true;
    await waitFor(
      'a batida pintar a passagem',
      () => read().voice == VoiceState.done,
    );

    sala.handTap();

    expect(read().noteMode, isFalse);
    expect(read().voice, VoiceState.done);
    final turns = harness.room.turnsSent;
    sala.conversaTap();
    await settle();
    expect(harness.room.turnsSent, turns);
  });

  group('the spontaneous lines wait for the Channel', () {
    test('the facilitator\'s reply asked for under an open microphone plays '
        'only after it closes', () async {
      final harness = SalaHarness(
        replies: const [HandReply(id: 'r1', audioUrl: '/resposta-1')],
      );
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await waitFor('a resposta chegar à mão', () => read().hasUnheardReply);

      sala.conversaTap();
      await waitFor(
        'o microfone abrir',
        () => read().voice == VoiceState.listening,
      );
      sala.handTap();
      await settle();

      expect(harness.voice.played, isNot(contains('/resposta-1')));

      sala.conversaTap();
      await waitFor(
        'a resposta tocar depois do microfone',
        () => harness.voice.played.contains('/resposta-1'),
      );
    });

    test('the stranded line arriving under an open microphone plays only after '
        'it closes', () async {
      final (harness, container, disk) = await _inTheRehearsalOverAFullDisk();
      final sala = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      sala.takeKeep();
      sala.ensaioTap();
      await waitFor(
        'a parte seguinte começar a ser gravada',
        () => read().ensaio == EnsaioStatus.recording,
      );
      await waitFor('o disco recusar a parte', () => disk().asked);
      await settle();

      expect(harness.voice.assets, isNot(contains(_stranded)));

      sala.ensaioTap();
      await waitFor(
        'a linha tocar depois do microfone',
        () => harness.voice.assets.contains(_stranded),
      );
    });
  });
}
