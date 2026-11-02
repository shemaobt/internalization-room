import 'dart:async';

import 'dart:ui' show Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show byLabel, enabledFlagOf, isDrawn, thePersonSign;
import 'the_recording_screens_offer_her_way_back_test.dart'
    show onTheFirstListen, onTheGrainChoice, onTheHome, settles;

const _backToPassage = 'Voltar para a passagem atual';
const _backToRecording = 'Voltar para a gravação';
const _whole = 'A passagem inteira';
const _conferindo = 'conferindo…';
const _verdictLine = 'V1';
const _unclear = 'não ficou claro';

Finder _onTheWholeRow(String label) =>
    find.descendant(of: byLabel(_whole), matching: byLabel(label));

bool _drawn(WidgetTester tester, String label) =>
    byLabel(label).evaluate().isNotEmpty && isDrawn(tester, byLabel(label));

bool _takesTheFinger(String label) =>
    byLabel(label).hitTestable().evaluate().isNotEmpty;

bool _enabled(WidgetTester tester, String label) =>
    enabledFlagOf(tester, byLabel(label)) == Tristate.isTrue;

bool _live(WidgetTester tester, String label) =>
    _drawn(tester, label) && _takesTheFinger(label) && _enabled(tester, label);

SalaSessionState _state(ProviderContainer container) =>
    container.read(salaSessionProvider);

SalaSessionNotifier _notifier(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

Future<void> _until(
  WidgetTester tester,
  String what,
  bool Function() done,
) async {
  for (var vez = 0; vez < 100 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: what);
}

Iterable<String> _deletedSince(SalaHarness harness, int from, String kind) =>
    harness.recorder.deleted.skip(from).where((path) => path.contains(kind));

int _stopsAsked(SalaHarness harness) =>
    harness.recorder.sounds.where((sound) => sound == 'recorder:stop').length;

Future<void> _passTenSeconds(WidgetTester tester) async {
  for (var vez = 0; vez < 100; vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Iterable<String> _voicedSince(SalaHarness harness, int from) => harness.sounds
    .skip(from)
    .where((sound) => sound.startsWith('voice:') && sound != 'voice:stop');

Future<(SalaHarness, ProviderContainer)> _onTheBackTranslation(
  WidgetTester tester, {
  void Function(SalaHarness harness)? beforeItOpens,
}) => onTheFirstListen(tester, unheard: false, beforeItOpens: beforeItOpens);

Future<void> _theTellingOpens(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.playback.at = const Duration(seconds: 2);
  _notifier(container).retroTap();
  _notifier(container).retroTap();
  await _until(
    tester,
    'o microfone da tradução abrir',
    () => _state(container).voice == VoiceState.listening,
  );
}

Future<void> _theCheckIsAsked(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.playback.finishPlayback();
  await settles(tester);
  harness.room
    ..verdictChecked = true
    ..verdictFixedLine = _verdictLine
    ..holdNextVerdict();
  addTearDown(harness.room.finishHeldVerdict);
  unawaited(_notifier(container).finishBackTranslation());
  await _until(
    tester,
    'o «conferindo…» aparecer',
    () => find.text(_conferindo).evaluate().isNotEmpty,
  );
}

Future<void> _theHomeTakeRecords(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(_onTheWholeRow('Gravar'));
  await settles(tester);
  expect(_state(container).ensaio, EnsaioStatus.recording);
}

Future<void> _theSignStandsOverTheChevronUntilItClears(
  WidgetTester tester,
  ProviderContainer container,
) async {
  _notifier(container).haltForABrokenBuild();
  await _until(
    tester,
    'o sinal da pessoa aparecer',
    () => _state(container).needsPerson,
  );
  await settles(tester);
  await settles(tester);

  expect(
    _drawn(tester, _backToPassage) && _enabled(tester, _backToPassage),
    isTrue,
    reason: 'a seta sumia por regra própria debaixo do sinal',
  );
  expect(thePersonSign, findsOneWidget);

  await tester.tapAt(tester.getCenter(byLabel(_backToPassage)));
  await settles(tester);
  await settles(tester);

  expect(_state(container).needsPerson, isFalse);
  expect(_state(container).stage, SalaStage.ensaio);
  expect(
    _live(tester, _backToPassage),
    isTrue,
    reason: 'a seta não voltava a valer depois do sinal',
  );

  await tester.tap(byLabel(_backToPassage));
  await settles(tester);

  expect(_state(container).stage, SalaStage.conversa);
}

void main() {
  group('Acceptance 1: the chevron is drawn and live in every state', () {
    testWidgets(
      'on the recording home the chevron stays drawn and live while a take '
      'records, and its tap leaves for the conversation',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (_, container) = await onTheHome(tester);
        await _theHomeTakeRecords(tester, container);

        expect(
          _live(tester, _backToPassage),
          isTrue,
          reason:
              'a seta sumia enquanto a cena gravava, e a equipe ficava presa',
        );

        await tester.tap(byLabel(_backToPassage));
        await settles(tester);

        expect(_state(container).stage, SalaStage.conversa);
        semantics.dispose();
      },
    );

    testWidgets(
      'on the grain choice the chevron stays drawn under the person sign, the '
      'wash takes the tap, and once the sign clears the chevron is live and '
      'leaves',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (_, container) = await onTheGrainChoice(tester);

        await _theSignStandsOverTheChevronUntilItClears(tester, container);
        semantics.dispose();
      },
    );

    testWidgets(
      'on the First listen the chevron stays drawn and live while her fixed '
      'line speaks and while the parts play',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, container) = await onTheFirstListen(
          tester,
          beforeItOpens: (harness) {
            harness.voice.holdNextLine();
            addTearDown(harness.voice.finishHeldLine);
          },
        );
        expect(_state(container).voice, VoiceState.speaking);

        expect(
          _live(tester, _backToRecording),
          isTrue,
          reason: 'a seta sumia enquanto a fala dela tocava',
        );

        harness.voice.finishHeldLine();
        await _until(
          tester,
          'as partes tocarem',
          () => harness.playback.sounding,
        );

        expect(
          _live(tester, _backToRecording),
          isTrue,
          reason: 'a seta sumia enquanto as partes tocavam',
        );

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        semantics.dispose();
      },
    );

    testWidgets(
      'on the Back-translation the chevron stays drawn and live while the '
      'voice thinks, while it speaks the verdict, and while the telling\'s '
      'microphone is open',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theTellingOpens(tester, harness, container);

        expect(
          _live(tester, _backToRecording),
          isTrue,
          reason: 'a seta sumia com o microfone da tradução aberto',
        );

        _notifier(container).retroTap();
        await _until(
          tester,
          'o trecho chegar à sala',
          () =>
              harness.room.chunkTakes.isNotEmpty &&
              _state(container).voice != VoiceState.thinking,
        );
        await _theCheckIsAsked(tester, harness, container);

        expect(_state(container).voice, VoiceState.thinking);
        expect(
          _live(tester, _backToRecording),
          isTrue,
          reason: 'a seta sumia enquanto a voz pensava',
        );

        harness.voice.holdNextLine();
        addTearDown(harness.voice.finishHeldLine);
        harness.room.finishHeldVerdict();
        await _until(
          tester,
          'o veredito ser dito',
          () => _state(container).voice == VoiceState.speaking,
        );

        expect(
          _live(tester, _backToRecording),
          isTrue,
          reason: 'a seta sumia enquanto o veredito era dito',
        );
        harness.voice.finishHeldLine();
        await settles(tester);
        semantics.dispose();
      },
    );

    testWidgets(
      'under the person sign the recording home\'s chevron stays drawn, the '
      'wash takes the tap, and once the sign clears the chevron is live and '
      'leaves',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (_, container) = await onTheHome(tester);

        await _theSignStandsOverTheChevronUntilItClears(tester, container);
        semantics.dispose();
      },
    );
  });

  group('Acceptance 2: a tap stops a line or the verdict at once', () {
    testWidgets(
      'a tap while the First listen\'s fixed line speaks stops it at once and '
      'nothing more is said on the recording home',
      (tester) async {
        final (harness, container) = await onTheFirstListen(
          tester,
          beforeItOpens: (harness) {
            harness.voice.holdNextLine();
            addTearDown(harness.voice.finishHeldLine);
          },
        );
        expect(_state(container).voice, VoiceState.speaking);
        final stops = harness.voice.stops;
        final played = harness.playback.played.length;

        await tester.tap(byLabel(_backToRecording));
        await tester.pump();

        expect(
          harness.voice.stops,
          greaterThan(stops),
          reason: 'a fala dela seguia por cima da casa',
        );
        expect(_state(container).voice, isNot(VoiceState.speaking));
        final said = harness.sounds.length;

        harness.voice.finishHeldLine();
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        expect(_voicedSince(harness, said), isEmpty);
        expect(harness.playback.played.skip(played), isEmpty);
      },
    );

    testWidgets(
      'a tap while the verdict speaks stops it at once and nothing more is '
      'said on the recording home',
      (tester) async {
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theCheckIsAsked(tester, harness, container);
        harness.voice.holdNextLine();
        addTearDown(harness.voice.finishHeldLine);
        harness.room.finishHeldVerdict();
        await _until(
          tester,
          'o veredito ser dito',
          () => _state(container).voice == VoiceState.speaking,
        );
        final stops = harness.voice.stops;
        final played = harness.playback.played.length;

        await tester.tap(byLabel(_backToRecording));
        await tester.pump();

        expect(
          harness.voice.stops,
          greaterThan(stops),
          reason: 'o veredito seguia por cima da casa',
        );
        expect(_state(container).voice, isNot(VoiceState.speaking));
        final said = harness.sounds.length;

        harness.voice.finishHeldLine();
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        expect(_voicedSince(harness, said), isEmpty);
        expect(harness.playback.played.skip(played), isEmpty);
      },
    );

    testWidgets(
      'a tap while a line is still being fetched leaves, and the line is never '
      'said',
      (tester) async {
        const verdictClip = '/voice/veredito-novo';
        final (harness, container) = await _onTheBackTranslation(tester);
        harness.playback.finishPlayback();
        await settles(tester);
        harness.room
          ..verdictChecked = true
          ..verdictAudioUrl = verdictClip;
        harness.voice
          ..missing.add(verdictClip)
          ..holdNextFetch();
        addTearDown(harness.voice.finishHeldFetch);
        unawaited(_notifier(container).finishBackTranslation());
        await _until(
          tester,
          'o veredito estar sendo buscado',
          () => harness.voice.fetched.contains(verdictClip),
        );
        final said = harness.sounds.length;
        final played = harness.playback.played.length;

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);
        harness.voice.finishHeldFetch();
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        expect(
          _voicedSince(harness, said),
          isEmpty,
          reason: 'a fala buscada antes do toque era dita na casa',
        );
        expect(harness.playback.played.skip(played), isEmpty);
      },
    );
  });

  group('Acceptance 3: a tap during «conferindo…»', () {
    testWidgets(
      'a tap during «conferindo…» leaves, the verdict is not voiced on the '
      'recording home, and a later entry shows no «conferindo…» and restores '
      'the marks from the room',
      (tester) async {
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theCheckIsAsked(tester, harness, container);

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);
        expect(_state(container).stage, SalaStage.ensaio);

        harness.room.readsChecked = true;
        harness.room.finishHeldVerdict();
        await _passTenSeconds(tester);

        expect(
          harness.voice.fixedLines.map((line) => line.$1),
          isNot(contains(_verdictLine)),
          reason: 'o veredito era dito na casa da gravação',
        );

        _notifier(container).startRetro();
        await settles(tester);
        await settles(tester);

        expect(_state(container).stage, SalaStage.retro);
        expect(
          find.text(_conferindo),
          findsNothing,
          reason: 'a tradução voltava presa em «conferindo…»',
        );
        expect(
          _state(container).btPhase,
          BtPhase.conferida,
          reason: 'a volta esquecia o veredito que a sala deu',
        );
        expect(_state(container).btVeredito, isTrue);
      },
    );
  });

  group(
    'Acceptance 3b: the findings of a verdict that lands after the leave',
    () {
      testWidgets(
        'a tap during «conferindo…» over a verdict not checked, with findings, '
        'and a later entry shows those findings from the room',
        (tester) async {
          final (harness, container) = await _onTheBackTranslation(tester);
          await _theTellingOpens(tester, harness, container);
          _notifier(container).retroTap();
          await _until(
            tester,
            'o trecho chegar à sala',
            () =>
                harness.room.chunkTakes.isNotEmpty &&
                _state(container).btTrechos.isNotEmpty &&
                _state(container).voice != VoiceState.thinking,
          );
          final told = _state(container).btTrechos.first;
          final finding = BtFinding(
            kind: BtFindingKind.unclear,
            frase: told.frase,
            segmentId: told.segmentId,
          );
          harness.room
            ..verdictChecked = false
            ..verdictFindings = [finding];
          await _theCheckIsAsked(tester, harness, container);
          harness.room.verdictChecked = false;

          await tester.tap(byLabel(_backToRecording));
          await settles(tester);
          expect(_state(container).stage, SalaStage.ensaio);

          harness.room.retroSoFar = BackTranslationProgress(
            segments: [...harness.room.segments],
            findings: [finding],
          );
          harness.room.finishHeldVerdict();
          await _passTenSeconds(tester);

          _notifier(container).startRetro();
          await settles(tester);
          await settles(tester);

          expect(_state(container).stage, SalaStage.retro);
          expect(
            find.text(_unclear),
            findsOneWidget,
            reason: 'a volta perdia os achados do veredito que a sala deu',
          );
        },
      );
    },
  );

  group('Acceptance 4: a tap discards what is open and sends nothing', () {
    testWidgets('a tap while a home take records discards it unsent', (
      tester,
    ) async {
      final (harness, container) = await onTheHome(tester);
      await _theHomeTakeRecords(tester, container);
      final deleted = harness.recorder.deleted.length;

      await tester.tap(byLabel(_backToPassage));
      await settles(tester);
      await _passTenSeconds(tester);

      expect(_state(container).stage, SalaStage.conversa);
      expect(_deletedSince(harness, deleted, 'ensaio_tomada'), hasLength(1));
      expect(harness.room.takesReceived, isEmpty);
      expect((harness.takes as FakeTakeQueue).rows, isEmpty);

      _notifier(container).openTheEnsaioFinal();
      await settles(tester);
      _notifier(container).chooseTheGrain(Grain.whole);
      await settles(tester);

      expect(_state(container).stage, SalaStage.ensaio);
      expect(_onTheWholeRow('Gravar'), findsOneWidget);
      expect(_onTheWholeRow('Ouvir'), findsNothing);
    });

    testWidgets(
      'a tap while a home take is stopping discards it unsent and leaves no '
      'file',
      (tester) async {
        final (harness, container) = await onTheHome(tester);
        await _theHomeTakeRecords(tester, container);
        final deleted = harness.recorder.deleted.length;
        harness.recorder.holdNextStop();
        addTearDown(harness.recorder.finishStop);
        final stops = _stopsAsked(harness);
        await tester.tap(_onTheWholeRow('Parar'));
        await tester.pump();
        expect(_stopsAsked(harness), stops + 1);

        await tester.tap(byLabel(_backToPassage));
        await settles(tester);
        harness.recorder.finishStop();
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.conversa);
        expect(
          _deletedSince(harness, deleted, 'ensaio_tomada'),
          hasLength(1),
          reason: 'a gravação que parava na hora do toque ficava no tablet',
        );
        expect(harness.room.takesReceived, isEmpty);
        expect((harness.takes as FakeTakeQueue).rows, isEmpty);
      },
    );

    testWidgets(
      'a tap while the telling\'s microphone is open discards it and nothing '
      'is sent',
      (tester) async {
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theTellingOpens(tester, harness, container);
        final deleted = harness.recorder.deleted.length;

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        expect(harness.room.chunkTakes, isEmpty);
        expect(_deletedSince(harness, deleted, 'retro_passada'), hasLength(1));
      },
    );

    testWidgets(
      'a tap while the telling is stopping discards it, leaves no file, and '
      'nothing is sent',
      (tester) async {
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theTellingOpens(tester, harness, container);
        final deleted = harness.recorder.deleted.length;
        harness.recorder.holdNextStop();
        addTearDown(harness.recorder.finishStop);
        final stops = _stopsAsked(harness);
        _notifier(container).retroTap();
        await tester.pump();
        expect(_stopsAsked(harness), stops + 1);

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);
        harness.recorder.finishStop();
        await _passTenSeconds(tester);

        expect(_state(container).stage, SalaStage.ensaio);
        expect(harness.room.chunkTakes, isEmpty);
        expect(
          _deletedSince(harness, deleted, 'retro_passada'),
          hasLength(1),
          reason: 'a tradução que parava na hora do toque ficava no tablet',
        );
      },
    );

    testWidgets(
      'a tap while a stretch is on its way leaves, and the next entry starts '
      'after that stretch once the room has it',
      (tester) async {
        final (harness, container) = await _onTheBackTranslation(tester);
        await _theTellingOpens(tester, harness, container);
        harness.room.holdNextChunk();
        addTearDown(harness.room.finishHeldChunk);
        _notifier(container).retroTap();
        await _until(
          tester,
          'o trecho ir para a sala',
          () => harness.room.chunkTakes.isNotEmpty,
        );
        harness.room.failStateOnceWith = const NetworkFailed('sem rede');

        await tester.tap(byLabel(_backToRecording));
        await settles(tester);
        expect(_state(container).stage, SalaStage.ensaio);
        harness.room.finishHeldChunk();
        await _passTenSeconds(tester);

        _notifier(container).startRetro();
        await settles(tester);
        await settles(tester);

        expect(_state(container).stage, SalaStage.retro);
        expect(
          _state(container).btTrechos,
          hasLength(1),
          reason: 'o trecho que chegou depois do toque era esquecido',
        );
      },
    );
  });
}
