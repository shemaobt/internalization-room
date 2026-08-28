import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle, until;

void main() {
  test('a book with nothing left to offer reaches a person out loud', () async {
    final harness = SalaHarness();
    harness.finished.done.addAll({'Ruth/P01', 'Ruth/P02', 'Ruth/P03'});
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.naRoda, isEmpty);
    expect(state.needsPerson, isTrue);
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)));
  });

  test('a halted room says why it stopped, and says it once', () async {
    final harness = SalaHarness();
    harness.finished.done.addAll({'Ruth/P01', 'Ruth/P02', 'Ruth/P03'});
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.escolhaTap();
    notifier.escolhaTap();
    await settle();

    final spoken = harness.voice.assets
        .where((asset) => asset == fixedLineAsset(needsPersonLine));
    expect(spoken.length, 1);
  });

  test('a long press is still a way out of the finished book', () async {
    final harness = SalaHarness();
    harness.finished.done.addAll({'Ruth/P01', 'Ruth/P02', 'Ruth/P03'});
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.resolveWithPerson();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });

  test('the room is thinking while the clip is still coming down', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.holdNextFetch();
    unawaited(notifier.abrirEscolha());
    await until(() => harness.voice.fetched.isNotEmpty);

    expect(container.read(salaSessionProvider).voice, VoiceState.thinking);

    harness.voice.finishHeldFetch();
    await settle();
    expect(harness.voice.played, isNotEmpty);
  });

  test('the panorama is offered once per book, not once per opening', () async {
    final harness = SalaHarness();
    final first = harness.container();
    addTearDown(first.dispose);

    await first.read(salaSessionProvider.notifier).openTheRoom();
    await settle();
    expect(first.read(salaSessionProvider).stage, SalaStage.convite);

    await first.read(salaSessionProvider.notifier).openConvite();
    await until(() => harness.finished.done.any((it) => it.startsWith('livro:')));

    final second = harness.container();
    addTearDown(second.dispose);
    await second.read(salaSessionProvider.notifier).openTheRoom();
    await settle();

    expect(second.read(salaSessionProvider).stage, SalaStage.escolha);
  });

  test('leaving a passage goes back to the wheel and keeps it there', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);

    notifier.leaveThePassage();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.escolha);
    expect(state.naRoda, hasLength(3));
    expect(harness.finished.done, isEmpty);
  });

  test('a take that finishes playing stops its own pulse', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takePlay();
    await settle();
    expect(container.read(salaSessionProvider).playPing, isTrue);

    harness.playback.finishPlayback();
    await settle();

    expect(container.read(salaSessionProvider).playPing, isFalse);
  });

  test('the circle does not record over the facilitator answering', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
    );
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await until(
      () => container.read(salaSessionProvider).hasUnheardReply,
    );
    harness.voice.holdNextLine();
    notifier.handTap();
    await until(
      () => container.read(salaSessionProvider).playingReplyId != null,
    );

    final before = harness.recorder.captures;
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.captures, before);
    harness.voice.finishHeldLine();
  });

  test('a question sent to a person is answered out loud, not with a knot', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    await settle();
    notifier.conversaTap();
    await until(() => harness.inbox.questionsSent.isNotEmpty);
    await settle();

    expect(harness.voice.assets, contains(fixedLineAsset(handoffLines.first)));
    expect(container.read(salaSessionProvider).knots, 1);
  });

  test('the handoff line rotates, so a second question is not an echo', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    for (var asked = 0; asked < 2; asked++) {
      notifier.handTap();
      await settle();
      notifier.conversaTap();
      await until(() => harness.inbox.questionsSent.length > asked);
      await settle();
    }

    final spoken = harness.voice.assets
        .where((asset) => asset.contains('/C'))
        .toList();
    expect(spoken, [
      fixedLineAsset(handoffLines[0]),
      fixedLineAsset(handoffLines[1]),
    ]);
  });

  test('a stretch the room did not capture is still kept as audio', () async {
    final harness = SalaHarness();
    harness.room.chunkCaptured = false;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await until(() => container.read(salaSessionProvider).btPhase == BtPhase.playing);
    await settle();

    var queued = await harness.takes.entries();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (queued.where((entry) => entry.kind == 'retro').isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      queued = await harness.takes.entries();
    }
    expect(
      queued.where((entry) => entry.kind == 'retro'),
      isNotEmpty,
      reason: 'o servidor devolve 200 sem guardar nada; se o app também soltar, o trecho deixa de existir',
    );
  });

  test('a take with nowhere to go says so instead of filling a bead', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const SessionGone();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await until(() => container.read(salaSessionProvider).sessionId == null);
    harness.room.failWith = null;

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();

    expect(harness.voice.assets, contains(strandedTakeAsset));
  });

  test('leaving a passage does not strand the take on disk', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    final recorded = harness.recorder.lastPath;
    expect(recorded, isNotNull);

    notifier.leaveThePassage();
    await settle();

    expect(harness.recorder.deleted, contains(recorded));
  });

  test('a stretch that failed keeps its own place in the row', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.room.chunkCaptured = false;
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await until(() => container.read(salaSessionProvider).btChunkFailures.isNotEmpty);

    harness.room.chunkCaptured = true;
    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await until(() => container.read(salaSessionProvider).btChunkPasses.isNotEmpty);

    final state = container.read(salaSessionProvider);
    expect(state.btChunkFailures, [1],
        reason: 'o trecho que falhou foi o primeiro, e é a primeira conta que fica oca');
    expect(state.btChunkPasses, hasLength(1));
    expect(
      state.btChunkPasses.length + state.btChunkFailures.length,
      2,
      reason: 'uma conta por trecho contado — nem a mais, nem a menos',
    );
  });

  test('a stranded recording is spoken before any session exists', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await harness.takes.enqueue(
      harness.recorder.aFile('perdida'),
      sessionId: 'sessao-de-ontem',
      kind: 'ensaio',
      scope: 'inteira',
    );
    harness.room.reachable = false;
    for (var wait = 0; wait <= takeUploadWaitsBeforeSaying; wait++) {
      await harness.takes.flush();
    }

    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await settle();

    expect(container.read(salaSessionProvider).sessionId, isNull);
    expect(harness.voice.assets, contains(strandedTakeAsset));
  });

  test('a name already on its way does not speak over where the finger went', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    harness.voice.played.clear();

    harness.voice.holdNextFetch();
    notifier.dizerAPassagem();
    await until(() => harness.voice.fetched.length > 1);

    notifier.apontarPassagem(2);
    harness.voice.finishHeldFetch();
    await settle();

    expect(harness.voice.played, isEmpty,
        reason: 'a fala em curso era da P01; o dedo já estava na P03 quando ela chegou');
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P03');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'e não pode deixar a tela travada em "falando" sobre a passagem errada');
  });

  test('a rehearsal that will not play never opens the terminei', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.failPlayback();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isFalse,
        reason: 'uma falha chegava como conclusão, e é a conclusão que abre o terminei');
    expect(state.canFinishBackTranslation, isFalse);
    expect(state.needsPerson, isTrue,
        reason: 'o áudio da própria equipe não abrir é coisa para uma pessoa olhar');
  });

  test('a retro with no rehearsal reaches a person, not the terminei', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isFalse,
        reason: 'não haver ensaio nenhum não é um ensaio que chegou ao fim');
    expect(state.needsPerson, isTrue);
  });

  test('a ghost play that fails gives the ensaio back its gestures', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();
    notifier.ghostPlay();
    await settle();
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.ghostPlaying);

    harness.playback.failPlayback();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle,
        reason: 'preso em ghostPlaying, o toque no círculo e o botão fantasma não fazem '
            'nada, e o ensaio não desenha o glifo de parada — a tela move e não responde');
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    notifier.resolveWithPerson();
    await settle();
    notifier.ensaioTap();
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recording,
        reason: 'e depois que a pessoa resolve, gravar volta a funcionar');
  });

  test('a reply that will not play does not take the hand with it', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
    );
    harness.voice.succeeds = false;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await until(() => container.read(salaSessionProvider).hasUnheardReply);
    notifier.handTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.hasUnheardReply, isFalse,
        reason: 'a mão oferece sempre a resposta mais antiga não ouvida, então uma que '
            'não toca era oferecida para sempre e a equipe perdia o gesto de perguntar');
    expect(state.needsPerson, isTrue,
        reason: 'a resposta se perdeu — quem transmite agora é uma pessoa');
    expect(harness.inbox.heard, contains('r1'),
        reason: 'e o servidor precisa saber, senão ela volta na próxima abertura');
  });

  test('the server asking for a person is said out loud too', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 30));
    harness.room.serverStatus = 'needs_person';
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);

    await until(() => container.read(salaSessionProvider).needsPerson);

    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)),
        reason: 'o caminho em que o próprio servidor manda parar era o mais mudo dos seis');
  });

  test('a session the room forgot does not keep being told about it', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final asked = harness.room.personsAsked;

    harness.room.failWith = const SessionGone();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.sessionId, isNull);
    expect(state.needsPerson, isTrue);
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)));
    expect(harness.room.personsAsked, asked,
        reason: 'a sessão foi esquecida junto, e é a sessão nula que impede o aviso de '
            'sair — avisar um id que já deu 404 é um 404 atrás do outro');
  });

  test('a room that answers nothing is not a network that is gone', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomSlow();
    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.offline, isFalse,
        reason: 'um turno lento apagava a tela e dizia que a internet tinha caído');
    expect(state.voice, VoiceState.invite,
        reason: 'a sala continua lá — o toque tenta de novo em vez de desistir');
  });

  test('a room that answers nothing three times is finally given up on', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomSlow();
    for (var tentativa = 0; tentativa < 3; tentativa++) {
      await notifier.abrirEscolha();
      await settle();
    }

    final state = container.read(salaSessionProvider);
    expect(state.offline, isTrue);
    expect(state.reach, RoomReach.roomSilent,
        reason: 'e o rosto disso não é a nuvem cortada: a rede está boa, quem não '
            'responde é a sala');
  });

  test('no network and no room wear different faces', () async {
    final harness = SalaHarness()..network.radioSeesNothing = true;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    await settle();

    expect(container.read(salaSessionProvider).reach, RoomReach.noNetwork);

    final semSala = SalaHarness()..network.reachable = false;
    final outro = semSala.container();
    addTearDown(outro.dispose);
    await outro.read(salaSessionProvider.notifier).goConversa();
    await settle();

    expect(outro.read(salaSessionProvider).reach, RoomReach.roomSilent,
        reason: 'endereço errado numa rede perfeita foi o que travou o aparelho hoje, e '
            'a sala disse que a internet tinha caído');
  });

  test('a kept take still reaches the queue when the room is disposed', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    container.dispose();
    await settle(const Duration(milliseconds: 400));

    expect(await harness.takes.entries(), isNotEmpty,
        reason: 'a guarda contra ler providers descartados foi posta antes do '
            'enfileiramento, no método cujo trabalho é não perder gravação');
  });

  test('a rehearsal that will not open leaves a way to make another', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.failPlayback();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'o retro não tem gesto que se recupere de um clipe que não abre: '
            'btClipEnded nunca chega, o terminei nunca aparece e reRecordClip exige findings');
    expect(state.ensaio, EnsaioStatus.idle);
    expect(state.needsPerson, isTrue);
  });

  test('the hand does not bury the way back from an outage', () async {
    // No pending reply on purpose: with one, the hand plays it and never reaches the
    // branch that overwrites the offline state.
    final harness = SalaHarness(retryBackoff: const [Duration(milliseconds: 30)]);
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.network.reachable = false;
    harness.room.reachable = false;
    notifier.conversaTap();
    notifier.conversaTap();
    await until(() => container.read(salaSessionProvider).offline);

    notifier.handTap();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue,
        reason: 'a mão escrevia needsPerson por cima de offline, e toda volta — o timer, '
            'a escuta de rede, o toque — é guardada em state.offline');

    harness.network.reachable = true;
    harness.room.reachable = true;
    await until(
      () => !container.read(salaSessionProvider).offline,
      limit: const Duration(seconds: 3),
    );
    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'e a queda voltava a se curar sozinha');
  });

  test('a settle that finds the session gone halts instead of retrying', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 40));
    final container = harness.container();
    addTearDown(container.dispose);

    // The poll is armed at the end of the opening turn and fires once. Setting the
    // failure here catches that one poll, which is the only thing that reads the session
    // between turns.
    await container.read(salaSessionProvider.notifier).goConversa();
    harness.room.failWith = const SessionGone();
    await until(
      () => container.read(salaSessionProvider).needsPerson,
      limit: const Duration(seconds: 3),
    );

    final state = container.read(salaSessionProvider);
    expect(state.sessionId, isNull,
        reason: 'o 404 caía no catch genérico e virava mais uma tentativa; o disco de '
            'convite seguia respirando sobre uma sessão que o servidor já esqueceu, e a '
            'equipe falava um turno inteiro dentro dela');
  });

  test('a denied microphone leaves no screen pretending to record', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    harness.recorder.permitted = false;
    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle,
        reason: 'a porteira troca a tela, mas o estado embaixo dela é o que a equipe '
            'encontra ao voltar — e ele dizia que a sala estava gravando');
  });

  test('a turn the recorder never handed back is not a shrug', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    harness.recorder.returnsNothing = true;
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a equipe acabou de falar a passagem inteira e nada voltou do gravador; '
            'voltar ao convite em silêncio é o mesmo descarte que o ensaio tinha');
  });

  test('a question the recorder never handed back is not forgotten', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    await settle();
    harness.recorder.returnsNothing = true;
    notifier.conversaTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue);
    expect(state.noteMode, isFalse);
  });

  test('the next passage does not inherit the last one\'s retell', () async {
    final harness = SalaHarness();
    harness.room.verdictChecked = false;
    harness.room.verdictFinding = BtFindingKind.missing;
    harness.room.verdictFindingSegmentId = 'trecho-1';
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();
    notifier.retellChunk();
    await settle();

    notifier.leaveThePassage();
    await settle();
    harness.room.chunkSpans.clear();
    final antes = harness.room.retells;

    notifier.entrarNaOferecida();
    await settle();
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 9);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.retells, antes,
        reason: 'o primeiro trecho de uma retro nova subia marcado como recontagem de um '
            'trecho que não existe, porque _recontando só é limpo por um chunk que chega');
  });

  test('a fresh passage does not inherit the last one\'s strikes', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.succeeds = false;
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'duas falhas ainda não chamam ninguém');

    // Entered with the room still failing, because a turn that lands resets the counters
    // itself — the inheritance only shows when the new passage stumbles too.
    notifier.leaveThePassage();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'a passagem nova começava com as faltas da anterior e parava na primeira');
  });

  test('an inbox that cannot be asked is not an inbox with nothing in it', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 20));
    harness.inbox.cannotBeAsked = true;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    for (var turno = 0; turno < 3; turno++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'chave rotacionada, 500 e timeout liam como "não há respostas", então a '
            'mão emudecia justo quando um facilitador espera ser avisado de que a dele chegou');
  });

  test('a team rehearsing in its own language is not a room in trouble', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.turnsAreCanned = true;
    harness.room.fixedLine = 'G0';

    for (var turno = 0; turno < 3; turno++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    final ditas = harness.voice.assets.where((a) => a == fixedLineAsset('G0')).length;
    expect(ditas, 3,
        reason: 'a parada é na terceira; um teste que não chega lá passa sem nunca ter '
            'exercido a contagem que ele existe para prender');
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'a equipe fazia o que a sala pediu — ensaiar na língua dela — e no terceiro '
            'turno o app parava a sessão para um facilitador que não estava na casa');
  });

  test('a room answering from the tin does not pass for a working one', () async {
    final harness = SalaHarness();
    harness.room.turnsAreCanned = true;
    harness.room.turnsAreDegraded = true;
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    for (var turno = 0; turno < 3; turno++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o servidor avisa que a resposta é enlatada porque o modelo falhou, e o '
            'app zerava todo contador e avançava a passagem em cima disso');
  });

  test('a turn that says nothing about coverage leaves the necklace alone', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 30));
    harness.room.nextCoverage = coverage(engaged: 3, surfaced: 5);
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).coverage.engaged, 3);

    harness.room.silentAboutCoverage = true;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).coverage.engaged, 3,
        reason: 'campo ausente lido como zero esvaziava o colar no meio da passagem — o '
            'único registro de progresso que essa equipe percebe');
  });

  test('coming back to a passage reopens the same session', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    final aberta = container.read(salaSessionProvider).sessionId;
    expect(aberta, isNotNull);

    notifier.leaveThePassage();
    await settle();
    expect(container.read(salaSessionProvider).comecadas, contains('P01'),
        reason: 'a régua desenha essas mais altas, porque voltar a uma é outro ato');

    harness.room.pericopesAsked.clear();
    notifier.entrarNaOferecida();
    await settle();

    expect(container.read(salaSessionProvider).sessionId, aberta,
        reason: 'sair abandonava a sessão no servidor para sempre — e o servidor não a '
            'reencontra, porque ir_sessions não guarda aparelho');
    expect(harness.room.pericopesAsked, isEmpty,
        reason: 'e não se cria outra em cima da que já existe');
  });

  test('a passage carried to the end stops being work in progress', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    // Entered through the wheel, because a resume point is a passage: `goConversa()` with
    // no pericope has nothing to remember.
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    notifier.goEnsaio();
    await settle();
    expect(await harness.emAberto.startedIn('Ruth'), contains('P01'));

    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle(const Duration(milliseconds: 900));

    expect(await harness.emAberto.startedIn('Ruth'), isEmpty,
        reason: 'uma passagem conferida não é trabalho em aberto');
  });

  test('a session the server forgot starts the passage clean', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    notifier.leaveThePassage();
    await settle();

    harness.room.failWith = const SessionGone();
    notifier.entrarNaOferecida();
    await settle();
    harness.room.failWith = null;
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa,
        reason: 'lembrar de uma sessão que o servidor esqueceu não pode virar beco');
  });

  test('hearing again is not offered on top of the retro clip', () async {
    final harness = SalaHarness();
    harness.room.verdictChecked = false;
    harness.room.verdictFinding = BtFindingKind.missing;
    harness.room.verdictFindingSegmentId = 'trecho-nenhum';
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btPhase, BtPhase.findings);
    expect(state.lastSpoken, isNotNull);
    expect(state.voice, VoiceState.invite);
    expect(state.canHearAgain, isFalse);
  });
}

Future<ProviderContainer> inConversaHarness(SalaHarness harness) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}
