import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _greenCheck = 'Terminar a conversa e ir para o ensaio';

Future<ProviderContainer> _inConversa(
  WidgetTester tester,
  Moment moment,
) async {
  final harness = SalaHarness(filaEmMemoria: true)..room.nextMoment = moment;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 2));
  expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  expect(container.read(salaSessionProvider).moment?.at, moment.at);
  return container;
}

const _redMicrophone = 'ensaio da cena';

double _opacityOf(WidgetTester tester, Finder control) => tester
    .widgetList<AnimatedOpacity>(
      find.ancestor(of: control, matching: find.byType(AnimatedOpacity)),
    )
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

bool _takesNoTouch(WidgetTester tester, Finder control) => tester
    .widgetList<IgnorePointer>(
      find.ancestor(of: control, matching: find.byType(IgnorePointer)),
    )
    .any((pointer) => pointer.ignoring);

Finder get _controlsOffered => find
    .descendant(
      of: find.byType(ConversaView),
      matching: find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onTap != null,
      ),
    )
    .hitTestable();

const _lastSceneBeforeTheSendOff = Moment(
  at: MomentAt.articulation,
  part: 3,
  parts: 3,
);

Finder get _checkGlyph => find.descendant(
  of: find.byType(ConversaView),
  matching: find.byIcon(LucideIcons.check),
);

void main() {
  testWidgets(
    'a session in the Familiarização draws no green check under the circle',
    (tester) async {
      await _inConversa(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      expect(
        byLabel(_greenCheck),
        findsNothing,
        reason:
            'o check verde levava a equipe para a gravação a qualquer hora, '
            'pulando os momentos que ela construiu',
      );
      expect(_checkGlyph, findsNothing);
    },
  );

  testWidgets(
    'a scene\'s Articulação offers the red microphone to rehearse it, not a green check',
    (tester) async {
      await _inConversa(
        tester,
        const Moment(at: MomentAt.articulation, part: 2, parts: 3),
      );

      final microphone = byLabel(_redMicrophone);
      expect(microphone, findsOneWidget);
      expect(
        _opacityOf(tester, microphone),
        greaterThan(0),
        reason:
            'na Articulação da cena a equipe ensaia pelo microfone vermelho',
      );
      expect(_takesNoTouch(tester, microphone), isFalse);
      expect(
        byLabel(_greenCheck),
        findsNothing,
        reason:
            'ao lado do microfone vermelho ficava o check verde, que pulava '
            'o ensaio da cena e ia direto para a gravação da passagem',
      );
      expect(_checkGlyph, findsNothing);
    },
  );

  testWidgets(
    'before the send-off no touch on the conversation reaches the recording of the whole passage',
    (tester) async {
      await _inConversa(tester, _lastSceneBeforeTheSendOff);
      final offered = _controlsOffered.evaluate().length;
      expect(
        offered,
        greaterThan(1),
        reason: 'sem os controles da conversa este caso não toca em nada',
      );

      for (var control = 0; control < offered; control++) {
        await tester.pumpWidget(const SizedBox.shrink());
        final container = await _inConversa(tester, _lastSceneBeforeTheSendOff);
        expect(container.read(salaSessionProvider).endOfThePassage, isFalse);

        await tester.tap(_controlsOffered.at(control));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          container.read(salaSessionProvider).stage,
          isNot(SalaStage.ensaio),
          reason:
              'o controle $control da conversa levava a equipe à gravação da '
              'passagem inteira antes da despedida da voz',
        );
      }
    },
  );

  testWidgets(
    'the circle stands in the middle of the conversation, with no empty space kept above or under it',
    (tester) async {
      await _inConversa(
        tester,
        const Moment(at: MomentAt.familiarization, parts: 3),
      );

      final canvas = tester.getRect(find.byType(ConversaView));
      final circle = tester.getRect(
        find.descendant(
          of: find.byType(ConversaView),
          matching: find.byType(FacilitatorCircle),
        ),
      );
      expect(circle.center.dx, closeTo(canvas.center.dx, 0.5));
      expect(
        circle.center.dy,
        closeTo(canvas.center.dy, 0.5),
        reason:
            'a fileira do check embaixo e o vão de 26 px em cima, deixado '
            'pelas fichas que saíram, tiravam o círculo do meio, onde o dela '
            'fica',
      );
    },
  );
}
