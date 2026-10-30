import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart' show ouvir, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show
        antes,
        depois,
        entrarComAFala,
        ouvirAPausa,
        pausarAos,
        s,
        traduzirEConfirmar;

final _umaLacunaAos4e4 = aSpokenWav(gaps: [(s(4.4), s(4.8))]);

const _barraDaFrase1 = 'Ouvir esta frase de novo e traduzir de novo — 1';

Paused _aParteSeguradaEm(ProviderContainer container, Duration pausa) => Paused(
  PartSound(
    0,
    container.read(salaSessionProvider).partes.single.path,
    from: pausa,
  ),
  started: false,
);

double? _ondeOTocadorEsta(WidgetTester tester) {
  final faixa = tester.widget<SceneStrip>(
    find.descendant(
      of: find.byType(PartStrips),
      matching: find.byType(SceneStrip),
    ),
  );
  final painter =
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byWidget(faixa),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!
          as SceneStripPainter;
  return switch (painter.drawing.playhead) {
    final x? => x / faixa.width,
    null => null,
  };
}

Future<ProviderContainer> _pausadaAos4(
  WidgetTester tester,
  SalaHarness harness,
) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await entrarComAFala(tester, harness, _umaLacunaAos4e4);
  await pausarAos(tester, harness, s(4.0));
  expect(container.read(salaSessionProvider).btCorte, s(4.0));
  return container;
}

void main() {
  testWidgets('after «um pouco depois» the held part stands at the moved '
      'pause, and the player\'s line sits on it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _pausadaAos4(tester, harness);

    await tocar(tester, depois);

    expect(container.read(salaSessionProvider).btCorte, s(4.6));
    expect(
      container.read(salaSessionProvider).channel,
      _aParteSeguradaEm(container, s(4.6)),
      reason:
          'a parte segurada ficava onde a gravação tinha parado, não na pausa '
          'movida',
    );
    expect(
      _ondeOTocadorEsta(tester),
      closeTo(0.46, 1e-9),
      reason: 'a linha do tocador não pulava para a pausa movida, como na dela',
    );
    closeTheRoom(container);
  });

  testWidgets('after «um pouco antes» the held part stands at the moved pause', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _pausadaAos4(tester, harness);

    await tocar(tester, antes);

    expect(container.read(salaSessionProvider).btCorte, s(3.6));
    expect(
      container.read(salaSessionProvider).channel,
      _aParteSeguradaEm(container, s(3.6)),
      reason:
          'a parte segurada ficava em 4,0 s depois de mover a pausa para trás',
    );
    closeTheRoom(container);
  });

  testWidgets('«ouvir a pausa» after a nudge still plays the moment before the '
      'moved pause, and the held part comes back at the pause', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _pausadaAos4(tester, harness);
    await tocar(tester, depois);

    await tocar(tester, ouvirAPausa);

    expect(harness.playback.ranges.last, '3100-4600');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(salaSessionProvider).channel,
      _aParteSeguradaEm(container, s(4.6)),
      reason:
          'depois de ouvir a pausa a parte voltava a onde tinha parado, não '
          'à pausa movida',
    );
    expect(_ondeOTocadorEsta(tester), closeTo(0.46, 1e-9));
    closeTheRoom(container);
  });
}
