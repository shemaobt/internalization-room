import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;
import 'um_ensaio_de_tres_partes.dart';

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
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  await sala.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor(
    'a primeira parte entrar no ar no seu cursor',
    () =>
        read().stage == SalaStage.retro &&
        read().btPhase == BtPhase.playing &&
        read().btCursor == const Duration(seconds: 6) &&
        harness.playback.sounding,
  );
  return (container, read);
}

void main() {
  test('the scissors between part two being asked for and its opening sit on '
      'part two\'s Cursor, never on part one\'s position', () async {
    final harness = SalaHarness();
    final (container, read) = await _reopensOnPartTwoOfTwo(harness);
    final sala = container.read(salaSessionProvider.notifier);

    harness.playback.holdNextOpening();
    harness.playback.finishPlayback();
    await waitFor('a segunda parte ser pedida', () => read().btParte == 1);
    sala.retroTap();

    expect(read().btCursor, Duration.zero);
    expect(
      read().btCorte,
      const Duration(milliseconds: 200),
      reason:
          'antes da abertura a Cabeça é o Cursor da parte 2; os 6 s eram '
          'da parte 1',
    );
    harness.playback.finishHeldOpening();
  });

  test(
    'a part that fails to play leaves the Channel silent, keeps the Cursor, '
    'calls nobody and its bead answers a tap; failing again still calls nobody',
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
      await settle();

      expect(
        it.estado.needsPerson,
        isFalse,
        reason:
            'só a voz do Guia falhando duas vezes chama alguém; uma parte que '
            'falha deixa silêncio',
      );
      expect(it.harness.room.personsAsked, 0);
      expect(it.estado.channel, const Silence());
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

  test('a reply asked for at the idle turn survives re-entering the same '
      'conversation', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/resposta-1')],
    );
    harness.emAberto.rows['Ruth/P01/pt'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.conversa,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor('a resposta chegar à mão', () => read().hasUnheardReply);
    harness.voice.holdNextLine();
    sala.handTap();
    await waitFor('a resposta tocar', () => read().playingReplyId != null);

    unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await settle();
    harness.voice.finishHeldLine();
    await settle();

    expect(read().hasUnheardReply, isTrue);
    expect(harness.inbox.heard, isEmpty);

    sala.handTap();
    await waitFor(
      'a resposta ser ouvida depois de reentrar na mesma conversa',
      () => harness.inbox.heard.contains('r1'),
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

    expect(read().replies.single.failures, 0);
  });
}
