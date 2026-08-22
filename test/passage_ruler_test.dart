import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/presentation/widgets/passage_ruler.dart';

void main() {
  Future<void> pumpRuler(
    WidgetTester tester, {
    required int total,
    required int at,
    required List<int> aimed,
    required List<int> settled,
    Set<int> started = const {},
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
                started: started,
                onAim: aimed.add,
                onSettle: () => settled.add(at),
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
    expect(aimed.last, lessThan(forward),
        reason: 'voltar uma passagem custava dar a volta inteira na roda');
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

    expect(aimed.length, greaterThan(1),
        reason: 'o marcador acompanha o dedo');
    expect(settled, hasLength(1),
        reason: 'nomear cada entalhe atravessado seria gaguejar catorze áudios');
  });

  testWidgets('a row of one still shows where the team is', (tester) async {
    final aimed = <int>[];
    final settled = <int>[];
    await pumpRuler(tester, total: 1, at: 0, aimed: aimed, settled: settled);

    expect(find.byType(PassageRuler), findsOneWidget);
    expect(tester.getSize(find.byType(PassageRuler)).height, PassageRuler.height,
        reason: 'a última passagem do livro ficava sem indicador nenhum');
    expect(
      find.descendant(
        of: find.byType(PassageRuler),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
      reason: 'a última passagem do livro ficava sem indicador nenhum',
    );
  });
}
