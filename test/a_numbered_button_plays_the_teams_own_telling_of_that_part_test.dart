import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _withThreeTellings(
  WidgetTester tester,
) async {
  final tellings = [aKept('S3', 2), aKept('S1', 4), aKept('S2', 6)];
  final (harness, container) = await atRestAfterATurn(tester, tellings);
  harness.room.keptAudio = {
    for (final (index, telling) in tellings.indexed)
      telling.audioUrl: Uint8List.fromList(List.filled(8, 30 + index)),
  };
  return (harness, container);
}

void main() {
  testWidgets('a tap on a number plays the telling kept for that scene', (
    tester,
  ) async {
    final (harness, _) = await _withThreeTellings(tester);

    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.isNotEmpty);

    expect(
      harness.playback.played,
      hasLength(1),
      reason: 'o toque no número não pôs nenhum áudio no ar',
    );
    expect(
      File(harness.playback.played.single).readAsBytesSync(),
      List.filled(8, 32),
      reason: 'o botão 2 tocou o take de outra cena',
    );
    expect(harness.playback.sounding, isTrue);
  });

  testWidgets(
    'while it plays the voice, the circle and the room are exactly as they were',
    (tester) async {
      final (harness, container) = await _withThreeTellings(tester);
      SalaSessionState read() => container.read(salaSessionProvider);
      String circle() => tester
          .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
          .semanticLabel;
      final labelBefore = circle();
      final linesBefore = harness.voice.played.length;

      await tester.tap(byLabel('Hear how you told part 1'));
      await _pumpUntil(tester, () => harness.playback.sounding);
      expect(harness.playback.sounding, isTrue);

      expect(read().voice, VoiceState.invite);
      expect(circle(), labelBefore);
      expect(harness.voice.played.length, linesBefore);
      expect(harness.room.personsAsked, 0);
      expect(read().needsPerson, isFalse);
      expect(read().noteMode, isFalse);
      expect(
        byLabel('Hear how you told part 3'),
        findsOneWidget,
        reason: 'os botões sumiram enquanto o take tocava',
      );
    },
  );

  testWidgets('a second tap on the same number plays it again from the start', (
    tester,
  ) async {
    final (harness, _) = await _withThreeTellings(tester);

    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.isNotEmpty);
    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.length == 2);

    expect(
      harness.playback.played,
      hasLength(2),
      reason: 'o segundo toque no mesmo número não recomeçou o take',
    );
    expect(harness.playback.played.first, harness.playback.played.last);
    expect(harness.playback.playedFrom.last, Duration.zero);
    expect(harness.playback.sounding, isTrue);
  });

  testWidgets('a tap on another number plays that part instead', (
    tester,
  ) async {
    final (harness, _) = await _withThreeTellings(tester);

    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.isNotEmpty);
    await tester.tap(byLabel('Hear how you told part 3'));
    await _pumpUntil(tester, () => harness.playback.played.length == 2);

    expect(
      harness.playback.played.map((path) => File(path).readAsBytesSync()),
      [List.filled(8, 32), List.filled(8, 30)],
      reason: 'o botão 3 não tocou a cena 3 por cima da 2',
    );
    expect(harness.playback.sounding, isTrue);
  });

  testWidgets('a telling already on the tablet is not fetched again', (
    tester,
  ) async {
    final (harness, _) = await _withThreeTellings(tester);

    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.isNotEmpty);
    await tester.tap(byLabel('Hear how you told part 2'));
    await _pumpUntil(tester, () => harness.playback.played.length == 2);

    expect(
      harness.room.keptRetellingsFetched,
      hasLength(1),
      reason: 'o take já guardado era baixado a cada toque',
    );
  });
}
