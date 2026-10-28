import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/language_and_look.dart';
import 'package:internalization_room/features/sala/presentation/widgets/shema_mark.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

final _aLongBook = [
  const Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
    book: 'Ruth',
  ),
  for (var n = 1; n <= 60; n++)
    Passagem(
      pericope: 'P$n',
      audioUrl: '/voice/p$n',
      book: 'Ruth',
      reference: 'Ruth $n:1–22',
    ),
];

const _se = Size(375, 667);
const _seBar = 20.0;

Future<void> _withRealLetters() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      File(
        '$fonts/Roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
}

void _on(WidgetTester tester, Size screen, double bar) {
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
  addTearDown(tester.view.reset);
}

void main() {
  for (final (code, heading) in [
    ('PT', 'Escolha a passagem'),
    ('EN', 'Choose the Passage'),
  ]) {
    testWidgets(
      'on the iPhone SE the sun and moon and the $code pill stand clear '
      'of «$heading» and the mark, not over them',
      (tester) async {
        await tester.runAsync(_withRealLetters);
        _on(tester, _se, _seBar);
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
          closeTo(_se.height * 0.13, 0.1),
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
          pills.top >= _seBar && pills.right <= _se.width,
          isTrue,
          reason: 'as pílulas saíam da tela ou entravam na barra de estado',
        );
        closeTheRoom(container);
      },
    );
  }
}
