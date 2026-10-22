import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';
import 'package:internalization_room/features/sala/presentation/widgets/person_sign.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

const _theSign = 'Um momento para uma pessoa';
const _hearAgain = 'Ouvir de novo';
const _leavePassage = 'Escolher outra passagem';
const _redMicrophone = 'ensaio da cena';
const _orangeDot = 'Gravar o ensaio de vocês';

typedef _Sala = ({
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
});

SalaSessionState _read(_Sala sala) => sala.container.read(salaSessionProvider);

Future<void> _until(_Sala sala, String what, bool Function() ready) => waitFor(
  what,
  ready,
  step: () => sala.tester.pump(const Duration(milliseconds: 100)),
);

Future<void> _pass(_Sala sala, [int beats = 3]) async {
  for (var beat = 0; beat < beats; beat++) {
    await sala.tester.pump(const Duration(milliseconds: 100));
  }
}

int _replies(_Sala sala) =>
    sala.harness.voice.played.where((url) => url == turnoUrl).length;

Future<_Sala> _atRestInTheConversation(
  WidgetTester tester, [
  SalaHarness? withThis,
]) async {
  final harness = withThis ?? SalaHarness();
  final container = await pumpSala(tester, harness);
  final sala = (tester: tester, harness: harness, container: container);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await _until(
    sala,
    'the opening to be heard and the room to rest',
    () =>
        _read(sala).sessionId != null &&
        (_read(sala).voice == VoiceState.invite ||
            _read(sala).voice == VoiceState.done) &&
        !_read(sala).awaitingTheGuide &&
        _replies(sala) == 1,
  );
  await _pass(sala, 20);
  return sala;
}

Future<void> _speak(_Sala sala) async {
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _pass(sala);
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _pass(sala);
}

var _heardAtTheSign = 0;

Future<_Sala> _theSignRises(
  WidgetTester tester, [
  SalaHarness? withThis,
]) async {
  final sala = await _atRestInTheConversation(tester, withThis);
  sala.harness.room.failTurnsWith = const Refused('PIPELINE_REFUSED');
  await _speak(sala);
  await _until(sala, 'the person sign', () => _read(sala).needsPerson);
  _heardAtTheSign = sala.harness.voice.played.length;
  sala.harness.room.failTurnsWith = null;
  return sala;
}

Future<_Sala> _underTheSign(
  WidgetTester tester, [
  SalaHarness? withThis,
]) async {
  final sala = await _theSignRises(tester, withThis);
  await _pass(sala, 20);
  return sala;
}

Future<void> _tapACorner(_Sala sala) async {
  await sala.tester.tapAt(const Offset(4, 4));
  await _pass(sala, 20);
}

List<String> _labelsHeard(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

double _opacityOf(Finder what) => find
    .ancestor(of: what, matching: find.byType(AnimatedOpacity))
    .evaluate()
    .map((element) => (element.widget as AnimatedOpacity).opacity)
    .first;

bool _hitTestable(String label) =>
    byLabel(label).hitTestable().evaluate().isNotEmpty;

void main() {
  testWidgets(
    'the sign is a wash with no words, and the circle, the moment label, the dot, the red microphone and the passage button are gone',
    (tester) async {
      final heard = tester.ensureSemantics();
      final sala = await _atRestInTheConversation(
        tester,
        SalaHarness()
          ..room.done = true
          ..room.nextMoment = const Moment(
            at: MomentAt.familiarization,
            parts: 3,
          ),
      );
      await _until(sala, 'a moment', () => _read(sala).moment != null);
      await _pass(sala, 10);
      expect(_opacityOf(find.byType(MomentLabel)), greaterThan(0));
      expect(_opacityOf(byLabel(_orangeDot)), greaterThan(0));
      sala.harness.room.failTurnsWith = const Refused('PIPELINE_REFUSED');
      await _speak(sala);
      await _until(sala, 'the person sign', () => _read(sala).needsPerson);
      _heardAtTheSign = sala.harness.voice.played.length;
      await _pass(sala, 20);

      expect(byLabel(_theSign), findsOneWidget);
      expect(_opacityOf(find.byType(MomentLabel)), 0);
      expect(_opacityOf(byLabel(_orangeDot)), 0);
      expect(
        find.descendant(
          of: find.byType(PersonSign),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      expect(_hitTestable(_redMicrophone), isFalse);
      expect(_hitTestable(_hearAgain), isFalse);
      expect(_hitTestable(_leavePassage), isFalse);
      expect(find.byType(FacilitatorCircle).hitTestable(), findsNothing);
      expect(
        _labelsHeard(tester),
        isNot(
          contains(
            tester
                .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
                .semanticLabel,
          ),
        ),
      );
      expect(sala.harness.voice.played.length, _heardAtTheSign);
      heard.dispose();
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'a tap anywhere on the sign returns to the circle at rest with «Ouvir de novo» lit',
    (tester) async {
      final sala = await _underTheSign(tester);

      await _tapACorner(sala);

      expect(byLabel(_theSign), findsNothing);
      expect(_read(sala).needsPerson, isFalse);
      expect(_hitTestable(_hearAgain), isTrue);
      closeTheRoom(sala.container);
    },
  );

  testWidgets('after the tap «Ouvir de novo» plays the last reply heard', (
    tester,
  ) async {
    final sala = await _underTheSign(tester);
    await _tapACorner(sala);
    expect(_replies(sala), 1);

    await tester.tap(byLabel(_hearAgain));
    await _until(sala, 'the reply to play again', () => _replies(sala) == 2);

    expect(sala.harness.voice.played.last, turnoUrl);
    closeTheRoom(sala.container);
  });

  testWidgets('after the tap the team can leave the passage', (tester) async {
    final sala = await _underTheSign(tester);
    await _tapACorner(sala);

    await tester.tap(byLabel(_leavePassage));
    await _until(
      sala,
      'the Choice',
      () => _read(sala).stage == SalaStage.escolha,
    );

    expect(_read(sala).stage, SalaStage.escolha);
    closeTheRoom(sala.container);
  });

  testWidgets('after the tap the team can speak again', (tester) async {
    final sala = await _underTheSign(tester);
    final refusedTurn = sala.harness.room.turnIdsSent.last;
    await _tapACorner(sala);

    await tester.tap(find.byType(FacilitatorCircle));
    await _until(
      sala,
      'the microphone to open',
      () => _read(sala).voice == VoiceState.listening,
    );
    await tester.tap(find.byType(FacilitatorCircle));
    await _until(
      sala,
      'the next turn to go out',
      () => sala.harness.room.turnIdsSent.last != refusedTurn,
    );

    expect(
      sala.harness.room.turnIdsSent.where((id) => id == refusedTurn),
      hasLength(1),
    );
    closeTheRoom(sala.container);
  });

  testWidgets(
    'the build guard\'s sign clears by the tap, and the Menu reads the Wheel',
    (tester) async {
      final harness = SalaHarness()
        ..room.failWith = const Refused('BAD_REQUEST');
      final container = await pumpSala(tester, harness);
      final sala = (tester: tester, harness: harness, container: container);
      final notifier = container.read(salaSessionProvider.notifier);
      unawaited(notifier.abrirEscolha());
      await _until(sala, 'the Wheel left unread', () => _read(sala).rodaPorLer);
      harness.room.failWith = null;

      notifier.haltForABrokenBuild();
      await _pass(sala, 20);

      expect(byLabel(_theSign), findsOneWidget);
      expect(harness.room.calls, isNot(contains('askForAPerson')));

      await _tapACorner(sala);

      expect(byLabel(_theSign), findsNothing);
      await _until(
        sala,
        'the books to be listed',
        () => _read(sala).entriesOpen,
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a tap while the sign is still rising leaves it standing', (
    tester,
  ) async {
    final sala = await _theSignRises(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_read(sala).needsPerson, isTrue);

    await _pass(sala, 20);
    await _tapACorner(sala);

    expect(_read(sala).needsPerson, isFalse);
    closeTheRoom(sala.container);
  });

  testWidgets(
    'a double tap on the sign clears it and never opens the microphone',
    (tester) async {
      final sala = await _underTheSign(tester);
      final circle = tester.getCenter(find.byType(FacilitatorCircle));

      await tester.tapAt(circle);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(circle);
      await _pass(sala, 20);

      expect(_read(sala).needsPerson, isFalse);
      expect(_read(sala).voice, isNot(VoiceState.listening));
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'the circle leaves what VoiceOver hears as soon as the sign starts to rise',
    (tester) async {
      final heard = tester.ensureSemantics();
      final sala = await _theSignRises(tester);
      final label = tester
          .widget<FacilitatorCircle>(find.byType(FacilitatorCircle))
          .semanticLabel;

      await tester.pump(const Duration(milliseconds: 16));

      expect(_labelsHeard(tester), isNot(contains(label)));
      heard.dispose();
      closeTheRoom(sala.container);
    },
  );
}
