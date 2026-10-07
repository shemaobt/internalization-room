import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _guide = Line(LineKind.guide, 1);
const _approved = Line(LineKind.approved, 2);
const _acknowledgement = Line(
  LineKind.acknowledgement,
  3,
  source: Source.aside('acknowledgement'),
);
const _part = PartSound(0, 'parte-1.m4a');

const _at = Duration(milliseconds: 2400);
const _of = Duration(milliseconds: 9000);
const _cut = CutPoint(_at, of: _of);
const _interrupted = Interrupted(take: 'conversa_1', cut: _cut);

const _theCut = [
  StopTheSound(),
  OpenTheMic(MicOwner.conversation, take: 'conversa_1'),
];

(Machine, List<Effect>) _run(Machine from, List<MachineEvent> events) {
  var machine = from;
  var effects = <Effect>[];
  for (final event in events) {
    (machine, effects) = reduce(machine, event);
  }
  return (machine, effects);
}

Machine _onTheCanvas(Channel channel, {List<Line> queue = const []}) =>
    Machine(station: const Canvas(), channel: channel, queue: queue);

void main() {
  group('an interruption on the Canvas turns the Guide\'s line into the '
      'conversation\'s microphone, stopping her first', () {
    for (final line in const [_guide, _approved]) {
      test('a ${line.kind.name} line', () {
        final (machine, effects) = reduce(
          _onTheCanvas(GuideSpeaking(line)),
          _interrupted,
        );

        expect(
          machine.channel,
          const Microphone(MicOwner.conversation, cut: _cut),
        );
        expect(effects, _theCut);
        expect(machine.lastLine?.line, line);
        expect(machine.lastLine?.said, Said.cut);
      });
    }
  });

  test('an interruption over the acknowledgement takes the waiting reply out '
      'of the queue and ends it cut', () {
    final (machine, effects) = reduce(
      _onTheCanvas(
        const GuideSpeaking(_acknowledgement),
        queue: const [_guide],
      ),
      _interrupted,
    );

    expect(
      machine.channel,
      const Microphone(MicOwner.conversation, cut: CutPoint(Duration.zero)),
    );
    expect(machine.queue, isNot(contains(_guide)));
    expect(machine.owners.keys, isNot(contains(_guide)));
    expect(machine.lastLine?.line, _guide);
    expect(machine.lastLine?.said, Said.cut);
    expect(effects, _theCut);
  });

  group('an interruption changes nothing when the Guide is not speaking', () {
    final rows = <String, Machine>{
      'silence, the voice thinking': _onTheCanvas(const Silence()),
      'the microphone': _onTheCanvas(const Microphone(MicOwner.conversation)),
      'a part playing': _onTheCanvas(const PartPlaying(_part, opened: true)),
      'the acknowledgement with no reply queued': _onTheCanvas(
        const GuideSpeaking(_acknowledgement),
      ),
      'a blocking halt': const Machine(
        station: Canvas(),
        channel: GuideSpeaking(_guide),
        halt: Blocking(NothingKept()),
      ),
      'the Panorama station': const Machine(
        station: Panorama(),
        channel: GuideSpeaking(_guide),
      ),
    };
    for (final MapEntry(key: row, value: before) in rows.entries) {
      test(row, () {
        final (machine, effects) = reduce(before, _interrupted);

        expect(identical(machine, before), isTrue);
        expect(effects, isEmpty);
      });
    }
  });

  group('the take closed on an interrupted microphone carries its cut, and no '
      'other answer does', () {
    final (interrupted, _) = reduce(
      _onTheCanvas(const GuideSpeaking(_guide)),
      _interrupted,
    );

    test('a closed take carries the cut', () {
      final (machine, _) = reduce(
        interrupted,
        const MicAnswered(MicAnswer.closed, take: 'x'),
      );

      expect(machine.lastMic?.cut, _cut);
    });

    test('a discarded answer carries none', () {
      final (machine, _) = reduce(
        interrupted,
        const MicAnswered(MicAnswer.discarded),
      );

      expect(machine.lastMic?.cut, isNull);
      expect(_cutAnywhere(machine), isFalse);
    });

    test('a microphone the room discards leaves no cut behind', () {
      final (discarded, _) = reduce(interrupted, const MicDiscarded());
      final (machine, _) = reduce(
        discarded,
        const MicAnswered(MicAnswer.closed, take: 'x'),
      );

      expect(_cutAnywhere(discarded), isFalse);
      expect(machine.lastMic?.cut, isNull);
    });

    test('a generation move, then a fresh microphone closed, carries none', () {
      final stale = interrupted.generation;
      final (back, _) = _run(interrupted, const [
        TheChoiceOpened(),
        MicDiscarded(),
        PassageChosen(),
        MicOpened(MicOwner.conversation, take: 'y'),
      ]);
      final (machine, _) = _run(back, [
        MicAnswered(MicAnswer.closed, take: 'x', generation: stale),
        const MicAnswered(MicAnswer.closed, take: 'y'),
      ]);

      expect(machine.lastMic?.take, 'y');
      expect(machine.lastMic?.cut, isNull);
    });
  });
}

bool _cutAnywhere(Machine machine) => switch (machine.channel) {
  Microphone(cut: _?) => true,
  _ => false,
};
