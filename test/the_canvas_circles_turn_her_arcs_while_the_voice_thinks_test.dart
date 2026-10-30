import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/panorama_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show enterThePanorama;

Finder _arcsOn(Type screen) => find.descendant(
  of: find.byType(screen),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ArcPainter,
  ),
);

void main() {
  testWidgets('while the opening is drafted, her two arcs turn round the '
      'conversation\'s circle', (tester) async {
    final harness = SalaHarness(lingua: 'pt')
      ..room.passages = const [
        Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
      ];
    final container = await pumpSala(tester, harness);
    addTearDown(() => closeTheRoom(container));
    SalaSessionState read() => container.read(salaSessionProvider);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.holdNextTurn();
    unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(read().stage, SalaStage.conversa);
    expect(read().voice, VoiceState.thinking);

    expect(
      _arcsOn(ConversaView),
      findsNWidgets(2),
      reason:
          'os 6–10 s da abertura liam como nada acontecendo; o canvas dela '
          'gira os dois arcos em volta do círculo (globals.css:209-212)',
    );
    expect(
      find.descendant(
        of: find.byType(ConversaView),
        matching: find.text('pensando…'),
      ),
      findsOneWidget,
      reason: 'embaixo do círculo ela escreve a espera (page.tsx:1005)',
    );

    harness.room.finishHeldTurn();
    for (
      var beat = 0;
      beat < 30 && read().voice == VoiceState.thinking;
      beat++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets(
    'while the Panorama is drafted, her two arcs turn round its circle',
    (tester) async {
      final harness = SalaHarness(lingua: 'pt')
        ..room.passages = const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/panorama',
            kind: PassagemKind.panorama,
          ),
          Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
        ];
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      SalaSessionState read() => container.read(salaSessionProvider);
      harness.room.holdNextTurn();
      await enterThePanorama(
        container.read(salaSessionProvider.notifier),
        read,
        step: () => tester.pump(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(read().stage, SalaStage.panorama);
      expect(read().voice, VoiceState.thinking);

      expect(
        _arcsOn(PanoramaView),
        findsNWidgets(2),
        reason:
            'o Panorama dela é desenhado no mesmo canvas, com os mesmos arcos',
      );
      expect(
        find.descendant(
          of: find.byType(PanoramaView),
          matching: find.text('pensando…'),
        ),
        findsOneWidget,
      );

      harness.room.finishHeldTurn();
      for (
        var beat = 0;
        beat < 30 && read().voice == VoiceState.thinking;
        beat++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
}
