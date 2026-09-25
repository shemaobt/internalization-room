import 'dart:io';

import 'package:flutter/material.dart';
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

Future<void> settle([
  Duration delay = const Duration(milliseconds: 120),
]) async {
  await Future<void>.delayed(delay);
}

Finder _byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

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
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
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
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return (container, gravada.path);
}

/// A room reopened into the retro, warned but not yet blocked, with the resumed part
/// already playing — the ground T1 and T4 measure.
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
/// bead can be heard from the row without the team telling anything new.
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

/// A room reopened straight into a blocking halt already standing, before the entry
/// ever chose a part to play — the narrow case `_entradaParouSemTocar` alone used to
/// cover.
Future<(ProviderContainer, SalaSessionState Function(), String)>
_reopensBlockedBeforeAnyPlay(SalaHarness harness) async {
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.blocking;
  final (container, path) = await _reopensIntoRetro(harness);
  SalaSessionState read() => container.read(salaSessionProvider);
  await waitFor('a sala parar ao reabrir', () => read().needsPerson);
  return (container, read, path);
}

/// Turn the standing warning blocking, and wait for the watch's next beat to find it.
Future<void> _haltLandsBlocking(
  SalaHarness harness,
  SalaSessionState Function() read,
) async {
  harness.room.serverHalt = HaltKind.blocking;
  await waitFor('a sala parar', () => read().needsPerson);
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
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  return container;
}

void main() {
  test('T1: a blocking halt lifted mid-part plays the current part again from '
      'the cursor', () async {
    final harness = SalaHarness();
    final (_, _, read, path) = await _playingWithAWarningArmed(harness);
    final cursorBefore = harness.playback.playedFrom.last;
    final playsBefore = harness.playback.playedFrom.length;

    await _haltLandsBlocking(harness, read);

    harness.room.theDeskAttended();
    await waitFor(
      'a parte voltar a tocar',
      () => harness.playback.playedFrom.length > playsBefore,
    );

    expect(read().needsPerson, isFalse);
    expect(
      harness.playback.played.last,
      path,
      reason: 'a mesma parte, não outra',
    );
    expect(
      harness.playback.playedFrom.last,
      cursorBefore,
      reason: 'do cursor onde a fala parou, não do início',
    );
  });

  testWidgets(
    'T2: the circle says listen first when nothing has been heard since the '
    'cursor, and a tap leaves the state unchanged',
    (tester) async {
      final harness = SalaHarness();
      final container = await _freshlyInRetro(tester, harness);
      SalaSessionState read() => container.read(salaSessionProvider);

      expect(read().btPhase, BtPhase.playing);
      expect(_byLabel('Ouvir primeiro'), findsOneWidget);

      final startsBefore = harness.sounds
          .where((s) => s == 'recorder:start')
          .length;
      await tester.tap(_byLabel('Ouvir primeiro'));
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
    },
  );

  test('T3: a halt lifted while a bead replay was sounding resumes the part '
      'from the cursor, not the bead', () async {
    final harness = SalaHarness();
    final (_, notifier, read, path) =
        await _playingWithAToldStretchAndAWarningArmed(harness);

    notifier.ouvirOTrechoContado(0);
    await waitFor(
      'o trecho contado tocar',
      () => read().btTrechoTocando || read().btRetroTocando,
    );
    final playsBefore = harness.playback.playedFrom.length;

    await _haltLandsBlocking(harness, read);
    expect(read().btTrechoTocando, isFalse);
    expect(read().btRetroTocando, isFalse);

    harness.room.theDeskAttended();
    await waitFor(
      'a parte voltar a tocar',
      () => harness.playback.playedFrom.length > playsBefore,
    );

    expect(read().btTrechoTocando, isFalse);
    expect(read().btRetroTocando, isFalse);
    expect(harness.playback.played.last, path);
    expect(
      harness.playback.playedFrom.last,
      const Duration(milliseconds: 12000),
      reason: 'o cursor do trecho já contado, não o começo da parte',
    );
  });

  test('T4: while the halt stands, nothing sounds', () async {
    final harness = SalaHarness();
    final (_, _, read, _) = await _playingWithAWarningArmed(harness);

    await _haltLandsBlocking(harness, read);

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

  testWidgets('T5: in english the circle says listen first', (tester) async {
    final harness = SalaHarness(lingua: 'en');
    await _freshlyInRetro(tester, harness);

    expect(_byLabel('Listen first'), findsOneWidget);
  });

  test('T6: a halt already blocking when the entry chose its part plays it '
      'once lifted, the same as any other lift', () async {
    final harness = SalaHarness();
    final (_, read, path) = await _reopensBlockedBeforeAnyPlay(harness);
    expect(
      harness.playback.playedFrom,
      isEmpty,
      reason: 'a entrada escolheu a parte e parou antes de tocar',
    );

    harness.room.theDeskAttended();
    await waitFor(
      'a parte tocar pela primeira vez',
      () => harness.playback.playedFrom.isNotEmpty,
    );

    expect(read().needsPerson, isFalse);
    expect(harness.playback.played.last, path);
    expect(harness.playback.playedFrom.last, Duration.zero);
  });
}
