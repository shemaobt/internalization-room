import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _stamp = '2026-10-19T19:58:13.123456Z';

Future<(ProviderContainer, SalaSessionNotifier)> _inConversa(
  SalaHarness harness,
) async {
  harness.room.verdictCheckAt = _stamp;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await settle();
  return (container, notifier);
}

Future<void> _toTheTelling(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.goEnsaio();
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  await untilTheAdvanceDiscLights(notifier);
  notifier.startRetro();
  await settle();
  harness.playback.finishPlayback();
  await settle();
}

Future<void> _toTheVerdict(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  await _toTheTelling(harness, notifier);
  await notifier.finishBackTranslation();
  await settle();
}

Future<void> _whileTheVerdictPlays(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  await _toTheTelling(harness, notifier);
  harness.voice.holdNextLine();
  unawaited(notifier.finishBackTranslation());
  await waitFor(
    'o veredito começar a tocar',
    () => harness.voice.played.contains(falaDoVeredito),
  );
}

void main() {
  test(
    'a verdict played to its end is reported heard once, with its round\'s stamp',
    () async {
      final harness = SalaHarness();
      final (_, notifier) = await _inConversa(harness);

      await _toTheVerdict(harness, notifier);

      expect(
        harness.room.heardStamps,
        [_stamp],
        reason:
            'o aparelho nunca dizia que a equipe ouviu o veredito até o fim, '
            'e a voz nomeava a mesma nuance a cada rodada',
      );
    },
  );

  test(
    'a verdict cut by leaving the passage is never reported heard, even when the '
    'player later calls the cut line whole',
    () async {
      final harness = SalaHarness()..voice.reportsAStoppedLineWhole = true;
      final (container, notifier) = await _inConversa(harness);
      await _whileTheVerdictPlays(harness, notifier);

      notifier.leaveThePassage();
      await waitFor(
        'a roda abrir',
        () => container.read(salaSessionProvider).stage == SalaStage.escolha,
      );
      harness.voice.theStoppedLineReportsWhole();
      await settle();

      expect(
        harness.room.heardStamps,
        isEmpty,
        reason:
            'a equipe saiu no meio do veredito e a nuance contava como dita; '
            'a próxima rodada não a nomeava de novo',
      );
    },
  );

  test(
    'a verdict cut by a reload is never reported heard, even when the player later '
    'calls the cut line whole',
    () async {
      final harness = SalaHarness()..voice.reportsAStoppedLineWhole = true;
      final (container, notifier) = await _inConversa(harness);
      await _whileTheVerdictPlays(harness, notifier);

      container.dispose();
      await settle();
      harness.voice.finishHeldLine();
      await settle();

      expect(
        harness.room.heardStamps,
        isEmpty,
        reason:
            'o aplicativo recarregou no meio do veredito e a nuance contava '
            'como ouvida até o fim',
      );
    },
  );

  test(
    'a verdict heard again to its end is reported again with the same round\'s stamp',
    () async {
      final harness = SalaHarness();
      harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true;
      final (container, notifier) = await _inConversa(harness);
      await _toTheVerdict(harness, notifier);
      await waitFor(
        'o veredito chegar com os achados',
        () =>
            container.read(salaSessionProvider).btPhase == BtPhase.playing &&
            container.read(salaSessionProvider).btVeredito,
      );
      final faladas = harness.voice.played.length;

      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'a resposta tocar de novo',
        () => harness.voice.played.length == faladas + 1,
      );
      await settle();

      expect(harness.voice.played.last, falaDoVeredito);
      expect(
        harness.room.heardStamps,
        [_stamp, _stamp],
        reason:
            'ouvir a resposta de novo até o fim não dizia nada à sala, e um '
            'primeiro aviso perdido deixava a nuance por dizer para sempre',
      );
    },
  );

  test(
    'a heard report the room never takes is not sent again, and the team sees '
    'nothing of it',
    () async {
      final harness = SalaHarness();
      harness.room.failHeardWith = const NetworkFailed('sem rede');
      final (container, notifier) = await _inConversa(harness);

      await _toTheVerdict(harness, notifier);
      await settle();
      await settle();
      final state = container.read(salaSessionProvider);

      expect(
        harness.room.heardStamps,
        [_stamp],
        reason:
            'um aviso perdido não é tentado de novo: a próxima rodada nomeia a '
            'nuance outra vez',
      );
      expect(state.btPhase, BtPhase.conferida);
      expect(state.needsPerson, isFalse);
    },
  );

  test('a verdict whose first load fails and whose reload plays is reported '
      'heard once', () async {
    final harness = SalaHarness();
    harness.voice.failsToLoad[falaDoVeredito] = 1;
    final (_, notifier) = await _inConversa(harness);

    await _toTheVerdict(harness, notifier);
    await settle(const Duration(milliseconds: 100));

    expect(
      harness.voice.played.where((url) => url == falaDoVeredito),
      hasLength(2),
    );
    expect(harness.room.heardStamps, [_stamp]);
  });

  test('a verdict the player fails on is never reported heard', () async {
    final harness = SalaHarness()..voice.refuses.add(falaDoVeredito);
    final (_, notifier) = await _inConversa(harness);

    await _toTheVerdict(harness, notifier);

    expect(harness.voice.played, contains(falaDoVeredito));
    expect(
      harness.room.heardStamps,
      isEmpty,
      reason: 'o tocador falhou e o veredito contava como ouvido até o fim',
    );
  });

  test('a verdict cut by a lost connection mid-stream, and lost again on its '
      'reload, is never reported heard', () async {
    final harness = SalaHarness();
    final (_, notifier) = await _inConversa(harness);
    await _whileTheVerdictPlays(harness, notifier);

    harness.voice
      ..roomFailsWith = const NetworkFailed('fala cortada')
      ..failHeldLine(const NetworkFailed('fala cortada'));
    await settle();

    expect(
      harness.room.heardStamps,
      isEmpty,
      reason: 'a conexão caiu no meio do veredito e a nuance contava como dita',
    );
  });

  test('a verdict that never loads is not the clip the conversation is kept '
      'ending on', () async {
    final harness = SalaHarness()..voice.refuses.add(falaDoVeredito);
    harness.room.verdictCheckAt = _stamp;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await settle();

    await _toTheVerdict(harness, notifier);
    await settle(const Duration(milliseconds: 100));

    final held = (harness.currentSession as FakeCurrentSessionLedger).held;
    expect(harness.voice.played, contains(falaDoVeredito));
    expect(held?.lastLine?.url, turnoUrl);
  });
}
