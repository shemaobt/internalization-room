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

  test('a halt raised on the external check does not stand there', () {
    final (waiting, effects) = reduce(
      const Machine(station: ChecagemExterna(1)),
      const RoomRaisedAHalt(),
    );

    expect(
      waiting.halt,
      isA<NoHalt>(),
      reason: 'a parada cobria a checagem, e o dela só fica sobre a conversa',
    );
    expect(waiting.aHaltWaitsForTheCanvas, isTrue);
    expect(effects, isEmpty);
  });

  test('a halt waiting from the external check is dropped when the team goes '
      'back to the back-translation, not carried to a later conversation', () {
    final (waiting, _) = reduce(
      const Machine(station: ChecagemExterna(1)),
      const RoomRaisedAHalt(),
    );

    final (back, _) = reduce(waiting, const TheExternalCheckLeft());
    final (onTheCanvas, _) = reduce(back, const TheRecordingLeft());

    expect(back.station, isA<Retro>());
    expect(back.halt, isA<NoHalt>());
    expect(
      onTheCanvas.halt,
      isA<NoHalt>(),
      reason: 'a parada da checagem subia numa conversa muito depois',
    );
  });
}
