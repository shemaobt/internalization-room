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

void main() {
  testWidgets(
    'the bead row paints translucent, solid, drained and the current ring',
    (tester) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BeadRow(
              entries: const [
                BeadRowEntry(
                  fill: BeadFill.translucent,
                  semanticLabel: 'Parte 1',
                ),
                BeadRowEntry(fill: BeadFill.solid, semanticLabel: 'Parte 2'),
                BeadRowEntry(fill: BeadFill.drained, semanticLabel: 'Parte 3'),
                BeadRowEntry(
                  fill: BeadFill.translucent,
                  current: true,
                  semanticLabel: 'Parte 4',
                ),
              ],
              onTap: (index) => tapped = index,
            ),
          ),
        ),
      );

      final boxes = _beadBoxes(tester);
      expect(boxes, hasLength(4));

      expect(boxes[0].decoration, isA<BoxDecoration>());
      final translucent = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidget(boxes[0]),
              matching: find.byType(Opacity),
            ),
          )
          .first;
      expect(translucent.opacity, 0.3);
      expect((boxes[0].decoration as BoxDecoration).gradient, BeadStyles.wood);

      final solid = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidget(boxes[1]),
              matching: find.byType(Opacity),
            ),
          )
          .first;
      expect(solid.opacity, 1);
      expect((boxes[1].decoration as BoxDecoration).gradient, BeadStyles.wood);

      final drained = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidget(boxes[2]),
              matching: find.byType(Opacity),
            ),
          )
          .first;
      expect(drained.opacity, 1);
      expect(
        (boxes[2].decoration as BoxDecoration).gradient,
        BeadStyles.oat(SalaColors.light),
      );

      final currentOne = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidget(boxes[3]),
              matching: find.byType(Opacity),
            ),
          )
          .first;
      expect(
        currentOne.opacity,
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
      final ringSize = tester.getSize(find.byWidget(rings.first));
      expect(ringSize, const Size(40, 40));
      final ringBorder =
          (rings.first.decoration as BoxDecoration).border as Border;
      expect(ringBorder.top.color, ShemaBrand.telha);
      expect(ringBorder.top.width, 2.5);

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
}
