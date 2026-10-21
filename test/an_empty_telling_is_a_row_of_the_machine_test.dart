import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
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

  test('An empty telling on the Canvas changes nothing.', () {
    const onTheCanvas = Machine(station: Canvas());

    final (machine, effects) = reduce(onTheCanvas, _empty);

    expect(machine, same(onTheCanvas));
    expect(effects, isEmpty);
  });

  test('An empty telling in the scene rehearsal asks the frase again and '
      'changes nothing else.', () {
    const onTheScene = Machine(station: SceneRehearsal());

    final (machine, effects) = reduce(onTheScene, _empty);

    expect(machine, same(onTheScene));
    expect(effects, const [AskTheFraseAgain()]);
  });

  test('An empty telling in the scene rehearsal that reads the list again asks '
      'the frase again after the list.', () {
    const onTheScene = Machine(station: SceneRehearsal());

    final (machine, effects) = reduce(
      onTheScene,
      const TheTellingCameBackEmpty(readAgain: true),
    );

    expect(machine, same(onTheScene));
    expect(effects, const [AskTheFraseAgainAfterTheList()]);
  });

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

  test('Asking for the verdict clears her line.', () {
    final (machine, effects) = reduce(
      _afterAnEmptyTelling(),
      const TheVerdictAsked(),
    );

    expect(machine.wordlessTelling, isFalse);
    expect(effects, isEmpty);
  });

  test('Starting the translation over clears her line.', () {
    final (machine, effects) = reduce(
      _afterAnEmptyTelling(),
      const TheTranslationStartedOver(),
    );

    expect(machine.wordlessTelling, isFalse);
    expect(effects, isEmpty);
  });

  test('A halt does not clear her line, raised or tapped away.', () {
    final (halted, _) = reduce(_afterAnEmptyTelling(), const RoomRaisedAHalt());
    expect(halted.halt, isA<Blocking>());
    expect(halted.wordlessTelling, isTrue);

    final (lifted, _) = reduce(halted, const TeamTapped());
    expect(lifted.halt, isA<NoHalt>());
    expect(lifted.wordlessTelling, isTrue);
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
