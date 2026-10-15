import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/presentation/widgets/passage_ruler.dart';

void main() {
  Future<void> pumpRuler(
    WidgetTester tester, {
    required int total,
    required int at,
    required List<int> aimed,
    required List<int> settled,
    Set<int> approved = const {},
    int? current,
    String language = 'pt',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: PassageRuler(
                total: total,
                at: at,
                approved: approved,
                current: current,
                onAim: aimed.add,
                onSettle: () => settled.add(at),
                language: language,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the finger runs the row both ways', (tester) async {
    final aimed = <int>[];
    final settled = <int>[];
    await pumpRuler(tester, total: 14, at: 7, aimed: aimed, settled: settled);

    await tester.drag(find.byType(PassageRuler), const Offset(120, 0));
    await tester.pump();
    final forward = aimed.last;

    aimed.clear();
    await tester.drag(find.byType(PassageRuler), const Offset(-120, 0));
    await tester.pump();

    expect(forward, greaterThan(7));
    expect(
      aimed.last,
      lessThan(forward),
      reason: 'voltar uma passagem custava dar a volta inteira na roda',
    );
  });

  testWidgets('the row stops at its ends', (tester) async {
    final aimed = <int>[];
    final settled = <int>[];
    await pumpRuler(tester, total: 5, at: 2, aimed: aimed, settled: settled);

    await tester.drag(find.byType(PassageRuler), const Offset(900, 0));
    await tester.pump();
    expect(aimed.last, 4);

    await tester.drag(find.byType(PassageRuler), const Offset(-900, 0));
    await tester.pump();
    expect(aimed.last, 0);
  });

  testWidgets('the room is asked to speak once, when the finger lifts', (
    tester,
  ) async {
    final aimed = <int>[];
    final settled = <int>[];
    await pumpRuler(tester, total: 14, at: 0, aimed: aimed, settled: settled);

    await tester.drag(find.byType(PassageRuler), const Offset(300, 0));
    await tester.pump();

    expect(aimed.length, greaterThan(1), reason: 'o marcador acompanha o dedo');
    expect(
      settled,
      hasLength(1),
      reason: 'nomear cada entalhe atravessado seria gaguejar catorze áudios',
    );
  });

  testWidgets('a row of one still shows where the team is', (tester) async {
    final aimed = <int>[];
    final settled = <int>[];
    await pumpRuler(tester, total: 1, at: 0, aimed: aimed, settled: settled);

    expect(find.byType(PassageRuler), findsOneWidget);
    expect(
      tester.getSize(find.byType(PassageRuler)).height,
      PassageRuler.height,
      reason: 'a última passagem do livro ficava sem indicador nenhum',
    );
    expect(
      find.descendant(
        of: find.byType(PassageRuler),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
      reason: 'a última passagem do livro ficava sem indicador nenhum',
    );
  });

  testWidgets('an approved notch wears the olive and the orange dot', (
    tester,
  ) async {
    await pumpRuler(
      tester,
      total: 3,
      at: 2,
      aimed: <int>[],
      settled: <int>[],
      approved: const {0},
    );

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: ShemaBrand.verdeClaro)
        ..circle(x: 30, color: SalaColors.light.telha, radius: 3)
        ..circle(color: SalaColors.light.telha, radius: 9),
    );
  });

  testWidgets('the entry the team left is tinted blue-green', (tester) async {
    await pumpRuler(
      tester,
      total: 3,
      at: 2,
      aimed: <int>[],
      settled: <int>[],
      current: 1,
    );

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: ShemaBrand.azul, strokeWidth: 3),
    );
  });

  testWidgets('an approved passage the team just left is blue-green and '
      'keeps its dot', (tester) async {
    await pumpRuler(
      tester,
      total: 3,
      at: 2,
      aimed: <int>[],
      settled: <int>[],
      approved: const {1},
      current: 1,
    );

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: ShemaBrand.azul, strokeWidth: 3)
        ..circle(color: SalaColors.light.telha, radius: 3),
    );
  });

  testWidgets('a screen reader on an approved passage hears that it has a '
      'saved rehearsal, in the language of the room', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      approved: const {1},
    );
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel(
              RegExp('Escolher a passagem|Choose the passage'),
            ),
          )
          .value,
      '2 de 3, tem um ensaio salvo',
    );

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      approved: const {1},
      language: 'en',
    );
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel(
              RegExp('Escolher a passagem|Choose the passage'),
            ),
          )
          .value,
      '2 of 3, has a saved rehearsal',
    );

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      approved: const {0},
    );
    expect(
      tester
          .getSemantics(
            find.bySemanticsLabel(
              RegExp('Escolher a passagem|Choose the passage'),
            ),
          )
          .value,
      '2 de 3',
    );
    handle.dispose();
  });

  testWidgets('a screen reader on the passage the team just left hears it is '
      'the current one, in the language of the room', (tester) async {
    final handle = tester.ensureSemantics();
    final ruler = find.bySemanticsLabel(
      RegExp('Escolher a passagem|Choose the passage'),
    );

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      current: 1,
    );
    expect(tester.getSemantics(ruler).value, '2 de 3, passagem atual');

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      current: 1,
      language: 'en',
    );
    expect(tester.getSemantics(ruler).value, '2 of 3, current passage');

    await pumpRuler(
      tester,
      total: 3,
      at: 1,
      aimed: <int>[],
      settled: <int>[],
      approved: const {1},
      current: 1,
    );
    expect(
      tester.getSemantics(ruler).value,
      '2 de 3, passagem atual, tem um ensaio salvo',
    );
    handle.dispose();
  });
}
