import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

const _reply = HandReply(id: 'r1', audioUrl: '/resposta/r1');

void main() {
  testWidgets(
    'A rebuilt room does not wait on the inbox read its earlier life left in '
    'flight: it reads once, afresh',
    (tester) async {
      final harness = SalaHarness(replies: const [_reply]);
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      SalaSessionNotifier sala() =>
          container.read(salaSessionProvider.notifier);
      SalaSessionState estado() => container.read(salaSessionProvider);

      unawaited(sala().goConversa(book: 'Ruth'));
      await waitFor(
        'a conversa abrir no convite',
        () => estado().sessionId != null && estado().voice == VoiceState.invite,
        step: () => tester.pump(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      harness.inbox.holdNextCheck();
      sala().lookForReplies();
      await tester.pump();
      final beforeTheRebuild = harness.inbox.checks;

      container.invalidate(salaSessionProvider);
      container.read(salaSessionProvider);
      sala().lookForReplies();
      await tester.pump();

      expect(harness.inbox.checks - beforeTheRebuild, 1);
      harness.inbox.finishHeldCheck();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
