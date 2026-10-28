import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/language_and_look.dart';
import 'package:internalization_room/features/sala/presentation/widgets/pause_adjust_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/shema_mark.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, onAScreen, settle, withRealLetters;
import 'the_back_translation_is_told_by_beads_test.dart'
    show cabeca, entrarNaTraducao, passaDoCursor, pausar;
import 'um_ensaio_de_tres_partes.dart';

final _aLongBook = [
  const Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
    book: 'Ruth',
  ),
  for (var n = 1; n <= 120; n++)
    Passagem(
      pericope: 'P$n',
      audioUrl: '/voice/p$n',
      book: 'Ruth',
      reference: 'Ruth $n:1–22',
    ),
];

const _se = Size(375, 667);
const _seBar = 20.0;

const _tocarOuPausar = 'Tocar ou pausar a gravação';

Rect _theRing(WidgetTester tester) {
  final circle = tester.getRect(
    find.descendant(
      of: find.byType(RetroView),
      matching: find.byType(FacilitatorCircle),
    ),
  );
  return circle.inflate(circle.width * 0.23);
}

void main() {
  for (final (named, screen, bar) in [
    ('the iPhone SE', _se, _seBar),
    ('a 393×852 iPhone', const Size(393, 852), 59.0),
    ('a 430×932 iPhone', const Size(430, 932), 59.0),
    ('the iPhone 16 Pro Max', const Size(440, 956), 62.0),
    ('the iPad', const Size(820, 1180), 24.0),
  ]) {
    for (final (code, heading) in [
      ('PT', 'Escolha a passagem'),
      ('EN', 'Choose the Passage'),
    ]) {
      testWidgets('on $named the sun and moon and the $code pill stand clear '
          'of «$heading» and the mark, not over them', (tester) async {
        await tester.runAsync(withRealLetters);
        onAScreen(tester, screen, bar: bar);
        final container = await pumpSala(
          tester,
          SalaHarness()..room.passages = _aLongBook,
        );
        await tester.runAsync(settle);
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.tap(find.text(code));
        await tester.pump(const Duration(milliseconds: 1500));

        final pills = tester.getRect(
          find
              .descendant(
                of: find.byType(LanguageAndLook),
                matching: find.byType(Column),
              )
              .first,
        );
        final words = tester.getRect(find.text(heading));
        final mark = tester.getRect(
          find.descendant(
            of: find.byType(EscolhaView),
            matching: find.byType(ShemaMark),
          ),
        );
        expect(
          mark.top,
          closeTo(screen.height * 0.13, 0.1),
          reason: 'a lista não enchia a tela e a Escolha ficava no meio',
        );
        expect(
          pills.overlaps(words),
          isFalse,
          reason: 'as pílulas cobriam o fim do título da Escolha',
        );
        expect(
          pills.overlaps(mark),
          isFalse,
          reason: 'as pílulas cobriam a marca',
        );
        expect(
          pills.top >= bar && pills.right <= screen.width,
          isTrue,
          reason: 'as pílulas saíam da tela ou entravam na barra de estado',
        );
        closeTheRoom(container);
      });
    }
  }

  for (final (named, screen) in [
    ('the iPhone SE', _se),
    ('the iPad', const Size(820, 1180)),
  ]) {
    testWidgets('on $named the pause button and the three pause controls '
        'stand outside the check circle\'s ring, not inside it', (
      tester,
    ) async {
      tester.view
        ..physicalSize = screen
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness);
      harness.playback.at = cabeca;
      await tester.pump(passaDoCursor);

      final ring = _theRing(tester);
      expect(
        tester.getRect(find.byType(PauseAdjustRow)).bottom,
        lessThanOrEqualTo(ring.top),
        reason: 'os três controles da pausa tocavam o anel do círculo',
      );
      expect(
        tester.getRect(byLabel(pausar)).top,
        greaterThanOrEqualTo(ring.bottom),
        reason: 'o botão de pausar ficava dentro do anel do círculo',
      );
      closeTheRoom(container);
    });
  }

  testWidgets('on the iPhone SE the first listen\'s line and its pause button '
      'start below the check circle\'s ring, not on it', (tester) async {
    tester.view
      ..physicalSize = _se
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Sala it;
    await tester.runAsync(() async => it = await umEnsaioDeTresPartesGravado());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: it.container,
        child: const SalaApp(),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      it.harness.room.listeningUnheardTakeIds = [
        for (final parte in it.partes) parte.takeId!,
      ];
      final tocadas = it.harness.playback.played.length;
      it.sala.startRetro();
      await waitFor(
        'uma parte entrar no ar',
        () => it.harness.playback.played.length > tocadas,
      );
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 3);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final ring = _theRing(tester);
    expect(
      tester
          .getRect(
            find.textContaining('ouvindo a gravação de vocês… — parte 1 · '),
          )
          .top,
      greaterThanOrEqualTo(ring.bottom),
      reason: 'a linha da escuta encostava no anel do círculo',
    );
    expect(
      tester.getRect(byLabel(_tocarOuPausar)).top,
      greaterThanOrEqualTo(ring.bottom),
      reason: 'o botão de pausar ficava dentro do anel do círculo',
    );
    closeTheRoom(it.container);
  });
}
