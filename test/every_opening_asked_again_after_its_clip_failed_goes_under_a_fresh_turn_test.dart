import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
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

void _expectAFreshTurnId(SalaHarness harness) {
  expect(harness.room.turnIdsAsked.length, greaterThanOrEqualTo(2));
  expect(
    harness.room.turnIdsAsked.skip(1),
    everyElement(isNot(harness.room.turnIdsAsked.first)),
    reason:
        'o mesmo id devolve a resposta lembrada, com o clipe que não '
        'existe, e a sala pararia de novo',
  );
}

void main() {
  test('the invitation\'s opening asked again after its clip could not be '
      'fetched goes under a fresh turn id', () async {
    final harness = SalaHarness();
    harness.voice.roomFailsWith = const Refused(RefusalCode.notFound);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await notifier.openConvite();
    await waitFor('a sala parar', () => read().needsPerson);
    await theHaltIsLifted(harness, notifier, read);
    notifier.conviteTap();
    await settle();

    _expectAFreshTurnId(harness);
  });

  test('the panorama\'s opening asked again after its clip could not be '
      'fetched goes under a fresh turn id', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await notifier.abrirEscolha();
    await settle();

    harness.voice.roomFailsWith = const Refused(RefusalCode.notFound);
    notifier.entrarNaOferecida();
    await waitFor('a sala parar', () => read().needsPerson);
    await theHaltIsLifted(harness, notifier, read);
    notifier.entrarNaOferecida();
    await settle();

    _expectAFreshTurnId(harness);
  });
}
