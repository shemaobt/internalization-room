import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

Finder _drawnOn(Type screen, bool Function(Widget widget) drawn) =>
    find.descendant(
      of: find.byType(screen),
      matching: find.byWidgetPredicate(drawn),
    );

bool _anArc(Widget widget) =>
    widget is CustomPaint && widget.painter is ArcPainter;

bool _aGlyph(Widget widget) => widget is Icon;

void main() {
  testWidgets(
    'the Choice thinking while its wheel loads keeps the clay breath, with no '
    'arcs and no glyph',
    (tester) async {
      final harness = SalaHarness(lingua: 'pt');
      final container = await pumpSala(tester, harness);
      addTearDown(() => closeTheRoom(container));
      harness.room.holdNextPassages();
      unawaited(container.read(salaSessionProvider.notifier).abrirEscolha());
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(salaSessionProvider).voice, VoiceState.thinking);

      expect(
        _drawnOn(EscolhaView, _anArc),
        findsNothing,
        reason:
            'a Escolha dela é uma lista de texto, sem círculo nem arcos '
            '(page.tsx:985-990); os arcos são só do canvas',
      );
      expect(_drawnOn(EscolhaView, _aGlyph), findsNothing);

      harness.room.finishHeldPassages();
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'the claim code being prepared keeps the clay breath, with no arcs and no '
    'glyph',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: CodigoView(language: 'pt')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        _drawnOn(CodigoView, _anArc),
        findsNothing,
        reason: 'o código do aparelho não tem par na tela dela',
      );
      expect(_drawnOn(CodigoView, _aGlyph), findsNothing);
    },
  );
}
