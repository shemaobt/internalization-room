import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/checagem_externa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/circle_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaCasa;
import 'fakes.dart' show SalaHarness, closeTheRoom;
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart' show entrarNaTraducao;
import 'the_circle_glyphs_are_hers_test.dart' show paintedGlyph;

Finder _drawnOn(Type screen, bool Function(Widget widget) drawn) =>
    find.descendant(
      of: find.byType(screen),
      matching: find.byWidgetPredicate(drawn),
    );

bool _anArc(Widget widget) =>
    widget is CustomPaint && widget.painter is ArcPainter;

bool _aGlyph(Widget widget) =>
    widget is CustomPaint && widget.painter is CircleGlyphPainter;

Finder _theCircleOn(Type screen) => find.descendant(
  of: find.byType(screen),
  matching: find.byType(FacilitatorCircle),
);

void _noLoudspeakerInVoiceTime(WidgetTester tester, Type screen, String hers) {
  final circle = tester.widget<FacilitatorCircle>(_theCircleOn(screen));
  expect(
    [circle.voice == VoiceState.thinking, circle.halt is Blocking],
    [false, false],
    reason: 'o círculo precisa estar no tempo da voz para o teste dizer algo',
  );
  expect(
    find.descendant(
      of: _theCircleOn(screen),
      matching: paintedGlyph(CircleGlyph.sound),
    ),
    findsNothing,
    reason:
        'o círculo de checagem dela não desenha glifo nenhum ($hers); o '
        'alto-falante é só do canvas',
  );
}

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

  testWidgets('the Retro circle in voice time draws no loudspeaker, as her '
      'back-translation circle draws none', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);

    _noLoudspeakerInVoiceTime(tester, RetroView, 'Drafting.tsx:2405');
    closeTheRoom(container);
  });
  testWidgets(
    'the external check circle in voice time draws no loudspeaker, as her '
    'external check circle draws none',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await aprovadaNaCasa(tester, harness);
      await tester.ensureVisible(byLabel('Checagem externa').first);
      await tester.tap(byLabel('Checagem externa').first, warnIfMissed: false);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(container.read(salaSessionProvider).stage, SalaStage.checagem);
      await tester.ensureVisible(byLabel('Novo ouvinte').first);
      await tester.tap(byLabel('Novo ouvinte').first, warnIfMissed: false);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      _noLoudspeakerInVoiceTime(
        tester,
        ChecagemExternaView,
        'ExternalCheck.tsx:426',
      );
      closeTheRoom(container);
    },
  );
}
