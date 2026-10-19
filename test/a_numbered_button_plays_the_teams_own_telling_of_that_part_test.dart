import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
