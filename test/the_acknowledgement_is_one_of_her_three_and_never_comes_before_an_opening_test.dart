import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _p01 = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

String _clip(String line) => fixedLineAsset(line, testLanguage);

List<String> _acknowledgementsIn(Iterable<String> assets) => [
  for (final asset in assets)
    if (everyAcknowledgementLineTheAppEverHad.any(
      (line) => asset == _clip(line),
    ))
      asset,
];

Future<List<String>> _fiftyAcknowledgements() async {
  final harness = SalaHarness();
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  harness.voice.assets.clear();
  for (var turn = 0; turn < 50; turn++) {
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
  }
  return _acknowledgementsIn(harness.voice.assets);
}

void main() {
  group('fifty acknowledgements in a row', () {
    late Future<List<String>> fifty;

    setUpAll(() => fifty = _fiftyAcknowledgements());

    test('are only her three, never the same twice running', () async {
      final heard = await fifty;

      expect(heard, hasLength(50));
      expect(
        heard,
        everyElement(isIn([for (final l in instantAckLines) _clip(l)])),
      );
      expect(heard, isNot(contains(_clip('F3'))));
      for (var i = 1; i < heard.length; i++) {
        expect(heard[i], isNot(heard[i - 1]), reason: 'turn $i repeated');
      }
    });

    test('are picked at random, not rotated', () async {
      final heard = await fifty;

      final comesBackAfterADifferentOne = [
        for (var i = 2; i < heard.length; i++)
          if (heard[i] == heard[i - 2]) i,
      ];
      expect(
        comesBackAfterADifferentOne,
        isNotEmpty,
        reason: 'a fixed rotation of three never goes A, B, A',
      );
    });

    test('let every one of the three be heard', () async {
      final heard = await fifty;

      expect(heard.toSet(), {for (final l in instantAckLines) _clip(l)});
    });
  });

  test('the scene plays with no acknowledgement before it', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    await settle();

    expect(harness.voice.played, isNotEmpty);
    expect(_acknowledgementsIn(harness.voice.assets), isEmpty);
  });

  test('a scene asked again from the Menu after a failed opening plays no '
      'acknowledgement', () async {
    final harness = SalaHarness()
      ..room.failHeldTurnWith = const Refused('BAD_REQUEST');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'a abertura falhar em silêncio',
      () =>
          harness.room.turnIdsAsked.isNotEmpty &&
          read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    harness.voice.assets.clear();

    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'a cena ser dita',
      () => harness.voice.played.contains(turnoUrl),
    );

    expect(harness.room.turnIdsAsked, hasLength(2));
    expect(_acknowledgementsIn(harness.voice.assets), isEmpty);
  });
  test('the panorama\'s opening plays no acknowledgement', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.entrarNaOferecida();
    await settle();

    expect(harness.voice.played, isNotEmpty);
    expect(_acknowledgementsIn(harness.voice.assets), isEmpty);
  });
}
