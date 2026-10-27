import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

const _telha = Color(0xFFBE4A01);

Future<(SalaHarness, ProviderContainer)> _theOpeningIsDrafted(
  WidgetTester tester, {
  String lingua = 'pt',
}) async {
  final harness = SalaHarness(lingua: lingua)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')];
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  harness.room.holdNextTurn();
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await tester.pump(const Duration(milliseconds: 300));
  return (harness, container);
}

Finder _arcsOn(Type screen) => find.descendant(
  of: find.byType(screen),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ArcPainter,
  ),
);

void main() {
  testWidgets(
    'while the opening is drafted, «pensando…» is written in telha under the '
    'circle, and goes once she speaks',
    (tester) async {
      final (harness, container) = await _theOpeningIsDrafted(tester);
      VoiceState voice() => container.read(salaSessionProvider).voice;
      expect(voice(), VoiceState.thinking);
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);

      final word = find.text('pensando…');
      expect(
        word,
        findsOneWidget,
        reason:
            'os 6–10 s da abertura liam como nada acontecendo; a tela dela '
            'escreve voiceThinking sob o círculo (page.tsx:1005, strings.ts:391)',
      );
      final style = tester.widget<Text>(word).style!;
      expect(
        [style.color, style.fontSize, style.fontWeight, style.letterSpacing],
        [_telha, 16.8, FontWeight.w600, closeTo(1.008, 1e-9)],
        reason: '.think-note dela: telha, 1.05rem, 600, .06em',
      );
      expect(
        tester.getTopLeft(word).dy -
            tester
                .getRect(
                  find.descendant(
                    of: find.byType(ConversaView),
                    matching: find.byType(FacilitatorCircle),
                  ),
                )
                .bottom,
        closeTo(35.2, 0.5),
        reason: 'e 2.2rem abaixo da borda do círculo (globals.css:216)',
      );
      expect(
        find.ancestor(
          of: word,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && (widget.properties.liveRegion ?? false),
          ),
        ),
        findsOneWidget,
        reason: 'role=status: o leitor de tela anuncia que a voz pensa',
      );
      expect(
        _arcsOn(ConversaView),
        findsNWidgets(2),
        reason: 'e os dois arcos dela giram em volta do círculo da conversa',
      );

      harness.room.finishHeldTurn();
      for (var beat = 0; beat < 30 && voice() == VoiceState.thinking; beat++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(voice(), isNot(VoiceState.thinking));
      expect(
        word,
        findsNothing,
        reason: 'a palavra é só do pensar; quando ela fala, sai',
      );
    },
  );

  testWidgets('a room in English writes «thinking…», never the Portuguese', (
    tester,
  ) async {
    final (harness, container) = await _theOpeningIsDrafted(
      tester,
      lingua: 'en',
    );

    expect(
      find.text('thinking…'),
      findsOneWidget,
      reason: 'strings.ts:256 dela, na língua da sala',
    );
    expect(find.text('pensando…'), findsNothing);

    harness.room.finishHeldTurn();
    for (
      var beat = 0;
      beat < 30 &&
          container.read(salaSessionProvider).voice == VoiceState.thinking;
      beat++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets(
    'while the Panorama is drafted, the same word is written under its circle',
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

      final word = find.text('pensando…');
      expect(
        word,
        findsOneWidget,
        reason:
            'o Panorama dela é desenhado no mesmo canvas, com o mesmo '
            'think-note (page.tsx:1005)',
      );
      expect(
        tester.getTopLeft(word).dy -
            tester
                .getRect(
                  find.descendant(
                    of: find.byType(PanoramaView),
                    matching: find.byType(FacilitatorCircle),
                  ),
                )
                .bottom,
        closeTo(35.2, 0.5),
      );
      expect(
        _arcsOn(PanoramaView),
        findsNWidgets(2),
        reason: 'e os dois arcos dela giram em volta do círculo do Panorama',
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
