import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test('a halt over an opening clip that could not be fetched is lifted by '
      'asking the opening again under a turn id of its own', () async {
    final harness = SalaHarness();
    harness.voice.roomFailsWith = const Refused(RefusalCode.notFound);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('a sala parar', () => read().needsPerson);
    expect(harness.room.turnIdsAsked, hasLength(1));
    final failed = harness.room.turnIdsAsked.single;

    harness.voice.roomFailsWith = null;
    harness.room.theDeskAttended();
    await waitFor(
      'a abertura ser pedida de novo',
      () => harness.room.turnIdsAsked.length == 2,
    );

    expect(
      harness.room.turnIdsAsked.last,
      isNot(failed),
      reason:
          'o mesmo id devolve a mesma resposta lembrada, com o mesmo clipe '
          'que não existe, e a sala pararia de novo a cada soltura',
    );
    await waitFor('a sala seguir', () => !read().needsPerson);
  });
}
