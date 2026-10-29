import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

void main() {
  test('a halt raised on the scene rehearsal does not stand there, and rises '
      'once the team is back on the conversation', () {
    final (waiting, effects) = reduce(
      const Machine(station: SceneRehearsal()),
      const RoomRaisedAHalt(),
    );

    expect(
      waiting.halt,
      isA<NoHalt>(),
      reason: 'a parada cobria a cena, e o dela só fica sobre a conversa',
    );
    expect(effects, isEmpty);

    final (back, _) = reduce(waiting, const TheSceneRehearsalLeft());

    expect(back.station, isA<Canvas>());
    expect(back.halt, isA<Blocking>());
  });
}
