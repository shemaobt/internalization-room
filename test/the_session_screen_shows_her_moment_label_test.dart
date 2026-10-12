import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

final _label = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      ((widget.properties.label?.startsWith('Momento da sessão') ?? false) ||
          (widget.properties.label?.startsWith('Session moment') ?? false)),
);

String _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _label, matching: find.byType(Text)))
    .map((text) => text.data)
    .join();

Color? _dot(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(of: _label, matching: find.byType(DecoratedBox)),
    )
    .map((box) => box.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.shape == BoxShape.circle)
    .color;

Future<(SalaHarness, ProviderContainer)> _theOpeningSays(
  WidgetTester tester,
  Moment? moment, {
  String lingua = 'pt',
}) async {
  final harness = SalaHarness(lingua: lingua)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = moment;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(pericope: 'P01'));
  await tester.pump(const Duration(milliseconds: 300));
  return (harness, container);
}

void main() {
  testWidgets(
    'the opening of a new session writes the Familiarização in her words and her teal',
    (tester) async {
      await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      expect(
        _label,
        findsOneWidget,
        reason:
            'a voz abriu a Familiarização e a tela não mostrou momento algum',
      );
      expect(_shown(tester), 'Familiarização · a passagem inteira');
      expect(_dot(tester), const Color(0xFF2E6F63));
    },
  );
}
