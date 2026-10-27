import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _theBook = [
  _panorama,
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
  Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
];

void main() {
  test('a passage the room refuses to open returns the team to the passage '
      'choice with the entry in place and tappable', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.passagesThatCannotOpen = {'P02'};
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P02');
    await waitFor(
      'the room to answer the tap',
      () => harness.room.calls.contains('createSession'),
    );
    await waitFor(
      'the Choice to come back',
      () => read().station is Menu && read().naRoda != null,
    );
    await settle();

    expect(read().station, isA<Menu>());
    expect(read().needsPerson, isFalse);
    expect(read().naRoda, _theBook);

    expect(read().entriesOpen, isTrue);

    harness.room.passagesThatCannotOpen = {};
    await enterThePassage(notifier, read, 'P02');
    await waitFor('P02 to open', () => read().sessionId != null);

    expect(read().station, isA<Canvas>());
    expect(harness.room.pericopesAsked, ['P02']);
  });

  test('a passage the room cannot be reached for leaves the team on the '
      'Choice with the entries live, and the same pill asks again', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await notifier.abrirEscolha();
    await waitFor('the Choice to list its entries', () => read().entriesOpen);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final before = harness.room.calls.length;
    harness.room.reachable = false;

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked',
      () => harness.room.calls.skip(before).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a equipe ficava na tela de uma passagem sem sessão',
    );
    expect(read().entriesOpen, isTrue);
    expect(read().naRoda, _theBook);
    expect(
      harness.room.calls.skip(before),
      ['createSession'],
      reason: 'só a sessão foi pedida; a roda não é lida de novo',
    );

    harness.room.reachable = true;
    notifier.openTheEntry(p02);
    await waitFor('P02 to open', () => read().sessionId != null);

    expect(read().station, isA<Canvas>());
    expect(
      harness.room.calls.skip(before).where((call) => call == 'createSession'),
      hasLength(2),
    );
  });

  test(
    'a Wheel that holds only the Panorama calls nobody and stays on the Choice',
    () async {
      final harness = SalaHarness()..room.passages = const [_panorama];
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.needsPerson, isFalse);
      expect(state.naRoda, [_panorama]);
    },
  );
}
