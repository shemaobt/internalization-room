import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

void main() {
  test('a reply heard to the end lets the hand go', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/voice/r1')],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa(book: 'Ruth');
    await settle();

    notifier.handTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(harness.inbox.heard, ['r1']);
    expect(
      state.playingReplyId,
      isNull,
      reason:
          'a resposta ouvida até o fim devolve a mão à equipe; presa nela, a '
          'mão seguia acesa e o próximo toque calava a sala antes de agir',
    );
  });
}
