import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

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

Future<void> _theNextReplySays(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
  Moment moment,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.room.nextMoment = moment;
  harness.voice.holdNextLine();
  notifier.conversaTap();
  await tester.pump(const Duration(milliseconds: 300));
  notifier.conversaTap();
  for (var vez = 0; vez < 30; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (container.read(salaSessionProvider).voice == VoiceState.speaking) {
      break;
    }
  }
  expect(container.read(salaSessionProvider).voice, VoiceState.speaking);
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

  testWidgets(
    'the reply that opens scene two turns the label violet as it starts to play',
    (tester) async {
      final (harness, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      await _theNextReplySays(
        tester,
        harness,
        container,
        const Moment(at: MomentAt.internalization, part: 2, parts: 3),
      );

      expect(
        _shown(tester),
        'Internalização · cena 2 de 3',
        reason: 'a voz abriu a cena 2 e a tela ficou na Familiarização',
      );
      expect(_dot(tester), const Color(0xFF6A4C9C));
    },
  );

  testWidgets(
    'the reply that carries the practice of scene three turns the label red',
    (tester) async {
      final (harness, container) = await _theOpeningSays(
        tester,
        const Moment(at: MomentAt.internalization, part: 3, parts: 3),
      );

      await _theNextReplySays(
        tester,
        harness,
        container,
        const Moment(at: MomentAt.articulation, part: 3, parts: 3),
      );

      expect(
        _shown(tester),
        'Articulação · cena 3 de 3',
        reason:
            'a voz deu o ensaio da cena 3 e a tela seguiu na Internalização',
      );
      expect(_dot(tester), const Color(0xFFC8321E));
    },
  );
}
