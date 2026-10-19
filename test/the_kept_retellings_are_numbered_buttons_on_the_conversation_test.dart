import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show stateReads;

KeptRetelling aKept(String scope, int turn) => KeptRetelling(
  scope: scope,
  turnNumber: turn,
  audioUrl: 'https://storage.example/kept/$scope-$turn/conto.m4a?sig=$turn',
);

final _buttons = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      RegExp(
        r'^Hear how you told part \d+$',
      ).hasMatch(widget.properties.label ?? ''),
);

List<String?> _labels(WidgetTester tester) => tester
    .widgetList<Semantics>(_buttons)
    .map((button) => button.properties.label)
    .toList();

List<String?> _numerals(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: _buttons, matching: find.byType(Text)),
    )
    .map((text) => text.data)
    .toList();

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(beat);
  }
}

Future<(SalaHarness, ProviderContainer)> atRestAfterATurn(
  WidgetTester tester,
  List<KeptRetelling> kept, {
  String lingua = 'en',
}) async {
  final harness = SalaHarness(lingua: lingua)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = const Moment(
      at: MomentAt.articulation,
      part: 3,
      parts: 3,
    )
    ..room.keptRetellings = kept;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  final readsBefore = stateReads(harness);
  notifier.conversaTap();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.conversaTap();
  await _pumpUntil(tester, () => stateReads(harness) > readsBefore);
  await tester.pump(const Duration(milliseconds: 1500));
  expect(
    container.read(salaSessionProvider).voice,
    VoiceState.invite,
    reason: 'a sala não voltou ao repouso depois do turno',
  );
  return (harness, container);
}

void main() {
  testWidgets(
    'every scene kept shows one numbered button per scene, numbered from one',
    (tester) async {
      await atRestAfterATurn(tester, [
        aKept('S3', 2),
        aKept('S1', 4),
        aKept('S2', 6),
        aKept('whole', 8),
      ]);

      expect(
        _labels(tester),
        [
          'Hear how you told part 1',
          'Hear how you told part 2',
          'Hear how you told part 3',
        ],
        reason: 'os botões não vieram um por cena, na ordem da passagem',
      );
      expect(_numerals(tester), ['1', '2', '3']);
    },
  );

  testWidgets(
    'two scenes of three kept show nothing, and a whole telling does not stand for the third',
    (tester) async {
      final (_, container) = await atRestAfterATurn(tester, [
        aKept('S1', 2),
        aKept('S2', 4),
        aKept('whole', 6),
      ]);

      expect(
        container.read(salaSessionProvider).keptRetellings,
        hasLength(3),
        reason: 'a leitura nem trouxe os takes: o teste não provaria nada',
      );
      expect(
        _buttons,
        findsNothing,
        reason: 'duas cenas de três mostravam botões antes da terceira',
      );
    },
  );

  testWidgets('no kept retelling shows no button', (tester) async {
    await atRestAfterATurn(tester, const []);

    expect(_buttons, findsNothing);
  });
}
