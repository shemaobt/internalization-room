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

Future<void> _intoFindings(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  notifier.startRetro();
  await settle();
  for (final at in const [Duration(seconds: 12), Duration(seconds: 30)]) {
    harness.playback.at = at;
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();
  }
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await settle();
}

Future<void> _intoConferida(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
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
  await settle(const Duration(milliseconds: 900));
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

  test('the coverage necklace steps aside in the retro', () {
    expect(const SalaSessionState(stage: SalaStage.conversa).colarOn, isTrue);
    expect(const SalaSessionState(stage: SalaStage.ensaio).colarOn, isTrue);
    expect(const SalaSessionState(stage: SalaStage.retro).colarOn, isFalse,
        reason: 'na retro as contas são os trechos contados; o colar da '
            'conversa por cima lia como a mesma fileira de novo');
    expect(const SalaSessionState(stage: SalaStage.fim).colarOn, isTrue);
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

    expect(
      harness.room.calls.where((call) => call == 'openSession'),
      hasLength(2),
      reason: 'um novo toque tenta de novo em vez de bater numa tela morta',
    );
    expect(harness.room.pericopesAsked, hasLength(1),
        reason: 'tentar de novo não é abrir outro panorama: cada toque deixava uma sessão abandonada no servidor');
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

    expect(harness.room.takesKept, ['ensaio/${KeptScope.parte(1)}'],
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
    while ((await harness.takes.pending()).isEmpty) {
      await settle(const Duration(milliseconds: 20));
    }

    expect(harness.room.takesKept, isEmpty);
    expect(await harness.takes.pending(), hasLength(1),
        reason: 'sem rede a tomada fica na fila, e a fila é um arquivo em disco');

    harness.room.reachable = true;
    await harness.takes.flush();
    await until(() => harness.room.takesKept.isNotEmpty);

    expect(harness.room.takesKept, ['ensaio/${KeptScope.parte(1)}']);
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

  test('a wheel that failed to load is not a finished book', () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isFalse,
        reason: 'uma lista vazia por falha dizia à equipe que o livro inteiro '
            'já tinha sido trabalhado');
    expect(state.rodaPorLer, isTrue);
    expect(state.needsPerson, isFalse);
  });

  test('the touch is the retry when the wheel never loaded', () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    harness.room.failWith = null;

    notifier.escolhaTap();
    await settle();

    expect(container.read(salaSessionProvider).naRoda, hasLength(3),
        reason: 'sem isso a tela não tinha gesto vivo nenhum: o círculo era morto, '
            'não havia botão, e não há texto que explique o que houve');
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
  });

  test('an empty wheel really does mean the book is done', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isTrue);
    expect(state.rodaPorLer, isFalse);
    expect(state.needsPerson, isTrue,
        reason: 'roda lida e vazia é livro terminado — e terminar o livro é '
            'exatamente o momento de chamar o facilitador');
  });

  test('the wheel reloads itself when the network comes back', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.reachable = false;
    await notifier.abrirEscolha();
    await settle();
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.room.reachable = true;
    harness.network.reachable = true;
    harness.network.networkComesBack();
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).naRoda, hasLength(3),
        reason: '_comeBack não conhecia a escolha: a rede voltava e a roda '
            'continuava vazia para sempre');
  });

  test('the room offers one passage at a time, by voice', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    expect(harness.room.booksAsked, ['Ruth']);
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
    expect(harness.voice.played, ['/voice/p01'],
        reason: 'a equipe escolhe de ouvido: a sala diz a passagem, não a escreve');

    notifier.escolhaTap();
    await settle();

    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01',
        reason: 'o toque no círculo diz de novo; quem anda pela roda é o dedo na régua');
    expect(harness.voice.played, ['/voice/p01', '/voice/p01']);

    notifier.apontarPassagem(1);
    await settle();

    expect(harness.voice.played, ['/voice/p01', '/voice/p01'],
        reason: 'atravessar a régua com o dedo abaixado não dispara catorze nomes');

    notifier.dizerAPassagem();
    await settle();

    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P02');
    expect(harness.voice.played, ['/voice/p01', '/voice/p01', '/voice/p02']);
  });

  test('the row has ends, and stops at them instead of wrapping', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.apontarPassagem(9);
    await settle();
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P03',
        reason: 'a roda dava a volta porque o fim da lista era invisível; a régua '
            'mostra as pontas, e uma ponta que teleporta o dedo desorienta');

    notifier.apontarPassagem(-4);
    await settle();
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
  });

  test('entering carries the chosen passage to the room', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.apontarPassagem(1);
    notifier.dizerAPassagem();
    await settle();

    notifier.entrarNaOferecida();
    await settle();

    expect(harness.room.pericopesAsked, contains('P02'),
        reason: 'o cliente nunca mandava perícope e o servidor caía sempre na P01');
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  test('a passage carried to the end leaves the wheel for good', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    await _intoConferida(harness, notifier);

    await notifier.abrirEscolha();
    await settle();

    expect(
      container.read(salaSessionProvider).naRoda?.map((p) => p.pericope),
      ['P02', 'P03'],
      reason: 'uma perícope terminada nunca se repete — e antes o app refazia '
          'a P01 para sempre',
    );
  });

  test('a finished book reaches a person instead of dying quietly', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isTrue);
    expect(state.needsPerson, isTrue,
        reason: 'um disco verde parado, mudo, recusando todo gesto era '
            'indistinguível de um app morto — e não há texto que explique');
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)),
        reason: 'e a fala para chamar o facilitador já estava no pacote');

    notifier.resolveWithPerson();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'o toque longo tira a sala de lá, como em todo outro halt');
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
    expect(after.stage, SalaStage.escolha,
        reason: 'a sala reabre na escolha, não no convite: voltar ao convite '
            'refazia a mesma perícope para sempre num tablet esquecido ligado');
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

  test('a retro clip that never ends still offers terminei', () async {
    final harness = SalaHarness(playbackCeiling: const Duration(milliseconds: 400));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle(const Duration(milliseconds: 60));

    expect(container.read(salaSessionProvider).canFinishBackTranslation, isFalse);

    await settle(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).canFinishBackTranslation, isTrue,
        reason: 'se a conclusão do clipe se perde, a equipe capturava pedaços '
            'para sempre sem nunca poder concluir');
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

    expect(container.read(salaSessionProvider).stage, SalaStage.escolha,
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

  test('asking for a person in the retro always leaves a live gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);

    notifier.goEnsaio();
    notifier.startRetro();
    await settle();
    harness.room.failWith = const RoomRefused();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(container.read(salaSessionProvider).btPhase, isNot(BtPhase.thinking),
        reason: 'em thinking o círculo é morto e não há botão — a sala ficava '
            'sem nenhum gesto vivo, e o toque longo não a tirava de lá');
  });

  test('the stretch is found by the number the room gave it', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 2;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);

    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(trechos.map((t) => t.index).toList(), [1, 2],
        reason: 'o índice vem do servidor; derivá-lo da posição na lista '
            'desalinha assim que uma resposta se perde depois de persistir');
    expect(harness.playback.ranges.last, '12000-30000');
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

  test('a retold stretch is labelled by the room, not by the app', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 1;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);

    notifier.retellChunk();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).btChunkPasses, [1, 1, 2],
        reason: 'o app fixava a passada em 1 para sempre, então a borda azul da '
            'conta nunca aparecia e o pacote de evidência perdia o rótulo');
  });

  test('the retells run out and the room asks for a person', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 1
      ..room.retells = 2
      ..room.retellBudget = 3;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);

    notifier.retellChunk();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'contar o mesmo trecho de novo era o único ciclo sem teto, e o '
            'orçamento que existia estava numa rota que ninguém chamava');
  });

  test('retelling one stretch keeps every other explanation', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 1;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);
    final before = container.read(salaSessionProvider);
    harness.room.restartsAsked.clear();
    harness.playback.ranges.clear();

    notifier.retellChunk();
    await settle();

    final after = container.read(salaSessionProvider);
    expect(after.btTrechos.length, before.btTrechos.length,
        reason: 'recontar um trecho descartava as explicações de todos os '
            'outros e mandava a equipe reescutar a gravação do zero');
    expect(after.btChunkPasses, before.btChunkPasses);
    expect(harness.room.restartsAsked, isEmpty,
        reason: 'nada é descartado no servidor: o novo pedaço entra junto');
    expect(harness.playback.ranges, hasLength(1),
        reason: 'a sala toca aquele trecho para a equipe contar de novo');
    expect(after.btClipEnded, isTrue,
        reason: 'e o terminei continua ali para reconferir');
  });

  test('throwing the recording away tells the room to forget the old pieces',
      () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier);

    notifier.reRecordClip();
    await settle();

    expect(harness.room.restartsAsked, ['novo-clipe'],
        reason: 'sem avisar, os pedaços do clipe abandonado continuavam na sessão '
            'e voltavam para o analista junto com os novos');
    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
  });

  test('a room that halts for a person says so to the server', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(harness.room.personsAsked, 1,
        reason: 'needs_person tinha consumidor no app e nenhum produtor — o '
            'facilitador nunca ficava sabendo, e uma só vez basta');
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

  test('each pause closes a stretch, and the stretches follow the recording',
      () async {
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

    harness.playback.at = const Duration(seconds: 12);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.at = const Duration(seconds: 30);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['0-12000', '12000-30000'],
        reason: 'sem os limites o pedaço é só um ordinal e ninguém adiante '
            'consegue apontar o áudio que ele explica');
    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(trechos.map((t) => t.to.inSeconds).toList(), [12, 30]);
  });

  test('the verdict takes the team to the part it points at', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 2;
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

    harness.playback.at = const Duration(seconds: 12);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.at = const Duration(seconds: 30);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.finishPlayback();
    await settle();
    harness.playback.ranges.clear();
    await notifier.finishBackTranslation();
    await settle();

    expect(container.read(salaSessionProvider).btFindingChunk, 2);
    expect(harness.playback.ranges, ['12000-30000'],
        reason: 'a sala leva a equipe ao trecho apontado em vez de recomeçar '
            'a passagem inteira');
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
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(1)}';
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
    expect(harness.voice.assets, contains(fixedLineAsset(needsPersonLine)),
        reason: 'pedir uma pessoa em silêncio é um disco parado numa sala que não lê');
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

  test('a take is only offered once the recorder has handed it back', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    await settle();
    harness.recorder.holdNextStop();
    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recording,
        reason: 'os três botões da tomada não podem aparecer enquanto o arquivo '
            'ainda está sendo escrito');

    notifier.takeKeep();
    await settle();
    harness.recorder.finishStop();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);

    notifier.takeKeep();
    await settle();

    expect(container.read(salaSessionProvider).takes, 1,
        reason: 'um keep rápido achava o caminho nulo e descartava a tomada em silêncio');
    expect(container.read(salaSessionProvider).partes, hasLength(1));
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
    final guardada = container.read(salaSessionProvider).partes.firstOrNull;
    expect(guardada, isNotNull);

    final contadas = container.read(salaSessionProvider).takes;
    harness.recorder.returnsNothing = true;
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.partes.firstOrNull?.path, guardada!.path);
    expect(state.ensaio, EnsaioStatus.idle,
        reason: 'oferecer guardar, refazer e ouvir sobre uma tomada que não existe deixava '
            'a equipe confirmar um ensaio no vazio, do mesmo jeito que um bom');
    expect(state.takes, contadas,
        reason: 'e a conta não pode subir por uma gravação que nunca houve');
    expect(state.needsPerson, isTrue,
        reason: 'gravar a passagem inteira e não sair nada é coisa para uma pessoa olhar');
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

  test('the panorama question waits for one spoken answer at the entrada', () async {
    final harness = SalaHarness()..room.bridgeMode = 'calibration_pending';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    harness.room.bridgeMode = 'guided_microchecks';
    notifier.conviteTap();
    await settle();
    expect(container.read(salaSessionProvider).voice, VoiceState.listening,
        reason: 'a pergunta do método foi feita; o círculo escuta a única resposta');
    notifier.conviteTap();
    await until(() => harness.room.turnsSent == 1);
    await settle();

    expect(harness.room.turnsSent, 1,
        reason: 'a resposta vai para a sessão do panorama, uma vez só');
    await notifier.goConversa();
    await settle();
    expect(harness.room.bridgeModesSent.last, 'guided_microchecks',
        reason: 'a escolha feita no panorama viaja com a passagem do mesmo livro');
  });

  test('skipping the method answer sends no mode and never re-asks', () async {
    final harness = SalaHarness()..room.bridgeMode = 'calibration_pending';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await notifier.goConversa();
    await settle();

    expect(harness.room.turnsSent, 0,
        reason: 'entrar direto também é uma resposta: o servidor cai para o modo adaptativo');
    expect(harness.room.bridgeModesSent.last, isNull);
  });

  test('an explicit switch reported by a passage turn is remembered', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.bridgeMode = 'full_retell';
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await until(() => harness.room.turnsSent == 1);
    await settle();
    await notifier.goConversa();
    await settle();

    expect(harness.room.bridgeModesSent.last, 'full_retell',
        reason: 'o servidor decide a troca; o tablet só a carrega para a próxima passagem');
  });

  test('terminei carries how much of the clip was actually heard', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 61);
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.clipDurationsSent, isNotEmpty);
    expect(harness.room.clipDurationsSent.last, 61000,
        reason: 'o alcance tocado é evidência para o artefato do Refine: '
            'o servidor registra o que o tablet realmente deixou tocar');
  });

  test('a line that will not play does not erase the necklace', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.coverage.total, greaterThan(0),
        reason: 'a cobertura é um fato da passagem, não do áudio: a fala que falhou '
            'deixava o fio nu, sem contas e sem o acerto de 30s agendado');
    expect(state.voice, VoiceState.invite);
  });

  test('the necklace divides the moment the session is born', () async {
    final harness = SalaHarness()..voice.holdNextFetch();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    unawaited(notifier.goConversa());
    await until(() => container.read(salaSessionProvider).sessionId != null);

    expect(container.read(salaSessionProvider).coverage.total, greaterThan(0),
        reason: 'o createSession já devolve a cobertura; o colar não espera a voz');
    harness.voice.finishHeldFetch();
    await settle();
  });

  Future<void> gravaParte(SalaSessionNotifier notifier) async {
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();
  }

  test('the rehearsal is told in parts, each kept in order', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    await gravaParte(notifier);

    final state = container.read(salaSessionProvider);
    expect(state.takes, 3);
    expect([for (final t in state.partes) t.scopeId],
        ['parte-1', 'parte-2', 'parte-3']);
    expect(state.ensaio, EnsaioStatus.idle,
        reason: 'guardar uma parte já deixa o círculo pronto para a próxima');
    expect(harness.room.takesKept,
        ['ensaio/parte-1', 'ensaio/parte-2', 'ensaio/parte-3']);
    expect(state.ensaioDone, isTrue);
  });

  test('a part still waiting for its check rides into the retro', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);
    notifier.startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect([for (final t in state.partes) t.scopeId], ['parte-1', 'parte-2'],
        reason: 'um pedaço gravado e ainda sem o check sumia calado no pulo '
            'para a retro');
  });

  test('a recording still running holds the door to the retro', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.ensaioTap();
    await settle();

    notifier.startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio);
    expect(state.ensaio, EnsaioStatus.recording,
        reason: 'avançar no meio de uma gravação a descartaria sem gesto '
            'nenhum da equipe');
  });

  test('the ghost play walks every part in order', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);

    notifier.ghostPlay();
    await settle();
    expect(harness.playback.played, hasLength(1));
    harness.playback.finishPlayback();
    await settle();
    expect(harness.playback.played, hasLength(2),
        reason: 'a parte seguinte toca sozinha quando a anterior acaba');
    harness.playback.finishPlayback();
    await settle();
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle);
  });

  test('the retro pauses at a part boundary and waits for a gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();

    var state = container.read(salaSessionProvider);
    expect(state.btParteFronteira, isTrue);
    expect(state.btClipEnded, isFalse,
        reason: 'a fronteira não é o fim: terminei não pode aparecer aqui');
    expect(harness.playback.played, hasLength(1));

    notifier.proximaParte();
    await settle();
    expect(harness.playback.played, hasLength(2));
    expect(container.read(salaSessionProvider).btParteFronteira, isFalse);

    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();
    state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.canFinishBackTranslation, isTrue);
  });

  test('a stretch told across parts carries global positions', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 1);
    await settle();

    notifier.proximaParte();
    await settle();
    harness.playback.at = const Duration(seconds: 5);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 2);
    await settle();

    expect(harness.room.chunkSpans, ['0-10000', '10000-15000'],
        reason: 'a linha do tempo que o servidor vê continua única: os '
            'deslocamentos somam as partes anteriores');
  });

  test('terminei sums every part the team heard', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.proximaParte();
    await settle();
    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();

    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.clipDurationsSent.last, 18000);
  });

  test('a finding in the second part plays the right stretch of it', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing;
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 1);
    await settle();
    notifier.proximaParte();
    await settle();
    harness.playback.at = const Duration(seconds: 3);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 2);
    await settle();
    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();

    harness.room.verdictFindingChunk = 2;
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.playback.ranges, isNotEmpty);
    expect(harness.playback.ranges.last, '0-3000',
        reason: 'o trecho global 10s–13s vive na parte 2, que começa em 10s: '
            'localmente é 0–3s dentro do arquivo da parte');
    expect(harness.playback.played.last, contains('captura'),
        reason: 'e o arquivo tocado é o da parte 2');
  });

  test('re-recording the clip forgets every part', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingChunk = 1;
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 4);
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 1);
    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.proximaParte();
    await settle();
    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    notifier.reRecordClip();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.partes, isEmpty,
        reason: 'o ghost play tocava o take velho depois de regravar');
    expect(state.takes, 0);
  });

  test('the room stops touching its providers once it is gone', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    container.dispose();

    await settle(const Duration(milliseconds: 400));
  },
      timeout: const Timeout(Duration(seconds: 20)));
}
