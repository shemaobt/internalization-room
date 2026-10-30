import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart';
import 'support/temp.dart';

/// A tablet reopening straight into an unchecked telling-back, with one part already
/// named. Copied from `the_desk_lifts_the_halt_test.dart` and
/// `a_halt_in_the_middle_of_a_capture_leaves_the_microphone_open_test.dart`: fixtures never
/// travel between modules, only the shape does.
Future<(ProviderContainer, String)> _reopensIntoRetro(
  SalaHarness harness,
) async {
  final gravada = File('${aTempDir('sala-1136').path}/p1.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  final row = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  await holdTheSession(harness, row);
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.openTheRoom();
  await intoTheBackTranslation(
    notifier,
    () => container.read(salaSessionProvider),
  );
  await settle();
  return (container, gravada.path);
}

/// A room reopened into the retro, warned but not yet blocked, with the resumed part
/// already playing — the ground most of this file measures. The cursor starts at
/// nought.
Future<
  (ProviderContainer, SalaSessionNotifier, SalaSessionState Function(), String)
>
_playingWithAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  final (container, path) = await _reopensIntoRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await waitFor('o aviso chegar', () => read().warning);
  await waitFor('a parte tocar', () => read().btPhase == BtPhase.playing);
  return (container, notifier, read, path);
}

/// The same ground as above, but with a stretch already told over the resumed part, so a
/// bead can be heard from the row without the team telling anything new. Pins the
/// cursor at 12s, away from both nought and wherever a live read might wrongly resume
/// from.
Future<
  (ProviderContainer, SalaSessionNotifier, SalaSessionState Function(), String)
>
_playingWithAToldStretchAndAWarningArmed(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  harness.room.retroSoFar = const BackTranslationProgress(
    segments: [
      SegmentView(
        segmentId: 'trecho-1',
        takeId: 'gravacao-1',
        startsMs: 0,
        endsMs: 12000,
      ),
    ],
  );
  final (container, path) = await _reopensIntoRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await waitFor('o aviso chegar', () => read().warning);
  await waitFor('a parte tocar', () => read().btPhase == BtPhase.playing);
  await waitFor(
    'o trecho já contado chegar',
    () => read().btTrechos.isNotEmpty,
  );
  return (container, notifier, read, path);
}

/// A team standing on a freshly recorded part, nothing heard yet since the cursor.
Future<ProviderContainer> _freshlyInRetro(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  testWidgets(
    'T2: a tap on the circle while nothing has been heard since the cursor '
    'opens no microphone',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.takeLandsAfter = const Duration(seconds: 1);
      final container = await _freshlyInRetro(tester, harness);
      SalaSessionState read() => container.read(salaSessionProvider);

      expect(read().btPhase, BtPhase.playing);
      expect(read().nothingHeardSinceCursor, isTrue);

      final startsBefore = harness.sounds
          .where((s) => s == 'recorder:start')
          .length;
      await tester.tap(byLabel('ouvindo a gravação de vocês…'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        read().btPhase,
        BtPhase.playing,
        reason: 'o toque não abre a captura',
      );
      expect(
        harness.sounds.where((s) => s == 'recorder:start').length,
        startsBefore,
        reason: 'nenhum microfone abriu',
      );
      closeTheRoom(container);
    },
  );

  test('T4: a halt raised while the part sounds on the back-translation leaves '
      'it sounding, as hers', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);
    expect(harness.playback.sounding, isTrue);

    notifier.haltForABrokenBuild();
    await settle();

    expect(read().needsPerson, isFalse);
    expect(
      harness.playback.sounding,
      isTrue,
      reason: 'a parada calava a parte, e o Drafting dela segue tocando',
    );
    expect(read().btClipRodando, isTrue);
  });

  test('T5: the listen first label exists in pt and en through the map', () {
    expect(retroLabelFor('listenFirst', 'pt'), 'Ouvir primeiro');
    expect(retroLabelFor('listenFirst', 'en'), 'Listen first');
  });

  testWidgets('T5w: in english the circle held before anything was heard reads '
      'her paused line, not listen first', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _freshlyInRetro(tester, harness);
    await tester.tap(byLabel('Pause'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      byLabel('paused — tap the circle to mark where the sentence ends'),
      findsOneWidget,
    );
    closeTheRoom(container);
  });

  test('a confirm answered after a halt raised on the back-translation plays '
      'on, as hers', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);
    harness.playback.at = const Duration(seconds: 4);
    notifier.retroTap();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);

    harness.room.holdNextChunk();
    notifier.retroTap();
    await waitFor(
      'a sala pensar enquanto o V viaja',
      () => read().btPhase == BtPhase.thinking,
    );
    notifier.haltForABrokenBuild();
    await settle();
    final tocadas = harness.playback.played.length;

    harness.room.finishHeldChunk();
    await waitFor(
      'o trecho seguinte tocar',
      () => harness.playback.played.length > tocadas,
    );

    expect(read().needsPerson, isFalse);
    expect(
      harness.playback.played.length,
      greaterThan(tocadas),
      reason: 'a resposta que pousava sob a parada avançava em silêncio',
    );
  });

  test('P2: the scissors never cut behind the cursor, only at her floor past '
      'it', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) =
        await _playingWithAToldStretchAndAWarningArmed(harness);

    harness.playback.at = const Duration(seconds: 2);
    notifier.retroTap();
    await settle();

    expect(read().btCorte, const Duration(milliseconds: 12200));
  });

  test('T11: a halt silences the room outside the retro too, cutting the '
      'Guide off mid-line', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.voice.holdNextLine();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    expect(read().voice, VoiceState.speaking);
    final stopsBefore = harness.sounds.where((s) => s == 'voice:stop').length;

    notifier.haltForABrokenBuild();

    expect(read().needsPerson, isTrue);
    expect(
      harness.sounds.where((s) => s == 'voice:stop').length,
      greaterThan(stopsBefore),
      reason: 'ADR 0044: a halt silences every station, not only the retro',
    );
  });
}
