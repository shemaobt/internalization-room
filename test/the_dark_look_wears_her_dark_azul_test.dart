import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/language_and_look.dart';
import 'package:internalization_room/features/sala/presentation/widgets/mic_clock.dart';
import 'package:internalization_room/features/sala/presentation/widgets/update_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

const _looks = [('light', Color(0xFF89AAA3)), ('dark', Color(0xFF8FB1A9))];

ThemeData _theme(String look) =>
    look == 'dark' ? AppTheme.dark : AppTheme.light;

Future<void> _pump(WidgetTester tester, String look, Widget child) =>
    tester.pumpWidget(
      MaterialApp(
        key: ValueKey(look),
        theme: _theme(look),
        home: Scaffold(body: child),
      ),
    );

const _passages = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
    book: 'Ruth',
  ),
  Passagem(
    pericope: 'P01',
    audioUrl: '/voice/p01',
    book: 'Ruth',
    reference: 'Ruth 1:1–5',
  ),
];

Future<void> _atTheChoice(WidgetTester tester, String look) async {
  tester.platformDispatcher.platformBrightnessTestValue = look == 'dark'
      ? Brightness.dark
      : Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await pumpSala(
    tester,
    SalaHarness(filaEmMemoria: true)..room.passages = _passages,
  );
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

Iterable<BoxDecoration> _paintedUnder<T>(WidgetTester tester, Finder of) =>
    tester
        .widgetList(find.descendant(of: of, matching: find.byType(T)))
        .map(
          (box) => switch (box) {
            Container(:final decoration) => decoration,
            DecoratedBox(:final decoration) => decoration,
            _ => null,
          },
        )
        .whereType<BoxDecoration>();

void main() {
  for (final (look, azul) in _looks) {
    testWidgets(
      'in the $look look the chosen look and the chosen language are filled with her $look azul',
      (tester) async {
        await _atTheChoice(tester, look);

        expect(
          _paintedUnder<Container>(
            tester,
            find.byType(LanguageAndLook),
          ).where((paint) => paint.color == azul),
          hasLength(2),
          reason: 'no escuro o escolhido era pintado com o azul claro',
        );
      },
    );

    testWidgets(
      'in the $look look the panorama on the passage menu is edged in her $look azul',
      (tester) async {
        await _atTheChoice(tester, look);

        expect(
          _paintedUnder<DecoratedBox>(tester, find.byType(EscolhaView))
              .where((paint) => paint.border is Border)
              .map((paint) => (paint.border as Border).top.color),
          contains(azul),
          reason: 'no escuro o panorama tinha a borda azul clara, não a dela',
        );
      },
    );

    testWidgets('in the $look look the mic clock counts in her $look azul', (
      tester,
    ) async {
      await _pump(
        tester,
        look,
        Stack(children: [MicClock(circleSize: 200, since: DateTime.now())]),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(MicClock),
                matching: find.byType(Text),
              ),
            )
            .style
            ?.color,
        azul.withValues(alpha: 0.75),
        reason: 'no escuro o relógio contava no azul claro, não no dela',
      );
    });

    testWidgets(
      'in the $look look a nuance frase wears her $look azul on its bar and its edge',
      (tester) async {
        await _pump(
          tester,
          look,
          FraseList(
            language: 'pt',
            rows: [
              FraseRow(
                n: 1,
                parte: null,
                share: 1,
                onHear: () {},
                achado: BtFindingKind.nuance,
              ),
            ],
          ),
        );
        final painted = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(FraseList),
                matching: find.byType(Container),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>();

        expect(
          painted.where((paint) => paint.color == azul),
          isNotEmpty,
          reason: 'no escuro a barra da nuance era o azul claro, não o dela',
        );
        expect(
          painted.where(
            (paint) =>
                paint.border is Border &&
                (paint.border as Border).top.color == azul,
          ),
          isNotEmpty,
          reason: 'no escuro a borda da nuance era o azul claro, não o dela',
        );
      },
    );

    testWidgets(
      'in the $look look the mark a finding leaves on its frase is written and edged in her $look azul',
      (tester) async {
        await _pump(
          tester,
          look,
          FraseList(
            language: 'pt',
            rows: [
              FraseRow(
                n: 1,
                parte: null,
                share: 1,
                onHear: () {},
                mark: 'nuance',
                achado: BtFindingKind.nuance,
              ),
            ],
          ),
        );

        expect(
          tester.widget<Text>(find.text('nuance')).style?.color,
          azul,
          reason: 'no escuro a marca do achado era escrita no azul claro',
        );
        expect(
          ((tester
                              .widget<Container>(
                                find
                                    .ancestor(
                                      of: find.text('nuance'),
                                      matching: find.byType(Container),
                                    )
                                    .first,
                              )
                              .decoration
                          as BoxDecoration)
                      .border
                  as Border)
              .top
              .color,
          azul,
          reason: 'no escuro a marca do achado tinha a borda azul clara',
        );
      },
    );

    testWidgets(
      'in the $look look the update pill is edged in her $look azul',
      (tester) async {
        await _pump(
          tester,
          look,
          const ProviderScope(child: UpdateView(language: 'pt')),
        );

        expect(
          tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(UpdateView),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .map((box) => box.decoration)
              .whereType<BoxDecoration>()
              .map((paint) => paint.border)
              .whereType<Border>()
              .map((edge) => edge.top.color),
          [azul],
          reason: 'no escuro a pílula de atualizar tinha a borda azul clara',
        );
      },
    );
  }
}
