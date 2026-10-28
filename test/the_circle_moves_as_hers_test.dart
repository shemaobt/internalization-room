import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

const _side = 217.5;

Widget _circle(
  VoiceState voice, {
  required bool canvas,
  bool peerCue = false,
  bool still = false,
  Key? key,
}) => MaterialApp(
  key: key ?? ValueKey('$voice-$canvas-$peerCue-$still'),
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: Scaffold(
      body: Center(
        child: FacilitatorCircle(
          size: _side,
          voice: voice,
          peerCue: peerCue,
          canvas: canvas,
          semanticLabel: 'circulo',
          onTap: () {},
        ),
      ),
    ),
  ),
);

final _ring = find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
      (widget.decoration! as BoxDecoration).gradient != null &&
      ((widget.decoration! as BoxDecoration).border != null ||
          (widget.decoration! as BoxDecoration).boxShadow != null),
);

double _scaleAbove(WidgetTester tester, Finder what) => tester
    .widgetList<Transform>(
      find.ancestor(of: what, matching: find.byType(Transform)),
    )
    .fold(1.0, (scale, move) => scale * move.transform.storage[0]);

void main() {
  testWidgets('her canvas circle rests on a 6.5 s breath that reaches 1.035, '
      'at invite, at done and while the team talks', (tester) async {
    for (final (name, voice, peerCue) in [
      ('invite', VoiceState.invite, false),
      ('done', VoiceState.done, false),
      ('team talk', VoiceState.invite, true),
    ]) {
      await tester.pumpWidget(_circle(voice, canvas: true, peerCue: peerCue));
      expect(_scaleAbove(tester, _ring.first), closeTo(1, 1e-6));

      await tester.pump(const Duration(milliseconds: 3250));
      expect(
        _scaleAbove(tester, _ring.first),
        closeTo(1.035, 1e-6),
        reason:
            '$name respirava em 4,6 s até 1.045; o invite dela é 6,5 s até '
            '1.035 (globals.css:192,195,230)',
      );

      await tester.pump(const Duration(milliseconds: 3250));
      expect(
        _scaleAbove(tester, _ring.first),
        closeTo(1, 1e-6),
        reason: '$name volta ao repouso em 6,5 s, não antes',
      );
    }
  });
}
