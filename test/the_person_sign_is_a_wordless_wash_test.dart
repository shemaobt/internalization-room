import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
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

Future<void> _speakAgain(_Sala sala) async {
  final sent = sala.harness.room.turnsSent;
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _until(
    sala,
    'the microphone to open',
    () => _read(sala).voice == VoiceState.listening,
  );
  await sala.tester.tap(find.byType(FacilitatorCircle));
  await _until(
    sala,
    'the take to go out',
    () => sala.harness.room.turnsSent == sent + 1,
  );
}

List<String?> _wordsOnScreen(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText())
    .toList();

const _everyRefusalThatKeepsTheConversation = <RoomFailure>[
  NetworkFailed('HTTP 502'),
  Refused('TURN_COLLISION'),
  Refused('PIPELINE_REFUSED'),
  Refused('A_CODE_THIS_BUILD_DOES_NOT_KNOW'),
  Refused(RefusalCode.unauthorized),
  Refused(RefusalCode.forbidden),
  Refused(RefusalCode.deviceRevoked),
  Refused(RefusalCode.notFound),
  Refused(RefusalCode.stretchNoLongerCounts),
  Refused(RefusalCode.unreadable),
  Refused(RefusalCode.credentialNotYet),
  Refused(RefusalCode.credentialTaken),
  Refused(RefusalCode.nobodyToReach),
  Refused(RefusalCode.idempotencyKeyInFlight),
  Refused(RefusalCode.passageClosed),
  Refused(RefusalCode.wordlessTelling),
  Refused(RefusalCode.sceneRehearsalSent),
  Refused(RefusalCode.restartOutOfOrder),
  Refused(RefusalCode.tooLarge),
  Refused(RefusalCode.unknownReference),
  Refused(RefusalCode.takeFingerprintDiffers),
  Refused(RefusalCode.takeMoved),
  Refused(RefusalCode.sceneRehearsalSending),
  Refused(RefusalCode.fraseOutOfPlace),
  Refused(RefusalCode.pauseOnlyOnTheLastFrase),
  Refused(RefusalCode.pausePastTheEnd),
  Refused(RefusalCode.pauseCannotStandThere),
  Refused(RefusalCode.sentenceTooLong),
  Refused(RefusalCode.sentenceTooShort),
  Refused(RefusalCode.sentenceFormatDiffers),
  Refused(RefusalCode.anotherSentenceAwaits),
  Refused(RefusalCode.partNotWav),
  Refused(RefusalCode.sentenceIdReused),
  Refused(RefusalCode.nothingToBringBack),
  Refused(RefusalCode.draftApproved),
  Refused(RefusalCode.draftNotApproved),
];

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

      expect(thePersonSign, findsOneWidget);
      expect(_labelsHeard(tester), isNot(contains(_theSign)));
      expect(
        tester
            .getSemantics(
              find
                  .descendant(
                    of: find.byType(PersonSign),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isFalse,
      );
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

      expect(thePersonSign, findsNothing);
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
    'the build guard\'s sign clears by the tap, and the Menu reads nothing',
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

      expect(thePersonSign, findsOneWidget);
      expect(harness.room.calls, isNot(contains('askForAPerson')));

      final asked = harness.room.calls.length;
      await _tapACorner(sala);
      await _pass(sala, 20);

      expect(thePersonSign, findsNothing);
      expect(harness.room.calls.skip(asked), isNot(contains('servedBooks')));
      expect(_read(sala).entriesOpen, isFalse);
      closeTheRoom(container);
    },
  );

  testWidgets('a tap while the sign is still rising clears it, as hers', (
    tester,
  ) async {
    final sala = await _theSignRises(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(PersonSign),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value,
      lessThan(1),
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 50));

    expect(_read(sala).needsPerson, isFalse);
    closeTheRoom(sala.container);
  });

  testWidgets('the sign rises over her 1.6 s with her ease', (tester) async {
    final sala = await _atRestInTheConversation(tester);
    double risen() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(PersonSign),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    sala.container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(risen(), closeTo(0.8024, 0.001));
    await tester.pump(const Duration(milliseconds: 799));
    expect(risen(), lessThan(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(risen(), 1);
    closeTheRoom(sala.container);
  });

  testWidgets(
    'a double tap on the sign clears it, and the second tap reaches the circle as the sign fades, as hers',
    (tester) async {
      final sala = await _underTheSign(tester);
      final circle = tester.getCenter(find.byType(FacilitatorCircle));

      await tester.tapAt(circle);
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byType(PersonSign),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value,
        greaterThan(0),
      );
      await tester.tapAt(circle);
      await _pass(sala, 20);

      expect(_read(sala).needsPerson, isFalse);
      expect(
        _read(sala).voice,
        VoiceState.listening,
        reason:
            'o sinal engolia o toque enquanto sumia, e o dela deixa passar ao círculo',
      );
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

  testWidgets(
    'an outage clears by a tap to the circle at rest with «Ouvir de novo» lit, and the next take goes out as a turn of its own',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      sala.harness.room.failTurnsWith = const NetworkFailed('HTTP 502');
      await _speak(sala);
      await _until(sala, 'the person sign', () => _read(sala).needsPerson);
      await _pass(sala, 20);
      final lostTurn = sala.harness.room.turnIdsSent.last;
      sala.harness.room.failTurnsWith = null;

      await _tapACorner(sala);

      expect(_read(sala).needsPerson, isFalse);
      expect(_hitTestable(_hearAgain), isTrue);

      await _speakAgain(sala);
      await _until(sala, 'the new reply to play', () => _replies(sala) == 2);

      expect(_replies(sala), 2);
      expect(sala.harness.room.turnIdsSent.last, isNot(lostTurn));
      expect(
        sala.harness.room.turnIdsSent.where((id) => id == lostTurn),
        hasLength(1),
        reason: 'a fala perdida na queda voltava a ser mandada atrás da equipe',
      );
      closeTheRoom(sala.container);
    },
  );

  testWidgets(
    'three outages in a row each end in the same wordless sign, and nothing but the acknowledgement is said',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      final voice = sala.harness.voice;
      final linesBefore = voice.fixedLines.length;
      final playedBefore = voice.played.length;
      final assetsBefore = voice.assets.length;
      sala.harness.room.failTurnsWith = const NetworkFailed('HTTP 502');

      for (var outage = 0; outage < 3; outage++) {
        await _speakAgain(sala);
        await _until(sala, 'the person sign', () => _read(sala).needsPerson);
        await _pass(sala, 20);

        expect(thePersonSign, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(PersonSign),
            matching: find.byType(Text),
          ),
          findsNothing,
        );
        await _tapACorner(sala);
      }

      expect(
        voice.fixedLines.skip(linesBefore).map((line) => line.$1),
        [isIn(instantAckLines), isIn(instantAckLines), isIn(instantAckLines)],
        reason:
            'a terceira queda seguida trazia a pausa ou a fala de sem conexão',
      );
      expect(voice.played.skip(playedBefore), isEmpty);
      expect(voice.assets.skip(assetsBefore), isEmpty);
      closeTheRoom(sala.container);
    },
  );

  for (final refusal in _everyRefusalThatKeepsTheConversation) {
    testWidgets('a turn refused with $refusal writes no word on the screen', (
      tester,
    ) async {
      final sala = await _atRestInTheConversation(tester);
      final written = _wordsOnScreen(tester);
      sala.harness.room.failTurnsWith = refusal;

      await _speakAgain(sala);
      await _pass(sala, 40);

      expect(
        _wordsOnScreen(tester),
        written,
        reason: 'uma recusa do servidor chegava à tela da equipe como palavra',
      );
      closeTheRoom(sala.container);
    });
  }

  testWidgets(
    'a turn refused because the passage cannot open lands on the Choice, with no word of a failure',
    (tester) async {
      final sala = await _atRestInTheConversation(tester);
      sala.harness.room.failTurnsWith = const Refused(
        RefusalCode.passageCannotOpen,
      );

      await _speakAgain(sala);
      await _until(
        sala,
        'the Choice',
        () => _read(sala).stage == SalaStage.escolha,
      );
      await _pass(sala, 20);

      expect(_wordsOnScreen(tester), contains('Escolha a passagem'));
      expect(
        _wordsOnScreen(tester),
        isNot(contains(_theSign)),
        reason: 'a recusa escrevia na tela o pedido de uma pessoa',
      );
      closeTheRoom(sala.container);
    },
  );
}
