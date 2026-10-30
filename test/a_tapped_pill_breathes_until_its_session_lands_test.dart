import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show enterThePassage, settle;

const _p01 = Passagem(
  pericope: 'P01',
  audioUrl: '/voice/p01',
  book: 'Ruth',
  reference: 'Ruth 1:1–5',
);
const _p02 = Passagem(
  pericope: 'P02',
  audioUrl: '/voice/p02',
  book: 'Ruth',
  reference: 'Ruth 1:6–14',
);
const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
  book: 'Ruth',
);
const _tapped = 'Rute 1:6–14';
const _other = 'Rute 1:1–5';

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

Future<ProviderContainer> _tapWhileTheRoomHolds(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await _catchUp(tester);
  harness.room.holdNextCreate();
  await tester.tap(find.text(_tapped));
  await _catchUp(tester);
  return container;
}

SalaHarness _aRoom() =>
    SalaHarness(filaEmMemoria: true)..room.passages = [_p01, _p02];

Iterable<double> _opacityOf(WidgetTester tester, String words) => find
    .ancestor(of: find.text(words), matching: find.byType(Opacity))
    .evaluate()
    .map((element) => (element.widget as Opacity).opacity);

void main() {
  testWidgets('a tapped pill breathes and the others rest at .45 and do not '
      'answer, while the team stays on the Choice', (tester) async {
    final harness = _aRoom();
    final container = await _tapWhileTheRoomHolds(tester, harness);
    final read = container.read(salaSessionProvider);

    expect(harness.room.createHeld, isTrue);
    expect(read.stage, SalaStage.escolha);
    expect(find.text(_tapped), findsOneWidget);
    expect(_opacityOf(tester, _other), contains(0.45));

    final seen = <double>{};
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      seen.add(_opacityOf(tester, _tapped).first);
    }
    expect(seen.length, greaterThan(1));
    expect(seen, everyElement(inInclusiveRange(0.62, 1.0)));
    expect(_opacityOf(tester, _tapped), isNot(contains(0.45)));

    final asked = harness.room.calls.where((c) => c == 'createSession').length;
    await tester.tap(find.text(_other), warnIfMissed: false);
    await _catchUp(tester);
    expect(harness.room.calls.where((c) => c == 'createSession').length, asked);
  });

  testWidgets('when the session lands the canvas opens and the pills rest', (
    tester,
  ) async {
    final harness = _aRoom();
    final container = await _tapWhileTheRoomHolds(tester, harness);

    harness.room.finishHeldCreate();
    await _catchUp(tester);
    final read = container.read(salaSessionProvider);

    expect(read.station, isA<Canvas>());
    expect(read.stage, SalaStage.conversa);
    expect(read.sessionId, isNotNull);
    expect(find.text(_tapped), findsNothing);
  });

  testWidgets('a passage the room cannot open leaves the Choice with every '
      'pill at rest and tappable', (tester) async {
    final harness = _aRoom()..room.passagesThatCannotOpen = {'P02'};
    final container = await _tapWhileTheRoomHolds(tester, harness);

    harness.room.finishHeldCreate();
    await _catchUp(tester);
    final read = container.read(salaSessionProvider);

    expect(read.station, isA<Menu>());
    expect(read.stage, SalaStage.escolha);
    expect(read.theEntryOpening, isNull);
    expect(_opacityOf(tester, _tapped), everyElement(1.0));
    expect(_opacityOf(tester, _other), everyElement(1.0));
  });

  testWidgets('a Panorama pill tapped breathes on the Choice too until its '
      'session lands', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.passages = [_panorama, _p01, _p02];
    final container = await pumpSala(tester, harness);
    await _catchUp(tester);
    harness.room.holdNextCreate();
    await tester.tap(find.text('◈ Panorama do Livro'));
    await _catchUp(tester);
    final read = container.read(salaSessionProvider);

    expect(read.theEntryOpening, _panorama);
    expect(read.stage, SalaStage.escolha);
    expect(_opacityOf(tester, _other), contains(0.45));
  });

  test(
    'a passage the room refuses leaves no entry marked as opening',
    () async {
      final harness = SalaHarness()
        ..room.passages = [_p01, _p02]
        ..room.passagesThatCannotOpen = {'P02'};
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePassage(notifier, read, 'P02');
      await waitFor(
        'the Choice to come back',
        () =>
            harness.room.calls.contains('createSession') &&
            read().station is Menu &&
            read().entriesOpen,
      );
      await settle();

      expect(read().openingEntry, isNull);
    },
  );
}
