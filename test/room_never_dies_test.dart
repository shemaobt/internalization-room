import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
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
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => container.read(salaSessionProvider).btPhase == BtPhase.playing);
    await settle();

    final queued = await harness.takes.entries();
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
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await until(() => container.read(salaSessionProvider).btChunkFailures.isNotEmpty);

    harness.room.chunkCaptured = true;
    harness.playback.at = const Duration(seconds: 30);
    notifier.retroTap();
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

  test('hearing again is not offered on top of the retro clip', () async {
    final harness = SalaHarness();
    harness.room.verdictChecked = false;
    harness.room.verdictFinding = BtFindingKind.missing;
    harness.room.verdictFindingChunk = 0;
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
