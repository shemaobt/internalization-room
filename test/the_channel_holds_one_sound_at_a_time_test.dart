import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
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

class _OutboxThatGaveUp extends TakeUploadQueue {
  _OutboxThatGaveUp({required super.room, super.home});

  bool gaveUp = false;

  @override
  Future<
    ({
      bool stranded,
      int unsentTakes,
      int unsentChunks,
      Set<String> unsentTakeScopes,
    })
  >
  tally({required String? sessionId}) async {
    final counted = await super.tally(sessionId: sessionId);
    return (
      stranded: gaveUp || counted.stranded,
      unsentTakes: counted.unsentTakes,
      unsentChunks: counted.unsentChunks,
      unsentTakeScopes: counted.unsentTakeScopes,
    );
  }
}

String get _stranded => strandedTakeAsset(testLanguage);

Future<(SalaHarness, ProviderContainer, SalaSessionState Function())>
_aReplyWaitsThroughAFall() async {
  final harness = SalaHarness(
    replies: const [HandReply(id: 'r1', audioUrl: '/resposta-1')],
  );
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await waitFor('a resposta chegar à mão', () => read().hasUnheardReply);

  harness.voice.holdNextLine();
  harness.room.holdNextTurn();
  sala.conversaTap();
  await waitFor('o microfone abrir', () => read().channel is Microphone);
  sala.conversaTap();
  await waitFor('a Guia falar', () => read().channel is GuideSpeaking);
  sala.handTap();
  await settle();
  harness.room.failHeldTurnWith = const NetworkFailed('sem rede');
  harness.room.finishHeldTurn();
  await waitFor('a sala cair', () => read().unreachable);
  await waitFor('a sala voltar', () => !read().unreachable);
  expect(read().stage, SalaStage.conversa);
  harness.voice.finishHeldLine();
  return (harness, container, read);
}

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

  test('a reply waiting while the room falls out of reach and comes back in '
      'the same Step still plays', () async {
    final (harness, _, _) = await _aReplyWaitsThroughAFall();

    await waitFor(
      'a resposta tocar',
      () => harness.voice.played.contains('/resposta-1'),
    );
  });

  test(
    'a reply that waited through a fall and played is marked heard',
    () async {
      final (harness, _, read) = await _aReplyWaitsThroughAFall();
      await waitFor(
        'a resposta tocar',
        () => harness.voice.played.contains('/resposta-1'),
      );

      await waitFor('a resposta ficar ouvida', () => !read().hasUnheardReply);
      expect(harness.inbox.heard, contains('r1'));
    },
  );

  test('a line waiting in the conversation survives re-entering the same '
      'conversation', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/resposta-1')],
    );
    harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.conversa,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(pericope: 'P01');
    await waitFor('a resposta chegar à mão', () => read().hasUnheardReply);
    harness.voice.holdNextLine();
    sala.sayTheMicIsBlocked();
    await waitFor('a Guia falar', () => read().channel is GuideSpeaking);
    sala.handTap();
    await settle();
    expect(harness.voice.played, isNot(contains('/resposta-1')));

    unawaited(sala.goConversa(pericope: 'P01'));
    await waitFor(
      'a resposta tocar depois de reentrar na mesma conversa',
      () => harness.voice.played.contains('/resposta-1'),
    );
  });

  test('a line waiting on the wheel survives the wheel read again in the same '
      'visit', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    final oferecida = read().oferecida!.audioUrl;
    await waitFor(
      'a roda dizer a passagem',
      () => harness.voice.played.where((url) => url == oferecida).length == 1,
    );
    await settle();
    harness.voice.holdNextLine();
    sala.sayTheMicIsBlocked();
    await waitFor('a Guia falar', () => read().channel is GuideSpeaking);
    sala.escolhaTap();
    await settle();

    unawaited(sala.abrirEscolha());
    await waitFor(
      'a passagem que esperava tocar',
      () => harness.voice.played.where((url) => url == oferecida).length == 2,
    );
    harness.voice.finishHeldLine();
    await waitFor(
      'a passagem que esperava e a da roda relida tocarem',
      () => harness.voice.played.where((url) => url == oferecida).length == 3,
    );
  });

  test('a line waiting while the room silences and then plays a stretch '
      'waits for that stretch', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    it.harness.room.verdictChecked = true;
    await pedirOVeredito(it);
    expect(it.estado.btPhase, BtPhase.conferida);
    final bloqueado = micBlockedAsset(testLanguage);
    it.harness.room
      ..releaseBlockers = const ['untold_stretch']
      ..releaseUntoldSegmentId = 'trecho-1';
    final lidas = it.harness.room.heldReads.length;
    it.harness.room.holdTheNextRead();
    unawaited(it.sala.aprovarRascunhoFinal());
    await waitFor(
      'a sala reler os trechos',
      () => it.harness.room.heldReads.length > lidas,
    );
    it.sala.ouvirGravacao();
    await waitFor('a parte tocar', () => it.estado.channel is PartPlaying);
    it.sala.sayTheMicIsBlocked();
    await settle();
    expect(it.harness.voice.assets, isNot(contains(bloqueado)));

    it.harness.room.answerHeldRead(it.harness.room.heldReads.length - 1);
    await waitFor('o trecho tocar', () => it.estado.btTrechoTocando);

    expect(
      it.harness.voice.assets,
      isNot(contains(bloqueado)),
      reason:
          'a linha esperava, e nenhum silêncio entre o gesto e o trecho a solta',
    );
    it.harness.playback.finishPlayback();
    await waitFor(
      'a linha tocar depois do trecho',
      () => it.harness.voice.assets.contains(bloqueado),
    );
  });

  test('a line waiting while a gesture silences the room and then finds '
      'nothing to play is played', () async {
    _OutboxThatGaveUp? outbox;
    final harness = SalaHarness(
      takesOverride: (room, home) =>
          outbox = _OutboxThatGaveUp(room: room, home: () async => home),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);
    await it.sala.goConversa(pericope: 'P01');
    await waitFor('a sala abrir', () => it.estado.sessionId != null);
    it.sala.goEnsaio();
    await gravarUmaParteDoEnsaio(it);
    it.sala.startRetro();
    await waitFor(
      'a parte tocar',
      () => it.estado.stage == SalaStage.retro && it.estado.btClipRodando,
    );
    await ouvirETraduzirAParteInteira(it, const Duration(seconds: 10));
    harness.room.segments.add(
      const SegmentView(
        segmentId: 'trecho-9',
        takeId: 'gravacao-9',
        startsMs: 0,
        endsMs: 4000,
      ),
    );
    harness.room
      ..verdictChecked = false
      ..verdictHasFinding = true
      ..verdictFindingSegmentId = 'trecho-9';
    await pedirOVeredito(it);
    await waitFor(
      'o achado apontar o trecho sem áudio no tablet',
      () =>
          it.estado.btPhase == BtPhase.findings &&
          it.estado.btFindingTrecho?.segmentId == 'trecho-9',
    );

    harness.voice.holdNextLine();
    it.sala.sayTheMicIsBlocked();
    await waitFor('a Guia falar', () => it.estado.channel is GuideSpeaking);
    outbox!.gaveUp = true;
    await it.sala.refreshUnsent();
    expect(harness.voice.assets, isNot(contains(_stranded)));

    it.sala.ouvirOTrechoEATraducao();
    await waitFor(
      'a linha que esperava tocar quando o gesto não tocou nada',
      () => harness.voice.assets.contains(_stranded),
    );
  });

  test('a waiting line is never started and then cut while a gesture hands '
      'off to the passage it opens', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    final bloqueado = micBlockedAsset(testLanguage);
    await sala.abrirEscolha();
    await waitFor('a roda carregar', () => read().naRoda != null);
    await settle();
    harness.voice.holdNextLine();
    sala.sayTheMicIsBlocked();
    await waitFor('a Guia falar', () => read().channel is GuideSpeaking);
    sala.sayTheMicIsBlocked();
    expect(read().machine.queue, hasLength(1));
    harness.network.holdNextCheck();

    sala.entrarNaOferecida();
    await settle();
    harness.network.finishHeldCheck();
    await waitFor(
      'a passagem abrir',
      () => read().stage == SalaStage.conversa && read().sessionId != null,
    );
    harness.voice.finishHeldLine();
    await settle();

    expect(
      harness.voice.assets.where((asset) => asset == bloqueado),
      hasLength(1),
      reason: 'a linha que esperava nunca começa para ser cortada logo depois',
    );
  });

  test('a reply silenced by a gesture is not counted against it when the room '
      'then fails', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/resposta-1')],
    );
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await waitFor('a resposta chegar à mão', () => read().hasUnheardReply);
    harness.voice.holdNextLine();
    sala.handTap();
    await waitFor(
      'a resposta começar',
      () => harness.voice.played.contains('/resposta-1'),
    );

    sala.goEnsaio();
    harness.voice.failHeldLine(const NetworkFailed('sem rede'));
    await settle();

    expect(read().replies.single.failedPlays, 0);
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
