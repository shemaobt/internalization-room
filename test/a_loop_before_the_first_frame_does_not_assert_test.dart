import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/motion.dart';

void main() {
  testWidgets(
    'a loop mounted before the first frame does not assert, and starts still',
    (tester) async {
      final seen = <double>[];

      tester.binding.attachRootWidget(
        tester.binding.wrapWithDefaultView(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Loop(
              period: const Duration(milliseconds: 4600),
              builder: (context, t) {
                seen.add(t);
                return const SizedBox(width: 10, height: 10);
              },
            ),
          ),
        ),
      );

      // tester.pumpWidget always drives handleBeginFrame before the first build, so
      // schedulerPhase is never idle there. Swapping this back to pumpWidget would
      // make this pass again on a broken motion.dart, silently — it would stop
      // reaching the one case this test is about.
      //
      // The build's own assertion is caught inside ComponentElement.performRebuild
      // and reported to FlutterError, never propagated out of buildScope — so
      // wrapping this call in expect(..., returnsNormally) cannot fail here and
      // was dropped. seen carries the case: build() never reaches widget.builder
      // once the assert fires, so a broken guard leaves seen empty.
      tester.binding.buildOwner!.buildScope(tester.binding.rootElement!);
      expect(
        seen,
        [0.0],
        reason:
            'motion.dart:122 lia currentFrameTimeStamp sem checar a fase do agendador; '
            'sem um frame para medir contra, o primeiro giro fica parado',
      );
    },
  );
}
