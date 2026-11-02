import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'a_parte_da_volta_ganha_nome_test.dart' show gravarSemEsperarNome;
import 'a_wav_take.dart';
import 'an_empty_telling_keeps_the_pause_and_shows_her_line_test.dart'
    show fecharSemPalavras, linha, pausarEAbrir;
import 'fakes.dart';
import 'scenario_helpers.dart'
    show byLabel, intoTheRecordingHome, relaunch, settle, umaParteInteira;
import 'support/temp.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        parte,
        tocarNoCirculo;

const _enviando = 'enviando…';
const _aprovar = 'Aprovar como rascunho final';
const _pronto = 'Pronto';

typedef _Held = ({
  SalaHarness harness,
  ProviderContainer container,
  String held,
  String span,
  int sentBefore,
});

SalaSessionState _state(ProviderContainer container) =>
    container.read(salaSessionProvider);

SalaSessionNotifier _notifier(ProviderContainer container) =>
    container.read(salaSessionProvider.notifier);

Future<_Held> _aStretchToldBeforeItsPartHasAName() async {
  final harness = SalaHarness(filaEmMemoria: true);
  harness.recorder.rehearsalSpeaks = aWavTake(
    samples: List.filled(16000 * umaParteInteira.inSeconds, 0),
  );
  final queue = harness.takes as FakeTakeQueue;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = _notifier(container);
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await intoTheRecordingHome(notifier, () => _state(container));
  notifier.goEnsaio();
  queue.forgetsNames = false;
  await gravarSemEsperarNome(container, 1);
  await waitFor(
    'a parte 1 ganhar o nome',
    () => _state(container).partes.single.takeId != null,
  );
  queue.forgetsNames = true;
  await gravarSemEsperarNome(container, 2);
  await waitFor(
    'a parte 2 chegar à sala',
    () =>
        _state(container).partes.length == 2 &&
        _state(container).everyPartIsSent,
  );
  final part = _state(container).partes[1];
  expect(
    part.takeId,
    isNull,
    reason:
        'o cenário é o da parte que chegou à sala sem o tablet saber o nome '
        'dela',
  );
  harness.room.takes.add(
    TakeView(
      takeId: queue.rows.last.takeId!,
      kind: partTakeKind,
      scope: part.scopeId,
      ordinal: 2,
      pass: part.pass,
      sha256: crypto.sha256
          .convert(File(part.path).readAsBytesSync())
          .toString(),
    ),
  );
  harness.playback.length = umaParteInteira;
  notifier.startRetro();
  await theClipOpens(harness);
  harness.playback.at = const Duration(seconds: 12);
  notifier.retroTap();
  notifier.retroTap();
  await settle();
  await confirmarATraducao(container);
  harness.playback.at = umaParteInteira;
  notifier.retroTap();
  notifier.retroTap();
  await settle();
  await confirmarATraducao(container);
  harness.playback.finishPlayback();
  await waitFor(
    'a retro tocar a parte 2',
    () =>
        harness.playback.played.isNotEmpty &&
        harness.playback.played.last == part.path,
  );
  await theClipOpens(harness);
  final sentBefore = harness.room.chunksSent;
  harness.room.holdNextTakesList();
  harness.playback.at = const Duration(seconds: 12);
  notifier.retroTap();
  notifier.retroTap();
  await settle();
  final cut = _state(container);
  final span = '${cut.btCursor.inMilliseconds}-${cut.btCorte.inMilliseconds}';
  await confirmarATraducao(container);
  await waitFor(
    'a listagem da sala ser pedida',
    () => harness.room.aTakesListIsHeld,
    limit: const Duration(seconds: 5),
  );
  return (
    harness: harness,
    container: container,
    held: harness.recorder.lastPath!,
    span: span,
    sentBefore: sentBefore,
  );
}

Future<void> _thePartIsNamed(_Held it) async {
  while (it.harness.room.aTakesListIsHeld) {
    it.harness.room.finishHeldTakesList();
    await settle();
  }
}

String _theRoomsNameForPart(SalaHarness harness, int n) => harness.room.takes
    .lastWhere((take) => take.scope == KeptScope.parte(n))
    .takeId;

const _bytesDaParte = [1, 2, 3];

Future<(SalaHarness, ProviderContainer)> _aResumedPartWithNoName() async {
  final antes = SalaHarness();
  final home = aTempDir('sala-parte-sem-nome');
  await antes.emAberto.remember(
    'Ruth',
    'P01',
    'pt',
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [
        for (var parte = 1; parte <= 2; parte++)
          KeptTake(
            scopeId: KeptScope.parte(parte),
            path: (File(
              '${home.path}/p$parte.m4a',
            )..writeAsBytesSync(_bytesDaParte)).path,
            takeId: parte == 2 ? null : 'antiga-$parte',
          ),
      ],
    ),
  );
  antes.room.takes.addAll([
    for (var parte = 1; parte <= 2; parte++)
      TakeView(
        takeId: parte == 2 ? 'da-sala-2' : 'antiga-$parte',
        kind: partTakeKind,
        scope: KeptScope.parte(parte),
        ordinal: parte,
        pass: 1,
        sha256: parte == 2
            ? crypto.sha256.convert(_bytesDaParte).toString()
            : null,
      ),
  ]);
  antes.room.failTakesWith = const NetworkFailed('sem rede');
  final primeira = antes.container();
  addTearDown(primeira.dispose);
  final notifier = _notifier(primeira);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await intoTheRecordingHome(notifier, () => _state(primeira));
  expect(_state(primeira).partes[1].takeId, isNull);
  final (harness, container) = await relaunch(antes, primeira);
  harness.room.failTakesWith = null;
  harness.room.holdNextTakesList();
  await _notifier(container).openTheRoom();
  await waitFor(
    'a listagem da retomada ser pedida',
    () => harness.room.aTakesListIsHeld,
    limit: const Duration(seconds: 5),
  );
  return (harness, container);
}

Future<void> _settleOnScreen(WidgetTester tester) async {
  for (var beat = 0; beat < 6; beat++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<ProviderContainer> _intoTheBackTranslationOverANamelessPart(
  WidgetTester tester,
  SalaHarness harness,
) async {
  (harness.takes as FakeTakeQueue).forgetsNames = true;
  harness.room.failTakesWith = const NetworkFailed('sem rede');
  harness.playback
    ..measured = parte
    ..length = parte;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = _notifier(container);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  await waitFor(
    'a parte chegar à sala sem nome',
    () => _state(container).everyPartIsSent,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  expect(_state(container).partes.single.takeId, isNull);
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<void> _approvedAndPronto(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.verdictChecked = true;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await _settleOnScreen(tester);
  await contarAteOFimDaParte(tester, harness);
  await _notifier(container).finishBackTranslation();
  await _settleOnScreen(tester);
  harness.room.approvedDraft = const ApprovedDraft(version: 1);
  await tester.ensureVisible(byLabel(_aprovar));
  await tester.tap(byLabel(_aprovar));
  await _settleOnScreen(tester);
  await tester.tap(byLabel(_pronto));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(harness.fimLinger + const Duration(seconds: 2));
}

void main() {
  group('a stretch told before its part has a name', () {
    test('a stretch told before its part has a name reads «enviando…», never '
        '«não entendi», and nothing is sent', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();

      final state = _state(it.container);
      expect(state.wordlessTelling, isFalse);
      expect(state.aStretchWaitsForItsPart, isTrue);
      expect(it.harness.room.chunksSent, it.sentBefore);
      expect(it.harness.recorder.deleted, isNot(contains(it.held)));
      await _thePartIsNamed(it);
    });

    test('when the part gets its name the held stretch goes with no tap and '
        'the part plays on', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();
      final failures = _state(it.container).btChunkFailures;
      final played = it.harness.playback.played.length;

      await _thePartIsNamed(it);
      await waitFor(
        'o trecho guardado ir à sala',
        () => it.harness.room.chunksSent == it.sentBefore + 1,
        limit: const Duration(seconds: 5),
      );
      await waitFor(
        'o trecho ser contado',
        () => _state(it.container).btTrechos.any(
          (trecho) => trecho.contado && trecho.retroPath == it.held,
        ),
        limit: const Duration(seconds: 5),
      );

      final state = _state(it.container);
      expect(
        it.harness.room.chunkTakes.last,
        _theRoomsNameForPart(it.harness, 2),
      );
      expect(it.harness.room.chunkSpans.last, it.span);
      expect(state.aStretchWaitsForItsPart, isFalse);
      expect(state.btChunkFailures, failures);
      expect(it.harness.playback.played.length, greaterThan(played));
      expect(
        it.harness.playback.played.last,
        state.keptTakes[1].path,
        reason: 'a parte segue tocando depois do trecho contado',
      );
    });

    test('a stretch held for its part is never sent after the team leaves the '
        'Back-translation', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();

      _notifier(it.container).leaveTheBackTranslation();
      await settle();
      await _thePartIsNamed(it);

      expect(it.harness.room.chunksSent, it.sentBefore);
      expect(it.harness.recorder.deleted, contains(it.held));
    });

    test(
      'telling a held stretch again sends only the newest recording',
      () async {
        final it = await _aStretchToldBeforeItsPartHasAName();
        it.harness.room.holdNextTakesList();

        _notifier(it.container).retroTap();
        await settle();
        await confirmarATraducao(it.container);
        final newest = _state(it.container).btTraducaoPendente;
        await _thePartIsNamed(it);
        await waitFor(
          'o trecho mais novo ir à sala',
          () => it.harness.room.chunksSent > it.sentBefore,
          limit: const Duration(seconds: 5),
        );
        await settle();

        expect(newest, isNot(it.held));
        expect(it.harness.recorder.deleted, contains(it.held));
        expect(it.harness.room.chunksSent, it.sentBefore + 1);
        expect(it.harness.room.chunkFiles.last, newest);
      },
    );

    test('translating a frase again while a stretch waits for its part lets '
        'the held stretch go, and «enviando…» with it', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();
      final frase1 = _state(
        it.container,
      ).btTrechos.indexWhere((trecho) => trecho.contado);

      _notifier(it.container).traduzirAFraseDeNovo(frase1);
      await settle();

      expect(_state(it.container).btTrechoTraduzidoDeNovo, isNotNull);
      expect(_state(it.container).aStretchWaitsForItsPart, isFalse);
      expect(it.harness.recorder.deleted, contains(it.held));
      await _thePartIsNamed(it);
      expect(it.harness.room.chunksSent, it.sentBefore);
    });

    test('hearing a frase rests while a stretch waits for its part, so the '
        'naming still sends it', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();
      final frase1 = _state(
        it.container,
      ).btTrechos.indexWhere((trecho) => trecho.contado);

      _notifier(it.container).ouvirOTrechoContado(frase1);
      await settle();
      await _thePartIsNamed(it);
      await waitFor(
        'o trecho guardado ir à sala',
        () => it.harness.room.chunksSent == it.sentBefore + 1,
        limit: const Duration(seconds: 5),
      );

      expect(_state(it.container).btTraducaoPendente, isNull);
    });

    test('«recomeçar» rests while a stretch waits for its part, so a naming '
        'during a failed restart still sends it', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();
      it.harness.room
        ..holdTheTranslationRestart()
        ..failRestartWith = const NetworkFailed('sem rede');

      _notifier(it.container).recomecarATraducao();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      _notifier(it.container).recomecarATraducao();
      await settle();
      await _thePartIsNamed(it);
      it.harness.room.finishTheTranslationRestart();
      await settle();
      await waitFor(
        'o trecho guardado ir à sala',
        () => it.harness.room.chunksSent == it.sentBefore + 1,
        limit: const Duration(seconds: 5),
      );

      expect(it.harness.room.restartsAsked, isEmpty);
    });

    test('«terminei» rests while a stretch waits for its part', () async {
      final it = await _aStretchToldBeforeItsPartHasAName();
      it.harness.playback.finishPlayback();
      await settle();
      final asked = it.harness.room.playedByTakeSent.length;

      await _notifier(it.container).finishBackTranslation();
      await settle();

      expect(_state(it.container).canFinishBackTranslation, isFalse);
      expect(it.harness.room.playedByTakeSent, hasLength(asked));
      await _thePartIsNamed(it);
    });

    test(
      '«regravar a frase N» rests while a stretch waits for its part',
      () async {
        final it = await _aStretchToldBeforeItsPartHasAName();
        final frase1 = _state(
          it.container,
        ).btTrechos.firstWhere((trecho) => trecho.contado);

        _notifier(it.container).regravarAFrase(frase1);
        await settle();

        expect(_state(it.container).fraseRegravavel(frase1), isFalse);
        expect(_state(it.container).btRegravacao, isNull);
        await _thePartIsNamed(it);
      },
    );
  });

  test('a stretch told before its part has a name on a resumed '
      'back-translation goes once the listing names the part', () async {
    final (harness, container) = await _aResumedPartWithNoName();
    final notifier = _notifier(container);
    harness.playback.length = umaParteInteira;
    notifier.startRetro();
    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.retroTap();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    harness.playback.finishPlayback();
    await waitFor(
      'a retro tocar a parte 2',
      () =>
          harness.playback.played.isNotEmpty &&
          harness.playback.played.last == _state(container).partes[1].path,
    );
    await theClipOpens(harness);
    final sentBefore = harness.room.chunksSent;
    harness.room.holdNextTakesList();
    harness.playback.at = const Duration(seconds: 12);
    notifier.retroTap();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'a listagem do trecho guardado ser pedida',
      () => harness.room.takesListsHeld == 2,
      limit: const Duration(seconds: 5),
    );
    expect(_state(container).aStretchWaitsForItsPart, isTrue);
    expect(harness.room.chunksSent, sentBefore);

    harness.room.finishHeldTakesList();
    harness.room.finishHeldTakesList();
    await waitFor(
      'o trecho guardado ir à sala',
      () => harness.room.chunksSent == sentBefore + 1,
      limit: const Duration(seconds: 5),
    );

    expect(harness.room.chunkTakes.last, 'da-sala-2');
    expect(_state(container).aStretchWaitsForItsPart, isFalse);
  });

  testWidgets('on the screen, a stretch told before its part has a name reads '
      '«enviando…», never «não entendi»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _intoTheBackTranslationOverANamelessPart(
      tester,
      harness,
    );
    await pausarEAbrir(tester, harness);

    await tocarNoCirculo(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(_state(container).aStretchWaitsForItsPart, isTrue);
    expect(find.text(_enviando), findsOneWidget);
    expect(find.text(linha), findsNothing);
    expect(
      _state(container).voice,
      isNot(VoiceState.thinking),
      reason: 'o círculo fica vivo para contar o trecho de novo',
    );
    closeTheRoom(container);
  });

  group('a telling turned away', () {
    Future<(ProviderContainer, String)> turnedAway(
      WidgetTester tester,
      SalaHarness harness,
      RoomFailure failure,
    ) async {
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      await pausarEAbrir(tester, harness);
      harness.room.chunkAnswersFirst.add(failure);
      await tocarNoCirculo(tester);
      final told = harness.recorder.lastPath!;
      await tester.pump(const Duration(milliseconds: 300));
      return (container, told);
    }

    void expectNoNaoEntendiAndAPersonWaiting(ProviderContainer container) {
      final state = _state(container);
      expect(find.text(linha), findsNothing);
      expect(state.wordlessTelling, isFalse);
      expect(state.machine.aHaltWaitsForTheCanvas?.callsForAPerson, isTrue);
      expect(state.needsPerson, isFalse);
    }

    testWidgets('a stretch the telling door answers 401 never reads «não '
        'entendi» and leaves a halt that calls a person waiting for the '
        'Conversation', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final (container, told) = await turnedAway(
        tester,
        harness,
        const Refused(RefusalCode.unauthorized),
      );

      expectNoNaoEntendiAndAPersonWaiting(container);
      expect(harness.recorder.deleted, contains(told));

      await _approvedAndPronto(tester, harness, container);

      expect(_state(container).stage, SalaStage.conversa);
      expect(_state(container).needsPerson, isTrue);
      closeTheRoom(container);
    });

    testWidgets('a stretch whose tablet was revoked never reads «não entendi» '
        'and leaves a halt that calls a person', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final (container, told) = await turnedAway(
        tester,
        harness,
        const Refused(RefusalCode.deviceRevoked),
      );

      expectNoNaoEntendiAndAPersonWaiting(container);
      expect(harness.recorder.deleted, contains(told));
      closeTheRoom(container);
    });

    testWidgets('a stretch told again that the telling door answers 401 never '
        'reads «não entendi»', (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await _settleOnScreen(tester);
      final frase1 = _state(
        container,
      ).btTrechos.indexWhere((trecho) => trecho.contado);
      _notifier(container).traduzirAFraseDeNovo(frase1);
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.replaceAnswersFirst.add(
        const Refused(RefusalCode.unauthorized),
      );

      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      final retold = harness.recorder.lastPath!;
      await _settleOnScreen(tester);

      expect(harness.room.replaceAnswersFirst, isEmpty);
      expectNoNaoEntendiAndAPersonWaiting(container);
      expect(harness.recorder.deleted, contains(retold));
      closeTheRoom(container);
    });
  });

  group('a late failure over a Borrowed translation', () {
    testWidgets('a late refusal of a stretch given up on, landing while a told '
        'stretch is borrowed to translate again, leaves that stretch\'s '
        'recording on the tablet and translating it again lands', (
      tester,
    ) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        busyCeiling: const Duration(seconds: 3),
      );
      final container = await entrarNaTraducao(tester, harness, partes: 1);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await _settleOnScreen(tester);
      final frase1 = _state(
        container,
      ).btTrechos.firstWhere((trecho) => trecho.contado);
      harness.room.holdNextChunkFailure();
      harness.playback.at = const Duration(seconds: 7);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(harness.room.aChunkFailureIsHeld, isTrue);
      expect(_state(container).btPhase, BtPhase.playing);

      _notifier(
        container,
      ).traduzirAFraseDeNovo(_state(container).btTrechos.indexOf(frase1));
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.failTheHeldChunk(Refused(RefusalCode.unnamed(422)));
      await _settleOnScreen(tester);

      expect(harness.recorder.deleted, isNot(contains(frase1.retroPath)));

      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await _settleOnScreen(tester);

      expect(harness.room.replacesAsked.single, startsWith('trecho-1@'));
      expect(_state(container).btTrechoTraduzidoDeNovo, isNull);
      closeTheRoom(container);
    });
  });

  testWidgets('a stretch the room heard and found no words in still reads «não '
      'entendi»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    await pausarEAbrir(tester, harness);

    await fecharSemPalavras(tester, harness);

    expect(find.text(linha), findsOneWidget);
    expect(_state(container).wordlessTelling, isTrue);
    closeTheRoom(container);
  });
}
