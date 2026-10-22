import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/raised_hand.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';

import 'a_hand_host_double.dart';
import 'fakes.dart';

const _reply = HandReply(id: 'resposta-1', audioUrl: '/voz/resposta-1');

Future<void> _theTeamTapsTheHandAndHearsTheReply(
  RaisedHand hand,
  AHandHost host,
) async {
  hand.tap();
  await Future.wait(host.handedOff);
  await pumpEventQueue();
}

void main() {
  test(
    'a reply marked heard is one write that marks it heard and clears the playing reply',
    () async {
      final host = AHandHost()..replies = [_reply];
      final hand = RaisedHand(
        host: host,
        inbox: () => FakeInbox(replies: const []),
        recorder: FakeRecorder.new,
      );

      await _theTeamTapsTheHandAndHearsTheReply(hand, host);

      expect(host.written, ['markPlaying:resposta-1', 'markReplyHeard']);
      expect(
        [for (final reply in host.markedHeard.single) (reply.id, reply.heard)],
        [('resposta-1', true)],
      );
    },
  );

  test('a heard mark the desk refuses gives the reply back unheard', () async {
    final host = AHandHost()..replies = [_reply];
    final inbox = FakeInbox(replies: const [_reply])
      ..marksFailWith = const Refused('REPLY_MOVED_ON');
    final hand = RaisedHand(
      host: host,
      inbox: () => inbox,
      recorder: FakeRecorder.new,
    );

    await _theTeamTapsTheHandAndHearsTheReply(hand, host);

    expect(host.written, [
      'markPlaying:resposta-1',
      'markReplyHeard',
      'showReplies',
    ]);
    expect(
      [for (final reply in host.shown.first) (reply.id, reply.heard)],
      [('resposta-1', false)],
      reason:
          'the desk did not take the mark, so the reply is offered again on '
          'the next touch',
    );
  });
}
