import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

const _twoPassages = [
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
];

bool _onTheChoice(ProviderContainer container) {
  final state = container.read(salaSessionProvider);
  return state.entriesOpen && state.theWayBackIsLive;
}

void _openP02(ProviderContainer container) {
  final state = container.read(salaSessionProvider);
  container
      .read(salaSessionProvider.notifier)
      .openTheEntry(state.naRoda!.firstWhere((p) => p.pericope == 'P02'));
}

List<String> _keptOnTheTablet(SalaHarness harness) => harness.recorder.home
    .listSync()
    .map((entry) => entry.uri.pathSegments.last)
    .where((name) => name.startsWith('kept-'))
    .toList();

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _withATellingOnTheTablet(
  WidgetTester tester,
) async {
  final tellings = [aKept('S1', 1), aKept('S2', 2), aKept('S3', 3)];
  final (harness, container) = await atRestAfterATurn(tester, tellings);
  harness.room.keptAudio = {
    for (final telling in tellings)
      telling.audioUrl: Uint8List.fromList(List.filled(8, 30)),
  };
  await tester.tap(byLabel('Hear how you told part 2'));
  await _pumpUntil(tester, () => _keptOnTheTablet(harness).isNotEmpty);
  expect(_keptOnTheTablet(harness), hasLength(1));
  return (harness, container);
}

void main() {
  testWidgets('the passage left keeps its kept tellings while it waits under '
      'the Choice, and they go when another passage opens', (tester) async {
    final (harness, container) = await _withATellingOnTheTablet(tester);
    harness.room.passages = _twoPassages;

    await tester.tap(byLabel('Choose another passage'));
    await _pumpUntil(tester, () => _onTheChoice(container));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      _keptOnTheTablet(harness),
      hasLength(1),
      reason: 'o take baixado saiu do tablet com a passagem ainda guardada',
    );

    _openP02(container);
    await _pumpUntil(tester, () => _keptOnTheTablet(harness).isEmpty);

    expect(
      _keptOnTheTablet(harness),
      isEmpty,
      reason: 'o take baixado ficou no tablet depois de abrir outra passagem',
    );
  });

  testWidgets('offline, a kept telling of the passage left plays again once a '
      'failed open lays that passage back', (tester) async {
    final (harness, container) = await _withATellingOnTheTablet(tester);
    harness.room.passages = _twoPassages;
    await tester.tap(byLabel('Choose another passage'));
    await _pumpUntil(tester, () => _onTheChoice(container));
    harness.room
      ..reachable = false
      ..failKeptRetellingWith = const NetworkFailed('sem rede');

    _openP02(container);
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).pericope == 'P01',
    );
    await tester.pump(const Duration(milliseconds: 300));
    final played = harness.playback.played.length;
    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.length > played);

    expect(
      harness.playback.played.skip(played),
      [contains('kept-')],
      reason: 'sem rede, o take guardado da passagem deixada não tocava mais',
    );
  });

  testWidgets('starting over takes the kept tellings off the tablet', (
    tester,
  ) async {
    final (harness, container) = await _withATellingOnTheTablet(tester);

    container.read(salaSessionProvider.notifier).beginAgain();
    await _pumpUntil(tester, () => _keptOnTheTablet(harness).isEmpty);

    expect(
      _keptOnTheTablet(harness),
      isEmpty,
      reason: 'o take baixado ficou no tablet depois de recomeçar',
    );
  });

  testWidgets(
    'a session the room lost takes its kept tellings off the tablet',
    (tester) async {
      final (harness, container) = await _withATellingOnTheTablet(tester);
      harness.room.forgetTheSession(
        container.read(salaSessionProvider).sessionId!,
      );
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.conversaTap();
      await tester.pump(const Duration(milliseconds: 300));
      notifier.conversaTap();
      await _pumpUntil(
        tester,
        () => container.read(salaSessionProvider).sessionId == null,
      );
      await _pumpUntil(tester, () => _keptOnTheTablet(harness).isEmpty);

      expect(
        container.read(salaSessionProvider).sessionId,
        isNull,
        reason: 'a sala não largou a sessão que o servidor perdeu',
      );
      expect(
        _keptOnTheTablet(harness),
        isEmpty,
        reason: 'o take baixado ficou no tablet depois da sessão perdida',
      );
    },
  );

  testWidgets('a telling that lands after the passage was left is not kept', (
    tester,
  ) async {
    final tellings = [aKept('S1', 1), aKept('S2', 2), aKept('S3', 3)];
    final (harness, container) = await atRestAfterATurn(tester, tellings);
    harness.room.keptAudio = {
      for (final telling in tellings)
        telling.audioUrl: Uint8List.fromList(List.filled(8, 30)),
    };
    harness.room.holdNextKeptRetelling();
    await tester.tap(byLabel('Hear how you told part 2'));
    await tester.pump(const Duration(milliseconds: 200));
    container.read(salaSessionProvider.notifier).leaveThePassage();
    await tester.pump(const Duration(milliseconds: 300));

    harness.room.finishHeldKeptRetelling();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      _keptOnTheTablet(harness),
      isEmpty,
      reason: 'o take que chegou depois da saída ficou guardado no tablet',
    );
  });
}
