import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';

List<Container> _beadBoxes(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(BeadRow),
        matching: find.byType(Container),
      ),
    )
    .where((box) => (box.decoration as BoxDecoration?)?.gradient != null)
    .toList();

double _opacityAbove(WidgetTester tester, Widget target) => tester
    .widgetList<Opacity>(
      find.ancestor(of: find.byWidget(target), matching: find.byType(Opacity)),
    )
    .first
    .opacity;

List<double> _opacitiesAbove(WidgetTester tester, Widget target) => tester
    .widgetList<Opacity>(
      find.ancestor(of: find.byWidget(target), matching: find.byType(Opacity)),
    )
    .map((o) => o.opacity)
    .toList();

Future<void> _pumpRow(
  WidgetTester tester,
  List<BeadRowEntry> entries,
  ValueChanged<int> onTap, {
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme ?? AppTheme.light,
    home: Scaffold(
      body: BeadRow(entries: entries, onTap: onTap),
    ),
  ),
);

void main() {
  testWidgets(
    'the bead row paints translucent, solid, drained and the current ring',
    (tester) async {
      int? tapped;
      await _pumpRow(tester, const [
        BeadRowEntry(fill: BeadFill.translucent, semanticLabel: 'Parte 1'),
        BeadRowEntry(fill: BeadFill.solid, semanticLabel: 'Parte 2'),
        BeadRowEntry(fill: BeadFill.drained, semanticLabel: 'Parte 3'),
        BeadRowEntry(
          fill: BeadFill.translucent,
          current: true,
          semanticLabel: 'Parte 4',
        ),
      ], (index) => tapped = index);

      final boxes = _beadBoxes(tester);
      expect(boxes, hasLength(4));

      expect(_opacityAbove(tester, boxes[0]), 0.3);
      expect((boxes[0].decoration as BoxDecoration).gradient, BeadStyles.wood);

      expect(_opacityAbove(tester, boxes[1]), 1);
      expect((boxes[1].decoration as BoxDecoration).gradient, BeadStyles.wood);

      expect(_opacityAbove(tester, boxes[2]), 1);
      expect(
        (boxes[2].decoration as BoxDecoration).gradient,
        BeadStyles.oat(SalaColors.light),
      );

      expect(
        _opacityAbove(tester, boxes[3]),
        0.3,
        reason: 'a conta continua translúcida; o anel é que fica opaco',
      );

      for (var i = 0; i < 4; i++) {
        final size = tester.getSize(find.byWidget(boxes[i]));
        expect(size, const Size(28, 28));
      }

      final rings = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(BeadRow),
              matching: find.byType(Container),
            ),
          )
          .where((box) => (box.decoration as BoxDecoration?)?.border != null)
          .toList();
      expect(rings, hasLength(1));
      final ring = rings.first;
      final ringSize = tester.getSize(find.byWidget(ring));
      expect(ringSize, const Size(40, 40));
      final ringBorder = (ring.decoration as BoxDecoration).border as Border;
      expect(ringBorder.top.color, SalaColors.light.telha);
      expect(ringBorder.top.width, 2.5);
      expect(
        _opacitiesAbove(tester, ring).every((o) => o == 1),
        isTrue,
        reason: 'o anel não mora dentro do Opacity(0.3) da conta translúcida',
      );

      await tester.tap(find.byWidget(boxes[2]));
      expect(tapped, 2);

      final labels = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byType(BeadRow),
              matching: find.byType(Semantics),
            ),
          )
          .map((s) => s.properties.label)
          .toList();
      expect(labels, containsAll(['Parte 1', 'Parte 2', 'Parte 3', 'Parte 4']));
    },
  );

  testWidgets('beads sit 16px edge to edge', (tester) async {
    await _pumpRow(tester, const [
      BeadRowEntry(fill: BeadFill.solid, semanticLabel: 'Parte 1'),
      BeadRowEntry(fill: BeadFill.solid, semanticLabel: 'Parte 2'),
    ], (_) {});

    final boxes = _beadBoxes(tester);
    final left = tester.getTopLeft(find.byWidget(boxes[0])).dx;
    final leftRight = left + tester.getSize(find.byWidget(boxes[0])).width;
    final rightLeft = tester.getTopLeft(find.byWidget(boxes[1])).dx;

    expect(
      rightLeft - leftRight,
      16,
      reason: 'a régua da tela pede 28px + 16px de vão, aro por cima',
    );
  });

  testWidgets('the ring follows the theme, not a fixed light-mode colour', (
    tester,
  ) async {
    await _pumpRow(
      tester,
      const [
        BeadRowEntry(
          fill: BeadFill.solid,
          current: true,
          semanticLabel: 'Parte 1',
        ),
      ],
      (_) {},
      theme: AppTheme.dark,
    );

    final ring = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(BeadRow),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (box) => (box.decoration as BoxDecoration?)?.border != null,
        );
    final ringBorder = (ring.decoration as BoxDecoration).border as Border;

    expect(ringBorder.top.color, SalaColors.dark.telha);
    expect(ringBorder.top.color, isNot(ShemaBrand.telha));
  });
}
