import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _empty = TheTellingCameBackEmpty();

Machine _afterAnEmptyTelling() =>
    reduce(const Machine(station: Retro()), _empty).$1;

void main() {
  test('An empty telling in the Back-translation shows her line and lets the '
      'pending translation go, with nothing counted or played.', () {
    final (machine, effects) = reduce(const Machine(station: Retro()), _empty);

    expect(machine.wordlessTelling, isTrue);
    expect(effects, const [LetThePendingTranslationGo()]);
  });

  test(
    'An empty telling anywhere but the Back-translation changes nothing.',
    () {
      const onTheCanvas = Machine(station: Canvas());

      final (machine, effects) = reduce(onTheCanvas, _empty);

      expect(machine, same(onTheCanvas));
      expect(effects, isEmpty);
    },
  );

  test('The capture microphone opening clears her line.', () {
    final (machine, _) = reduce(
      _afterAnEmptyTelling(),
      const MicOpened(MicOwner.capture, take: 'retro_1'),
    );

    expect(machine.wordlessTelling, isFalse);
  });

  test('A capture microphone that does not open keeps her line.', () {
    final speaking = _afterAnEmptyTelling().copyWith(
      channel: const GuideSpeaking(Line(LineKind.guide, 1)),
    );

    final (machine, _) = reduce(
      speaking,
      const MicOpened(MicOwner.capture, take: 'retro_1'),
    );

    expect(machine.wordlessTelling, isTrue);
  });

  test('A telling that lands clears her line.', () {
    final (machine, effects) = reduce(
      _afterAnEmptyTelling(),
      const TheTellingLanded(),
    );

    expect(machine.wordlessTelling, isFalse);
    expect(effects, isEmpty);
  });

  test('Leaving the Back-translation clears her line.', () {
    final (machine, _) = reduce(
      _afterAnEmptyTelling(),
      const TheChoiceOpened(),
    );

    expect(machine.wordlessTelling, isFalse);
  });

  test('Arriving again at the Back-translation keeps her line.', () {
    final (machine, _) = reduce(
      _afterAnEmptyTelling(),
      const TheBackTranslationOpened(),
    );

    expect(machine.wordlessTelling, isTrue);
  });
}
