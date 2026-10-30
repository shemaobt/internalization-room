import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

Machine _after(Machine machine, List<MachineEvent> events) {
  var now = machine;
  for (final event in events) {
    (now, _) = reduce(now, event);
  }
  return now;
}

void main() {
  test(
    'an ended Canvas left for the recording is still ended when the way back '
    'reaches it',
    () {
      final back = _after(const Machine(station: Canvas()), const [
        StepLeft(ended: true),
        TheRehearsalOpened(),
        TheRecordingLeft(),
      ]);

      expect(back.station, const Canvas());
      expect(
        back.theCanvasEnded,
        isTrue,
        reason: 'a volta da gravação deixava a conversa encerrada no convite',
      );
    },
  );

  test(
    'a step left from the recording or the back-translation keeps the end the '
    'Canvas had, not its own',
    () {
      final back = _after(const Machine(station: Canvas()), const [
        StepLeft(ended: true),
        ThePlanOpened(),
        StepLeft(),
        TheRehearsalOpened(),
        StepLeft(),
        TheRehearsalOpened(),
        TheRecordingLeft(),
      ]);

      expect(back.station, const Canvas());
      expect(back.theCanvasEnded, isTrue);
    },
  );

  test('a Canvas at the invite left for the recording comes back at the '
      'invite', () {
    final back = _after(
      const Machine(station: Canvas(), theCanvasEnded: true),
      const [StepLeft(), TheRehearsalOpened(), TheRecordingLeft()],
    );

    expect(back.theCanvasEnded, isFalse);
  });
}
