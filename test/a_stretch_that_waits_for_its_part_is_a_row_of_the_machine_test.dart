import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _onTheBackTranslation = Machine(station: Retro());

Machine _aStretchWaits() =>
    reduce(_onTheBackTranslation, const TheTellingWaitsForItsPart()).$1;

void main() {
  test('on the Back-translation a stretch that waits for its part keeps its '
      'translation and shows no «não entendi»', () {
    final (machine, effects) = reduce(
      _onTheBackTranslation,
      const TheTellingWaitsForItsPart(),
    );

    expect(machine.wordlessTelling, isFalse);
    expect(machine.aStretchWaitsForItsPart, isTrue);
    expect(effects, isNot(contains(const LetThePendingTranslationGo())));
  });

  test('a part named while a stretch waits sends the held stretch once', () {
    final (named, effects) = reduce(_aStretchWaits(), const APartWasNamed());
    final (namedAgain, again) = reduce(named, const APartWasNamed());
    final (_, withNoneWaiting) = reduce(
      _onTheBackTranslation,
      const APartWasNamed(),
    );

    expect(effects, const [TellTheHeldStretch()]);
    expect(named.aStretchWaitsForItsPart, isFalse);
    expect(again, isEmpty);
    expect(namedAgain.aStretchWaitsForItsPart, isFalse);
    expect(withNoneWaiting, isEmpty);
  });

  test('a telling turned away on the Back-translation lets its translation go '
      'and leaves a halt that calls a person waiting for the Conversation', () {
    final (machine, effects) = reduce(
      _onTheBackTranslation,
      const TheTellingWasTurnedAway(),
    );

    expect(machine.aHaltWaitsForTheCanvas?.callsForAPerson, isTrue);
    expect(effects, contains(const LetThePendingTranslationGo()));
    expect(machine.wordlessTelling, isFalse);
    expect(machine.halt, const NoHalt());
  });

  test(
    'leaving the Back-translation drops a stretch that waits for its part',
    () {
      final (away, _) = reduce(
        _aStretchWaits(),
        const TheExternalCheckOpened(1),
      );
      final (back, _) = reduce(away, const TheExternalCheckLeft());

      final (_, effects) = reduce(back, const APartWasNamed());

      expect(back.station, isA<Retro>());
      expect(effects, isEmpty);
    },
  );

  test('a stretch that waits for its part is dropped once its translation is '
      'let go', () {
    final (letGo, _) = reduce(
      _aStretchWaits(),
      const ThePendingTranslationWasLetGo(),
    );

    final (_, effects) = reduce(letGo, const APartWasNamed());

    expect(letGo.aStretchWaitsForItsPart, isFalse);
    expect(effects, isEmpty);
  });

  test('a halt from a telling turned away outlives a line the room serves, '
      'heard on the Back-translation', () {
    const verdict = Line(LineKind.guide, 1, url: '/voice/veredito');
    final (waiting, _) = reduce(
      const Machine(station: Retro(), channel: GuideSpeaking(verdict)),
      const TheTellingWasTurnedAway(),
    );

    final (heard, _) = reduce(waiting, const PlayerEnded(line: verdict));
    final (onTheCanvas, effects) = reduce(heard, const TheRecordingLeft());

    expect(heard.aHaltWaitsForTheCanvas?.callsForAPerson, isTrue);
    expect(onTheCanvas.halt, isA<Blocking>());
    expect(effects, contains(const CallForAPerson()));
  });
}
