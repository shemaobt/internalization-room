import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _partTwo = (session: 's1', scope: 'parte-2');

Machine _after(Machine machine, List<MachineEvent> events) {
  var now = machine;
  for (final event in events) {
    (now, _) = reduce(now, event);
  }
  return now;
}

const _inThePassage = Machine(station: Canvas(), session: 's1');

void main() {
  test(
    "a part is being kept from the keep's start until its row is written",
    () {
      final began = _after(_inThePassage, const [AKeepBegan(_partTwo)]);
      expect(began.beingKept('s1', 'parte-2'), isTrue);

      final written = _after(began, const [
        AKeepEnded(_partTwo, row: 'linha-1'),
      ]);
      expect(written.beingKept('s1', 'parte-2'), isFalse);
    },
  );

  test('a part is saved when the newest take this visit kept of it is the one '
      'the room holds', () {
    final keptTwice = _after(_inThePassage, const [
      AKeepBegan(_partTwo),
      AKeepEnded(_partTwo, row: 'linha-1'),
      AKeepBegan(_partTwo),
      AKeepEnded(_partTwo, row: 'linha-2'),
    ]);

    final (olderHeld, _) = reduce(
      keptTwice,
      const OutboxChanged({
        'linha-1': PartFact.sent,
        'linha-2': PartFact.stranded,
      }),
    );
    expect(olderHeld.savedParts('s1'), isEmpty);
    expect(olderHeld.newestKeptFact('s1', 'parte-2'), PartFact.stranded);

    final (newestHeld, _) = reduce(
      keptTwice,
      const OutboxChanged({'linha-1': PartFact.sent, 'linha-2': PartFact.sent}),
    );
    expect(newestHeld.savedParts('s1'), {'parte-2'});
  });

  test('a part being kept again is never saved', () {
    final (held, _) = reduce(
      _after(_inThePassage, const [
        AKeepBegan(_partTwo),
        AKeepEnded(_partTwo, row: 'linha-1'),
      ]),
      const OutboxChanged({'linha-1': PartFact.sent}),
    );
    expect(held.savedParts('s1'), {'parte-2'});

    final keptAgain = _after(held, const [AKeepBegan(_partTwo)]);

    expect(keptAgain.savedParts('s1'), isEmpty);
    expect(keptAgain.beingKept('s1', 'parte-2'), isTrue);
  });

  test("a part of another session is never saved in this session's", () {
    final (held, _) = reduce(
      _after(_inThePassage, const [
        AKeepBegan(_partTwo),
        AKeepEnded(_partTwo, row: 'linha-1'),
      ]),
      const OutboxChanged({'linha-1': PartFact.sent}),
    );

    expect(held.savedParts('s2'), isEmpty);
    expect(held.beingKept('s2', 'parte-2'), isFalse);
  });

  test('a keep that never wrote its row leaves the part as it was', () {
    final failed = _after(_inThePassage, const [
      AKeepBegan(_partTwo),
      AKeepEnded(_partTwo),
    ]);

    expect(failed.beingKept('s1', 'parte-2'), isFalse);
    expect(failed.keptThisVisit, isEmpty);
  });

  test('a take of an earlier visit sent by its tap is saved once the room '
      'holds it, as a take this visit kept', () {
    final (held, _) = reduce(
      _after(_inThePassage, const [TheTapSent(_partTwo, 'linha-antiga')]),
      const OutboxChanged({'linha-antiga': PartFact.sent}),
    );

    expect(held.savedParts('s1'), {'parte-2'});
    expect(held.beingKept('s1', 'parte-2'), isFalse);
  });
}
