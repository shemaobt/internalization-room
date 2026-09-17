import 'dart:async';
import 'dart:io';

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
import 'session_notifier_test.dart' show settle;

void main() {
  test('a book with nothing left to offer reaches a person out loud', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.naRoda, isEmpty);
    expect(state.needsPerson, isTrue);
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine, testLanguage)));
  });

  test('a halted room says why it stopped, and says it once', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.escolhaTap();
    notifier.escolhaTap();
    await settle();

    final spoken = harness.voice.assets
        .where((asset) => asset == fixedLineAsset(needsPersonLine, testLanguage));
    expect(spoken.length, 1);
  });

  test('a long press is still a way out of a book with nothing to offer',
      () async {
    final harness = SalaHarness()..room.passages = const [];
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
    await waitFor('a primeira fala ser buscada', () => harness.voice.fetched.isNotEmpty);

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
    await waitFor(
      'o livro ser dado por aberto',
      () => harness.finished.done.any((it) => it.startsWith('livro:')),
    );

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

  test('a passage the room refuses sends the team back to the wheel, not to a person',
      () async {
    final harness = SalaHarness()..room.shutsThePassage = 'P01';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.escolha,
        reason: 'a recusa chegava como sala quebrada e prendia a equipe numa conversa '
            'que nunca abriu');
    expect(harness.voice.assets, isNot(contains(fixedLineAsset(needsPersonLine, testLanguage))),
        reason: 'a sala pedia uma pessoa para uma passagem que pessoa nenhuma abre no tablet');
  });

  test('three passages that cannot open never spend a strike on the room', () async {
    final harness = SalaHarness()..room.shutsThePassage = 'P01';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.entrarNaOferecida();
      await settle();
    }

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isFalse,
        reason: 'a recusa andava na mesma escada do 500, e a terceira parava a sala '
            'para chamar alguém');
    expect(state.stage, SalaStage.escolha);
  });

  test('a refusal anywhere else stops for a person, never for a network that is fine',
      () async {
    final harness = SalaHarness()..room.failWith = const PassageShut();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.offline, isFalse,
        reason: 'a recusa caía no último ramo do funil e a sala dizia, numa rede boa, '
            'que a internet tinha ido embora');
    expect(state.needsPerson, isTrue);
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

    await waitFor('uma resposta chegar sem ser ouvida',
      () => container.read(salaSessionProvider).hasUnheardReply,
    );
    harness.voice.holdNextLine();
    notifier.handTap();
    await waitFor('uma resposta começar a tocar',
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
    await waitFor('a pergunta ser enviada à mão', () => harness.inbox.questionsSent.isNotEmpty);
    await settle();

    expect(harness.voice.assets, contains(fixedLineAsset(handoffLines.first, testLanguage)));
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
      await waitFor(
        'mais uma pergunta ser enviada à mão',
        () => harness.inbox.questionsSent.length > asked,
      );
      await settle();
    }

    final spoken = harness.voice.assets
        .where((asset) => asset.contains('/C'))
        .toList();
    expect(spoken, [
      fixedLineAsset(handoffLines[0], testLanguage),
      fixedLineAsset(handoffLines[1], testLanguage),
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
    await waitFor(
      'a retro começar a tocar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
    );
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
    await waitFor('a sessão sumir', () => container.read(salaSessionProvider).sessionId == null);
    harness.room.failWith = null;

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();

    expect(harness.voice.assets, contains(strandedTakeAsset(testLanguage)));
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
    await waitFor(
      'um trecho da retro falhar',
      () => container.read(salaSessionProvider).btChunkFailures.isNotEmpty,
    );

    harness.room.chunkCaptured = true;
    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor(
      'um trecho da retro passar',
      () => container.read(salaSessionProvider).btChunkPasses.isNotEmpty,
    );

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

  test('a recording written off for a missing file is spoken about too', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    final entry = await harness.takes.enqueue(
      harness.recorder.aFile('sumida'),
      sessionId: 'sessao-de-ontem',
      kind: 'ensaio',
      scope: 'inteira',
    );
    File(entry.path).deleteSync();
    await harness.takes.flush();

    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await settle();

    expect(harness.voice.assets, contains(strandedTakeAsset(testLanguage)),
        reason: 'dar uma gravação por perdida em silêncio é perdê-la duas vezes');
  });

  test('a recording written off with its audio still there is not called stranded',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    final entry = await harness.takes.enqueue(
      harness.recorder.aFile('condenada'),
      sessionId: 'sessao-de-ontem',
      kind: 'ensaio',
      scope: 'inteira',
    );
    final audio = File(entry.path);
    final gravado = audio.readAsBytesSync();
    audio.deleteSync();
    await harness.takes.flush();
    // O áudio está de volta — é o tablet de campo, onde ele nunca chegou a sair.
    audio.writeAsBytesSync(gravado);

    // A conta corre ANTES do flush que vai recuperar a linha: é essa ordem, em
    // session_notifier, que decide se a sala fala.
    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await settle();

    expect(harness.voice.assets, isNot(contains(strandedTakeAsset(testLanguage))),
        reason: 'a linha encalhada existe para dizer que uma gravação não vai subir; '
            'dizê-la de uma que sobe no flush seguinte é dar um susto falso à equipe '
            'justamente nos aparelhos que este conserto veio resgatar');
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
    expect(harness.voice.assets, contains(strandedTakeAsset(testLanguage)));
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
    await waitFor('uma segunda fala ser buscada', () => harness.voice.fetched.length > 1);

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

    // A person comes, marks the session attended on the desk, and holds the screen: the
    // touch asks the room now and brings back the answer the facilitator just wrote.
    harness.room.theDeskAttended();
    notifier.resolveWithPerson();
    await waitFor('a sala sair da parada',
        () => !container.read(salaSessionProvider).needsPerson);
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

    await waitFor(
      'uma resposta chegar sem ser ouvida',
      () => container.read(salaSessionProvider).hasUnheardReply,
    );
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

    await waitFor('a sala pedir uma pessoa', () => container.read(salaSessionProvider).needsPerson);

    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine, testLanguage)),
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
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine, testLanguage)));
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
            'btClipEnded nunca chega, o terminei nunca aparece e todo gesto da '
            'tela dos achados exige findings');
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
    await waitFor(
      'a sala se dar por fora do ar',
      () => container.read(salaSessionProvider).offline,
    );

    notifier.handTap();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue,
        reason: 'a mão escrevia needsPerson por cima de offline, e toda volta — o timer, '
            'a escuta de rede, o toque — é guardada em state.offline');

    harness.network.reachable = true;
    harness.room.reachable = true;
    await waitFor('a sala voltar ao ar',
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
    await waitFor('a sala pedir uma pessoa',
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

  test('a turn recorded into nothing stops the room instead of going up', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    final subiram = harness.room.turnsSent;
    harness.recorder.returnsEmpty = true;
    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, subiram,
        reason: 'o arquivo de zero byte subia como turno e a sala respondia a um '
            'silêncio que a equipe nunca disse');
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'gravador que devolve arquivo sem um byte é aparelho com problema, não '
            'pessoa falando baixo — pedir para repetir não esvazia um disco cheio');
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

  test('a question recorded into nothing is not sent, and is not forgotten', () async {
    final harness = SalaHarness();
    final container = await inConversaHarness(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    await settle();
    harness.recorder.returnsEmpty = true;
    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, isEmpty,
        reason: 'a pergunta sem um byte dentro entrava na caixa e ficava esperando '
            'resposta de um facilitador que não tinha o que ouvir');
    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue,
        reason: 'levantar a mão e perguntar no vazio não pode voltar ao convite calado');
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
        reason: 'o primeiro trecho de uma retro nova subia marcado como tradução de novo de um '
            'trecho que não existe, porque _traduzindoDeNovo só é limpo por um chunk que chega');
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

    final ditas = harness.voice.assets.where((a) => a == fixedLineAsset('G0', testLanguage)).length;
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
    await settle();
    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(milliseconds: 900));

    expect(await harness.emAberto.startedIn('Ruth'), isEmpty,
        reason: 'uma passagem aprovada não é trabalho em aberto — conferida '
            'ainda é: a equipe pode fechar o app antes de aprovar, e tem de '
            'voltar ao gesto que falta');
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
