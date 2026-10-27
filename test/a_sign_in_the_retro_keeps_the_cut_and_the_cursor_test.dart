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

/// A tablet reopening straight into an unchecked telling-back, with one part already
/// named. Copied from `the_desk_lifts_the_halt_test.dart` and
/// `a_halt_in_the_middle_of_a_capture_closes_the_microphone_test.dart`: fixtures never
/// travel between modules, only the shape does.
Future<(ProviderContainer, String)> _reopensIntoRetro(
  SalaHarness harness,
) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-1136').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
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
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
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

/// The person sign lands over whatever the retro holds: the build guard's, which calls
/// nobody, so the server's warning keeps standing beneath it.
Future<void> _haltLandsBlocking(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  notifier.haltForABrokenBuild();
  await waitFor('a sala parar', () => read().needsPerson);
}

/// The team's tap on the sign hands the room back.
Future<void> _liftsTheHalt(
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
) async {
  notifier.teamTapped();
  await waitFor('o círculo voltar ao convite', () => !read().needsPerson);
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
  notifier.ensaioTap();
  notifier.ensaioTap();
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

  test('a sign raised while the part sounds keeps where the part reached, and '
      'listening after the tap resumes there', () async {
    final harness = SalaHarness();
    final (_, notifier, read, path) =
        await _playingWithAToldStretchAndAWarningArmed(harness);
    harness.playback.at = const Duration(milliseconds: 15000);

    await _haltLandsBlocking(notifier, read);
    await _liftsTheHalt(notifier, read);
    final playsBefore = harness.playback.playedFrom.length;
    notifier.ouvirGravacao();
    await waitFor(
      'a parte voltar a tocar',
      () => harness.playback.playedFrom.length > playsBefore,
    );

    expect(harness.playback.played.last, path);
    expect(
      harness.playback.playedFrom.last,
      const Duration(milliseconds: 15000),
      reason: 'de onde a parte tinha chegado, como a pausa da equipe',
    );
  });

  test('T4: while the halt stands, nothing sounds', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);

    await _haltLandsBlocking(notifier, read);

    expect(harness.playback.sounding, isFalse);
    expect(read().btClipRodando, isFalse);

    final readsBefore = harness.room.calls
        .where((call) => call == 'fetchState')
        .length;
    await waitFor(
      'mais uma batida da vigia',
      () =>
          harness.room.calls.where((call) => call == 'fetchState').length >
          readsBefore,
    );

    expect(
      harness.playback.sounding,
      isFalse,
      reason: 'a parada ainda de pé; nada volta a soar sozinho',
    );
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

  test(
    "T7: a halt over a paused part gives the room back exactly as it stood — "
    'Henok, 25-09',
    () async {
      final harness = SalaHarness();
      final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);

      notifier.ouvirGravacao();
      await waitFor('a parte pausar', () => !read().btClipRodando);
      final playsBefore = harness.playback.playedFrom.length;
      final soundingBefore = harness.playback.sounding;
      expect(soundingBefore, isFalse);

      await _haltLandsBlocking(notifier, read);
      await _liftsTheHalt(notifier, read);

      expect(
        read().btClipRodando,
        isFalse,
        reason: 'a equipe tinha pausado; a parada não devolve tocando',
      );
      expect(
        harness.playback.playedFrom.length,
        playsBefore,
        reason: 'nada é reposto sozinho sobre uma parte pausada',
      );
      expect(harness.playback.sounding, isFalse);
    },
  );

  test('T8: a halt over a part already at its end gives the room back exactly '
      'as it stood — Henok, 25-09', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);

    harness.playback.finishPlayback();
    await waitFor('a parte terminar', () => read().btClipEnded);
    final playsBefore = harness.playback.playedFrom.length;

    await _haltLandsBlocking(notifier, read);
    await _liftsTheHalt(notifier, read);

    expect(
      read().btClipEnded,
      isTrue,
      reason: 'o fim da parte não é desfeito por uma parada',
    );
    expect(
      harness.playback.playedFrom.length,
      playsBefore,
      reason: 'nada é reposto sozinho sobre uma parte já terminada',
    );
  });

  test('T10: a halt landing and tapped away while the confirm itself is still in '
      'flight does not touch the cursor or the cut waiting on it', () async {
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

    await _haltLandsBlocking(notifier, read);
    await _liftsTheHalt(notifier, read);

    harness.room.finishHeldChunk();
    await settle();

    // `chunkSpans` is captured from the arguments at the call, before the halt ever
    // landed, and so is correct either way: the vulnerable read is the local `Trecho`
    // this builds *after* the await, from whatever `_trechoStart`/`_trechoEnd` are by
    // the time the network answers.
    expect(read().btTrechos, hasLength(1));
    expect(read().btTrechos.single.from, Duration.zero);
    expect(read().btTrechos.single.to, const Duration(seconds: 4));
  });

  test(
    'a confirm answered while a blocking halt stands advances in silence',
    () async {
      final harness = SalaHarness();
      final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);
      harness.playback.at = const Duration(seconds: 4);
      notifier.retroTap();
      notifier.retroTap();
      await waitFor(
        'a captura abrir',
        () => read().btPhase == BtPhase.capturing,
      );

      harness.room.holdNextChunk();
      notifier.retroTap();
      await waitFor(
        'a sala pensar enquanto o V viaja',
        () => read().btPhase == BtPhase.thinking,
      );
      await _haltLandsBlocking(notifier, read);
      final tocadas = harness.playback.played.length;

      harness.room.finishHeldChunk();
      await settle();

      expect(read().needsPerson, isTrue);
      expect(
        harness.playback.played,
        hasLength(tocadas),
        reason: 'a resposta que pousa sob a parada avança em silêncio',
      );
    },
  );

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

  test(
    'P4: a halt caught listening to the cut stretch does not wipe the cut',
    () async {
      final harness = SalaHarness();
      final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);

      harness.playback.at = const Duration(seconds: 4);
      notifier.retroTap();
      await waitFor('o corte ficar de pé', () => read().btCortado);
      notifier.ouvirGravacao();
      await waitFor('o trecho cortado tocar', () => read().btTrechoTocando);

      await _haltLandsBlocking(notifier, read);
      await _liftsTheHalt(notifier, read);

      expect(read().btCorte, const Duration(seconds: 4));
      expect(read().btCortado, isTrue);
    },
  );

  test('a halt caught listening to a retell already armed does not wipe its '
      'own place', () async {
    final harness = SalaHarness();
    final (_, notifier, read, _) = await _playingWithAWarningArmed(harness);
    harness.playback.at = const Duration(seconds: 4);
    notifier.retroTap();
    notifier.retroTap();
    await waitFor('a captura abrir', () => read().btPhase == BtPhase.capturing);
    notifier.retroTap();
    await waitFor('o trecho chegar à sala', () => harness.room.chunksSent == 1);

    harness.room.verdictChecked = false;
    harness.room.verdictHasFinding = true;
    harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
    harness.playback.finishPlayback();
    await waitFor(
      'o clipe poder ser dado por terminado',
      () => read().canFinishBackTranslation,
    );
    await notifier.finishBackTranslation();
    await waitFor('o veredito chegar', () => read().btPhase == BtPhase.playing);

    notifier.traduzirAFraseDeNovo(
      read().btTrechos.indexOf(read().btFindingTrecho!),
    );
    await waitFor(
      'o trecho ficar armado para retraduzir',
      () => read().btPhase == BtPhase.playing,
    );
    await waitFor(
      'o trecho apontado tocar',
      () => read().btTrechoTocando || read().btRetroTocando,
    );

    await _haltLandsBlocking(notifier, read);
    await _liftsTheHalt(notifier, read);

    expect(
      read().btTrechoTraduzidoDeNovo,
      isNotNull,
      reason: 'o retell segue armado',
    );
    expect(
      read().btCursor,
      Duration.zero,
      reason: 'o lugar do trecho, não o do cursor da parte',
    );
    expect(read().btCorte, const Duration(seconds: 4));
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
