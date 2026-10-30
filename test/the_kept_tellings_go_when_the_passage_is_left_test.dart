import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

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
  testWidgets('leaving the passage takes its kept tellings off the tablet', (
    tester,
  ) async {
    final (harness, _) = await _withATellingOnTheTablet(tester);

    await tester.tap(byLabel('Choose another passage'));
    await _pumpUntil(tester, () => _keptOnTheTablet(harness).isEmpty);

    expect(
      _keptOnTheTablet(harness),
      isEmpty,
      reason: 'o take baixado ficou no tablet depois de sair da passagem',
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
