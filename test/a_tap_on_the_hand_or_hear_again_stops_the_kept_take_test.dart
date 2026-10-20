import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show aKept, atRestAfterATurn;

const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _withAKeptTakePlaying(
  WidgetTester tester,
) async {
  final tellings = [aKept('S1', 1), aKept('S2', 2), aKept('S3', 3)];
  final (harness, container) = await atRestAfterATurn(tester, tellings);
  harness.room.keptAudio = {
    for (final telling in tellings)
      telling.audioUrl: Uint8List.fromList(List.filled(8, 30)),
  };
  await tester.tap(byLabel('Hear how you told part 2'));
  await _pumpUntil(tester, () => harness.playback.sounding);
  expect(harness.playback.sounding, isTrue);
  return (harness, container);
}

void main() {
  testWidgets('the hand tapped for a reply stops the kept take and plays it', (
    tester,
  ) async {
    final (harness, container) = await _withAKeptTakePlaying(tester);
    harness.inbox.replies = const [_reply];
    container.read(salaSessionProvider.notifier).lookForReplies();
    await _pumpUntil(
      tester,
      () => container.read(salaSessionProvider).hasUnheardReply,
    );

    await tester.tap(byLabel('Hear the facilitator\'s answer'));
    await _pumpUntil(
      tester,
      () => harness.voice.played.contains(_reply.audioUrl),
    );

    expect(
      harness.voice.played,
      contains(_reply.audioUrl),
      reason: 'a resposta esperava o take acabar para tocar',
    );
    expect(
      harness.playback.sounding,
      isFalse,
      reason: 'a resposta tocou por cima do take da mesa',
    );
  });

  testWidgets('the hand tapped to leave a question stops the kept take', (
    tester,
  ) async {
    final (harness, container) = await _withAKeptTakePlaying(tester);

    await tester.tap(byLabel('Leave a question for the facilitator'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).noteMode,
      isTrue,
      reason: 'o toque na mão não armou a pergunta',
    );
    expect(
      harness.playback.sounding,
      isFalse,
      reason: 'o take da mesa seguiu tocando com a pergunta armada',
    );
  });
}
