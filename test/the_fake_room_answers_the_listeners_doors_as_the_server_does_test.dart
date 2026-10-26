import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/external_check.dart';

import 'fakes.dart';

void main() {
  late FakeRoom room;
  late File audio;

  setUp(() async {
    room = FakeRoom()
      ..checkTakes = ['tomada-1']
      ..checkFrases = [
        for (final n in [1, 2])
          ExternalCheckFrase(segmentId: 'trecho-$n', number: n),
      ];
    final dir = await Directory.systemTemp.createTemp('sala-fake-');
    addTearDown(() => dir.delete(recursive: true));
    audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3]);
    await room.aNewListener('S', 1, attempt: 'a');
  });

  Future<RoomAnswer<void>> send(
    String kind, {
    String? segment,
    int version = 1,
    int listener = 1,
    File? file,
  }) => room.sendTheListenerRecording(
    'S',
    version,
    listener,
    file ?? audio,
    kind: kind,
    segmentId: segment,
  );

  test(
    'a kind and its segment id that disagree are refused, nothing kept',
    () async {
      for (final refused in [
        await send(listenerWholeComment, segment: 'trecho-1'),
        await send(listenerFraseComment),
        await send(listenerFraseComment, segment: 'trecho-9'),
        await send('outro'),
      ]) {
        expect(refused, const Refused('BAD_REQUEST'));
      }
      expect(room.listenerRecordings, isEmpty);
    },
  );

  test(
    'a frase comment names a frase, or a part on a check with none',
    () async {
      expect(
        await send(listenerFraseComment, segment: 'trecho-2'),
        isA<Answered>(),
      );
      room.checkFrases = const [];
      expect(
        await send(listenerFraseComment, segment: 'tomada-1'),
        isA<Answered>(),
      );
      expect(
        await send(listenerFraseComment, segment: 'trecho-2'),
        isA<Refused>(),
      );
    },
  );

  test('the same bytes sent again by the listener are kept once', () async {
    await send(listenerWholeComment);
    await send(listenerWholeComment);
    expect(room.listenerRecordings, hasLength(1));
  });

  test(
    'a listener is numbered within its version, and known only there',
    () async {
      final second = await room.aNewListener('S', 2, attempt: 'a');
      expect((second as Answered<int>).value, 1);
      expect(await send(listenerWholeComment, version: 2), isA<Answered>());
      expect(
        await send(listenerWholeComment, version: 2, listener: 2),
        const SessionGone(),
      );
      expect(
        await room.markTheFrase('S', 2, 2, 'trecho-1'),
        const SessionGone(),
      );
    },
  );

  test('a mark names a frase and is kept once per listener', () async {
    await room.markTheFrase('S', 1, 1, 'trecho-1');
    await room.markTheFrase('S', 1, 1, 'trecho-1');
    expect(room.listenerMarks, hasLength(1));
    expect(
      await room.markTheFrase('S', 1, 1, 'trecho-9'),
      const Refused('BAD_REQUEST'),
    );
    expect(await room.markTheFrase('S', 1, 7, 'trecho-1'), const SessionGone());
  });
}
