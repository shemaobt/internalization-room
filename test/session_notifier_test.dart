import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

Future<void> until(
  bool Function() condition, {
  Duration limit = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<ProviderContainer> inConversa(SalaHarness harness) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}

void main() {
  test('session starts at convite with an inviting voice', () {
    final container = SalaHarness().container();
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);

    expect(state.stage, SalaStage.convite);
    expect(state.voice, VoiceState.invite);
    expect(state.sessionId, isNull);
    expect(state.colarOn, isFalse);
  });

  test('ping range covers newly engaged beads only', () {
    const ping = PingRange(4, 6);

    expect(ping.contains(3), isFalse);
    expect(ping.contains(4), isTrue);
    expect(ping.contains(5), isTrue);
    expect(ping.contains(6), isFalse);
  });

  test('entering the passage opens a session on the backend', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(harness.room.calls, containsAllInOrder(['createSession', 'openSession']));
    expect(container.read(salaSessionProvider).sessionId, 'sessao-1');
    expect(harness.voice.played, hasLength(1));
  });

  test('a turn sends the recording and plays what comes back', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    expect(container.read(salaSessionProvider).voice, VoiceState.listening);

    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, 1);
    expect(harness.voice.played, hasLength(2));
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('the conversation keeps the words and throws the recording away', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, 1);
    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'o registro da conversa é o texto no servidor — o áudio da equipe '
            'não é o produto e não pode ficar enchendo o tablet');
  });

  test('a turn the room refused still throws the recording away', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.failWith = const RoomUnavailable('sem rede');

    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'nenhum caminho de erro reenvia o arquivo, então guardá-lo só ocupa espaço');
  });

  test('the app never decides coverage — it mirrors the server', () async {
    final harness = SalaHarness()..room.nextCoverage = coverage(engaged: 5, surfaced: 7);
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.coverage.engaged, 5);
    expect(state.coverage.surfaced, 7);
    expect(state.coverage.total, totalBeads);
  });

  test('a peer cue from the server hands the talking to the team', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).peerCue, isTrue);
  });

  test('the next tap leaves team-talk mode and addresses the app', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).conversaTap();

    final state = container.read(salaSessionProvider);
    expect(state.peerCue, isFalse);
    expect(state.voice, VoiceState.listening);
  });

  test('beads settle from the server, not from the turn that just spoke', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 80))
      ..room.settledCoverage = coverage(engaged: 3, surfaced: 4);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    expect(container.read(salaSessionProvider).coverage.engaged, 0);

    await settle(const Duration(milliseconds: 300));

    expect(harness.room.calls, contains('fetchState'));
    expect(container.read(salaSessionProvider).coverage.engaged, 3);
  });

  test('the server closing the session puts the circle at rest', () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).voice, VoiceState.done);
    expect(container.read(salaSessionProvider).conversaDone, isTrue);
  });

  test('a fixed line comes from the bundle, never from the wire', () async {
    final harness = SalaHarness()..room.fixedLine = 'D1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(harness.voice.assets, ['assets/audio/fixed/D1.mp3']);
    expect(harness.voice.played, isEmpty,
        reason: 'a linha de segurança não pede rede — a rede costuma ser o que falhou');
    expect(harness.room.clipsFetched, isEmpty);
  });

  test('no network is caught before the team ever taps', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset]);
    expect(harness.room.calls, isEmpty, reason: 'nem tentou falar com o servidor');
  });

  test('a network that cannot reach the backend still counts as offline', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset]);
  });

  test('the room comes back on its own when the network returns', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.network.reachable = true;
    harness.network.networkComesBack();
    await settle();

    expect(container.read(salaSessionProvider).offline, isFalse);
  });

  test('a network blip that still cannot reach the room keeps it offline', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    harness.network.networkComesBack();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue);
  });

  test('the offline notice is spoken once, not on every failure', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    harness.network.networkComesBack();
    harness.network.networkComesBack();
    await settle();

    expect(harness.voice.assets, hasLength(1));
  });

  test('losing the backend mid-session goes offline, not to an error', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.reachable = false;
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue);
  });

  test('a person resolves the offline halt', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).resolveWithPerson();

    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('the room comes back without the network ever changing', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.network.reachable = true;
    await settle();

    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'esperar um evento do sistema que nunca vem prende a sala para sempre');
  });

  test('a tap asks the room again instead of doing nothing', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final checksWhileOffline = harness.network.checks;

    harness.network.reachable = true;
    container.read(salaSessionProvider.notifier).conversaTap();
    await settle();

    expect(harness.network.checks, greaterThan(checksWhileOffline));
    expect(container.read(salaSessionProvider).offline, isFalse);
  });

  test('the notice is not spoken again each time a retry fails', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await until(() => harness.voice.assets.isNotEmpty);
    await settle(const Duration(milliseconds: 200));

    expect(harness.voice.assets, hasLength(1),
        reason: 'a sala repetindo o aviso a cada 20ms é um alarme, não um recado');
  });

  test('the sala asks out loud to be touched, and waits', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).beckon();
    await settle();

    expect(harness.voice.assets, [inviteToStartAsset]);
    expect(harness.room.calls, isEmpty,
        reason: 'o convite falado nao pode abrir sessao — o toque é que começa');
    expect(container.read(salaSessionProvider).awaitingFirstTouch, isTrue);
  });

  test('the invitation is repeated while nobody touches', () async {
    final harness = SalaHarness(beckonInterval: const Duration(milliseconds: 30));
    final container = harness.container();
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).beckon();
    await settle(const Duration(milliseconds: 100));

    expect(harness.voice.assets.length, greaterThan(1),
        reason: 'uma sala em silêncio deixa a equipe sem saber o que fazer');
  });

  test('the touch stops the invitation and starts the panorama', () async {
    final harness = SalaHarness(beckonInterval: const Duration(milliseconds: 30));
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.beckon();
    notifier.conviteTap();
    await settle(const Duration(milliseconds: 120));

    expect(harness.voice.assets, [inviteToStartAsset],
        reason: 'depois do toque o convite nao se repete');
    expect(harness.room.pericopesAsked, [panoramaPericope]);
    expect(container.read(salaSessionProvider).showEntrada, isTrue);
  });

  test('the convite speaks the panorama before offering the way in', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();

    expect(harness.room.pericopesAsked, [panoramaPericope]);
    expect(harness.voice.played, hasLength(1));
    final state = container.read(salaSessionProvider);
    expect(state.conviteStep, ConviteStep.entrada);
    expect(state.showEntrada, isTrue);
    expect(state.sessionId, isNull,
        reason: 'o panorama é do livro; a sessão da perícope nasce ao entrar');
  });

  test('entering after the panorama says the team already met the facilitator',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await notifier.goConversa();
    await settle();

    expect(harness.room.metBefore, [false, true],
        reason: 'sem esse aviso o facilitador se apresenta duas vezes na mesma mesa');
  });

  test('the convite without a room halts spoken, not on a dead screen', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..network.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();

    expect(container.read(salaSessionProvider).offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset]);
    expect(container.read(salaSessionProvider).showEntrada, isFalse);
  });

  test('a room that answers badly does not disguise itself as a dead network',
      () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.offline, isFalse,
        reason: 'chamar de queda de rede uma sala que respondeu errado devolve '
            'a equipe ao aceno para sempre, sem nunca pedir ajuda');
    expect(state.awaitingFirstTouch, isTrue);
    expect(harness.voice.assets, isNot(contains(offlineNoticeAsset)));
  });

  test('three bad answers ask for a person, not for another touch', () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await notifier.openConvite();
    await notifier.openConvite();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    notifier.resolveWithPerson();

    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('a panorama that cannot be spoken leaves a way back', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.conviteStep, ConviteStep.boasVindas,
        reason: 'o passo só avança depois que o panorama foi realmente falado');
    expect(state.awaitingFirstTouch, isTrue);

    notifier.conviteTap();
    await settle();

    expect(harness.room.pericopesAsked, hasLength(2),
        reason: 'um novo toque tenta de novo em vez de bater numa tela morta');
  });

  test('the convite does not stay stuck thinking forever', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 40));
    final container = harness.container();
    addTearDown(container.dispose);
    harness.voice.holdNextLine();

    unawaited(container.read(salaSessionProvider.notifier).openConvite());
    await settle(const Duration(milliseconds: 20));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking);

    await settle(const Duration(milliseconds: 80));

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'uma fala que nunca termina não pode prender a sala em silêncio');
  });

  test('the last line can be heard again without touching the room', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).canHearAgain, isTrue);
    final callsBefore = harness.room.calls.length;

    await notifier.hearAgain();

    expect(harness.voice.played, hasLength(2));
    expect(harness.voice.played.last, harness.voice.played.first);
    expect(harness.room.calls.length, callsBefore,
        reason: 'o áudio já está no disco — repetir não pode custar rede');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('a fixed line is repeated from the bundle', () async {
    final harness = SalaHarness()..room.fixedLine = 'D1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).hearAgain();

    expect(harness.voice.assets, [
      'assets/audio/fixed/D1.mp3',
      'assets/audio/fixed/D1.mp3',
    ]);
    expect(harness.room.clipsFetched, isEmpty);
  });

  test('replaying puts the facilitator back in the speaking state', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).peerCue, isTrue);

    harness.voice.holdNextLine();
    unawaited(notifier.hearAgain());
    await settle(const Duration(milliseconds: 20));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking,
        reason: 'repetindo, quem fala é o facilitador — a bola tem de ser a dele');

    harness.voice.finishHeldLine();
    await settle();

    final after = container.read(salaSessionProvider);
    expect(after.voice, VoiceState.invite);
    expect(after.peerCue, isTrue,
        reason: 'a fala repetida acaba e a equipe segue exatamente onde estava — '
            'a bola da conversa entre eles precisa voltar');
  });

  test('the window closes the moment the team starts recording', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).conversaTap();

    expect(container.read(salaSessionProvider).canHearAgain, isFalse,
        reason: 'gravando, não há mais janela — e o botão sairia debaixo do polegar');
  });

  test('a line that never played is not a line to repeat', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).lastSpoken, isNull);
    expect(container.read(salaSessionProvider).canHearAgain, isFalse);
  });

  test('leaving the stage takes the window with it', () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).goEnsaio();

    expect(container.read(salaSessionProvider).canHearAgain, isFalse);
  });

  test('a line finishing after the stage moved on is not offered there', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.holdNextLine();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    notifier.goEnsaio();
    harness.voice.finishHeldLine();
    await settle();

    expect(container.read(salaSessionProvider).lastSpoken, isNull,
        reason: 'a fala terminou depois da troca de etapa — escrevê-la de volta '
            'ressuscitaria o áudio da etapa anterior');
  });

  test('the question is sent by the circle and cancelled by the hand', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isTrue);

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isFalse);
    expect(container.read(salaSessionProvider).knots, 0);

    notifier.handTap();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).knots, 1);
  });

  test('the knot is tied only after the question actually left', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, ['sessao-1']);
    expect(container.read(salaSessionProvider).knots, 1);
    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'a pergunta já está no servidor, esperando uma pessoa — '
            'a cópia no tablet não serve para nada');
  });

  test('a question that never left is kept on the tablet', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..inbox.refuses = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, isEmpty);
    expect(harness.recorder.deleted, isEmpty,
        reason: 'nada reenvia essa pergunta, mas apagá-la seria destruir '
            'a única cópia de algo que a equipe pediu');
  });

  test('a question that never left ties no knot', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..inbox.refuses = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).knots, 0,
        reason: 'o nó no colar é o registro de uma pergunta feita — desenhá-lo sem '
            'entrega diz a uma equipe que não lê que ela foi ouvida');
    expect(container.read(salaSessionProvider).handAck, isFalse);
  });

  test('an unheard reply waits on the hand and is played on tap', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/api/internalization-room/voice/r1')],
    );
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).hasUnheardReply, isTrue);

    notifier.handTap();
    await settle();

    expect(harness.voice.played, contains('/api/internalization-room/voice/r1'),
        reason: 'a resposta é áudio do servidor, como toda voz que vem de fora');
    expect(container.read(salaSessionProvider).hasUnheardReply, isFalse);
    expect(harness.inbox.heard, ['r1']);
  });

  test('a kept take leaves the tablet', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();

    expect(harness.room.takesKept, ['ensaio/${KeptScope.whole}'],
        reason: 'o ensaio é o produto — um tablet que quebra não pode levar a sessão junto');
    expect(await harness.takes.pending(), isEmpty);
  });

  test('a take recorded with no network waits instead of being lost', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    harness.room.reachable = false;
    notifier.takeKeep();
    await settle();

    expect(harness.room.takesKept, isEmpty);
    expect(await harness.takes.pending(), hasLength(1),
        reason: 'sem rede a tomada fica na fila, e a fila é um arquivo em disco');

    harness.room.reachable = true;
    await harness.takes.flush();

    expect(harness.room.takesKept, ['ensaio/${KeptScope.whole}']);
  });

  test('a take the server has not taken yet is not counted as safe', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    harness.room.reachable = false;
    notifier.takeKeep();
    await settle();

    expect(container.read(salaSessionProvider).unsentTakes, 1,
        reason: 'a conta aparece quando a equipe guarda, mas ainda está só no tablet');

    harness.room.reachable = true;
    await harness.takes.flush();
    await notifier.refreshUnsent();

    expect(container.read(salaSessionProvider).unsentTakes, 0);
  });

  test('the closed necklace opens the room again on its own', () async {
    final harness = SalaHarness(fimLinger: const Duration(milliseconds: 40));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle(const Duration(seconds: 2));

    final after = container.read(salaSessionProvider);
    expect(after.stage, SalaStage.convite,
        reason: 'a equipe contempla o colar fechado e a sala reabre — antes ficava presa ali');
    expect(after.sessionId, isNull);
    expect(after.takes, 0);
  });

  test('the ensaio does not freeze on a ghost play that never ends', () async {
    final harness = SalaHarness(playbackCeiling: const Duration(milliseconds: 40));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.ghostPlay();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.ghostPlaying);

    await settle(const Duration(milliseconds: 140));

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle,
        reason: 'sem teto, uma reprodução interrompida deixava a tela do ensaio '
            'sem nenhum gesto vivo — nada para tocar, e nada escrito para explicar');
  });

  test('the closed room opens again on a touch, not only on its own', () async {
    final harness = SalaHarness(fimLinger: const Duration(seconds: 30));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle(const Duration(seconds: 2));

    expect(container.read(salaSessionProvider).stage, SalaStage.fim);

    notifier.beginAgain();

    expect(container.read(salaSessionProvider).stage, SalaStage.convite,
        reason: 'a tela do fim não tinha alvo de toque nenhum; se a corrente de '
            'temporizadores morresse, a sala ficava branca até matarem o app');
  });

  test('a verdict that lands after the room gave up does not restart it', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 60));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    harness.voice.holdNextLine();
    unawaited(notifier.finishBackTranslation());
    await settle(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o cão de guarda desiste de uma fala que não termina');

    harness.voice.finishHeldLine();
    await settle(const Duration(seconds: 2));

    final after = container.read(salaSessionProvider);
    expect(after.needsPerson, isTrue,
        reason: 'sem guarda de época, o veredito atrasado saltava a equipe para '
            'conferida e fechava o colar por cima de quem já tinha parado a sala');
    expect(after.stage, isNot(SalaStage.fim));
  });

  test('explaining for longer than the clip does not end the clip', () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 200);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle(const Duration(milliseconds: 50));

    harness.playback.at = const Duration(milliseconds: 40);
    notifier.retroTap();
    await settle(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'o teto contava no relógio de parede e não sabia que o clipe '
            'estava pausado, então terminava a gravação no meio da explicação');

    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).btClipEnded, isFalse);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing,
        reason: 'e a escuta volta de onde parou, em vez de ficar muda para sempre');
  });

  test('the retro ignores taps once it has asked for a person', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.room.failWith = const RoomRefused();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    final capturesBefore = harness.recorder.captures;

    notifier.retroTap();
    await settle();

    expect(harness.recorder.captures, capturesBefore,
        reason: 'a equipe falava para um buraco enquanto o círculo mostrava '
            '"chame uma pessoa"');
  });

  test('the room answers the moment the team stops talking', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.voice.assets.first, fixedLineAsset(instantAckLines.first),
        reason: 'a fala de reconhecimento existe aprovada e no pacote desde o '
            'começo, e nada nunca a tocava — a sala esperava calada');
  });

  test('the acknowledgement rotates so the room does not sound stuck', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    for (var turn = 0; turn < 2; turn++) {
      notifier.conversaTap();
      notifier.conversaTap();
      await settle();
    }

    expect(
      harness.voice.assets.where((asset) => asset.contains('/F')).toList(),
      [
        fixedLineAsset(instantAckLines[0]),
        fixedLineAsset(instantAckLines[1]),
      ],
    );
  });

  test('a capture with no speech is answered from the bundle, not from the room',
      () async {
    final harness = SalaHarness(shortestSpeech: const Duration(seconds: 30));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();
    final callsBefore = harness.room.calls.length;

    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.room.calls.length, callsBefore,
        reason: 'a regra existe para que um silêncio não custe nem espera nem '
            'chamada — hoje subia tudo e o servidor decidia depois');
    expect(harness.voice.assets, [fixedLineAsset(inaudibleLines.first)]);
    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'e a sala volta a convidar, pronta para ouvir de novo');
  });

  test('a take that ran out of tries is said out loud, once', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    harness.room.refuseTake = 'ensaio/${KeptScope.whole}';
    notifier.takeKeep();
    await settle();

    for (var attempt = 0; attempt < takeUploadAttempts + 1; attempt++) {
      await harness.takes.flush();
    }
    await notifier.refreshUnsent();
    await notifier.refreshUnsent();

    expect(harness.voice.assets.where((a) => a == strandedTakeAsset), hasLength(1),
        reason: 'a equipe precisa saber que algo ficou preso — e ouvir isso uma vez, '
            'não a cada vez que a conta é recontada');
  });

  test('a chunk the room refused is not counted as safe either', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.room.failWith = const RoomUnavailable('sem rede');
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).unsentChunks, 1,
        reason: 'o trecho subiu junto com a transcrição e falhou — a conta não pode dizer pronto');
  });

  test('a told-back piece goes to the server and nothing is voiced', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    final spokenBefore = harness.voice.played.length;
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunksSent, 1);
    expect(harness.voice.played.length, spokenBefore,
        reason: 'a retomada da gravação é o reconhecimento — nada é falado');
    expect(container.read(salaSessionProvider).btChunkPasses, [1]);
  });

  test('an inaudible piece is not counted', () async {
    final harness = SalaHarness()..room.chunkCaptured = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).btChunkPasses, isEmpty);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
  });

  test('a finding from the server opens the two honest exits', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition;
    final container = await inConversa(harness);
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
    expect(state.btPhase, BtPhase.findings);
    expect(state.btFindings, [BtFindingKind.addition]);
    expect(state.btFindings.single.exitsByReRecording, isTrue);
    expect(harness.voice.played.last, contains('veredito'));
  });

  test('a bad device key asks for a person, not for patience', () async {
    final harness = SalaHarness()..room.failWith = const RoomRefused();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue);
    expect(state.offline, isFalse,
        reason: 'esperar nunca conserta chave errada — não pode virar tela de offline');
    expect(harness.voice.assets, isEmpty);
  });

  test('a session the server no longer has is dropped, not retried forever', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);

    harness.room.failWith = const SessionGone();
    container.read(salaSessionProvider.notifier).conversaTap();
    container.read(salaSessionProvider.notifier).conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).sessionId, isNull);
  });

  test('the server asking for a person is obeyed', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 60))
      ..room.serverStatus = 'needs_person';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
  });

  test('losing the room mid-retro never leaves the screen without a gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.room.reachable = false;
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing,
        reason: 'thinking só avança pela rede — ficaria sem toque e sem volta');
  });

  test('a failed take never destroys the one already kept', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    final guardada = container.read(salaSessionProvider).wholeTake;
    expect(guardada, isNotNull);

    harness.recorder.returnsNothing = true;
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();

    expect(container.read(salaSessionProvider).wholeTake?.path, guardada!.path);
  });

  test('the back-translation reaches conferida and closes the necklace', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
    expect(container.read(salaSessionProvider).btChunkPasses, [1]);

    harness.playback.finishPlayback();
    await settle();
    expect(container.read(salaSessionProvider).canFinishBackTranslation, isTrue);

    await notifier.finishBackTranslation();
    await settle(const Duration(seconds: 2));

    expect(container.read(salaSessionProvider).stage, SalaStage.fim);
  });
}
