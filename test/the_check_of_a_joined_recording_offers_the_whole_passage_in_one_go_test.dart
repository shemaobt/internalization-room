import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/grain_choice_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle;
import 'um_ensaio_de_tres_partes.dart';

const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _recordThePart = 'voltar e regravar uma parte';
const _wholeArmed = 'toquem de novo: as cenas e as traduções ficam guardadas';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _theArmLapses = Duration(seconds: 8);
const _whole = 'A passagem inteira';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';

Future<void> _settles(WidgetTester tester) async {
  for (var vez = 0; vez < 10; vez++) {
    await _passo(tester);
  }
}

bool? _aberto(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await _passo(tester);
}

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _naConferencia(
  WidgetTester tester,
  SalaHarness harness, {
  bool juntada = true,
  bool aprovada = false,
  bool conferida = false,
  bool primeiraEscuta = false,
  String lingua = 'pt',
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1876');
  addTearDown(() => pasta.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/$lingua'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.wav',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
          origin: juntada ? 'ensaio-da-cena-$n' : null,
        ),
    ],
  );
  harness.room.takes.addAll([
    for (final n in [1, 2])
      TakeView(
        takeId: 'gravacao-$n',
        kind: 'ensaio',
        scope: KeptScope.parte(n),
        ordinal: n,
        pass: 1,
        origin: juntada ? 'ensaio-da-cena-$n' : null,
      ),
  ]);
  if (aprovada) harness.room.approvedDraft = const ApprovedDraft(version: 1);
  if (primeiraEscuta) {
    harness.room.listeningUnheardTakeIds = const ['gravacao-1', 'gravacao-2'];
  }
  harness.room.retroSoFar = BackTranslationProgress(
    checked: aprovada || conferida,
    segments: [
      if (!primeiraEscuta) ...const [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 5000,
          frase: 1,
        ),
        SegmentView(
          segmentId: 'trecho-2',
          takeId: 'gravacao-2',
          startsMs: 0,
          endsMs: 5000,
          frase: 2,
        ),
      ],
    ],
  );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  if (aprovada) {
    SalaSessionState estado() => container.read(salaSessionProvider);
    await waitFor(
      'a passagem aprovada pousar na conversa',
      () => estado().stage == SalaStage.conversa && !estado().awaitingTheGuide,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir',
      () => estado().stage == SalaStage.ensaio && estado().partes.isNotEmpty,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    container.read(salaSessionProvider.notifier).startRetro();
  }
  await waitFor(
    'a conferência voltar com as duas frases',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        primeiraEscuta == container.read(salaSessionProvider).btSoOuvir &&
        container.read(salaSessionProvider).btTrechos.length ==
            (primeiraEscuta ? 0 : 2) &&
        container.read(salaSessionProvider).btPhase ==
            (aprovada || conferida ? BtPhase.conferida : BtPhase.playing),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await waitFor(
    'a conferência ficar em silêncio',
    () => !harness.playback.sounding,
    step: () async {
      harness.playback.finishPlayback();
      await _passo(tester);
    },
  );
  await _passo(tester);
  return container;
}

Future<void> _umVeredito(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  await waitFor(
    'a gravação tocar até o fim',
    () => container.read(salaSessionProvider).btClipEnded,
    step: () async {
      harness.playback.finishPlayback();
      await _passo(tester);
    },
  );
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 1
    ..verdictFindings = const [
      BtFinding(kind: BtFindingKind.addition, frase: 2, segmentId: 'trecho-2'),
    ];
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar com o achado',
    () =>
        container.read(salaSessionProvider).btPhase == BtPhase.playing &&
        container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

void main() {
  testWidgets('the check of a joined recording offers «gravar a passagem '
      'inteira de uma vez» in the telling step', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    expect(
      find.text(_wholeAtOnce),
      findsOneWidget,
      reason:
          'a conferência do Ensaio Final não oferecia gravar a passagem '
          'de uma vez, e a dela oferece',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict it sits under «voltar e regravar uma parte», '
      'as hers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    await _umVeredito(tester, harness, container);

    expect(find.text(_recordThePart), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_wholeAtOnce)).dy,
      greaterThan(tester.getTopLeft(find.text(_recordThePart)).dy),
      reason: 'o dela fica logo abaixo de voltar e regravar uma parte',
    );
    closeTheRoom(container);
  });

  testWidgets('the check of a joined recording offers it in english as '
      '«record the whole passage in one go»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _naConferencia(tester, harness, lingua: 'en');

    expect(
      find.text('record the whole passage in one go'),
      findsOneWidget,
      reason: 'em inglês a conferência não tinha as palavras dela',
    );
    closeTheRoom(container);
  });

  testWidgets('the first tap arms it with «toquem de novo: as cenas e as '
      'traduções ficam guardadas»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    await _tap(tester, _wholeAtOnce);

    expect(
      find.text(_wholeArmed),
      findsOneWidget,
      reason: 'o primeiro toque não armava, e o dela diz o que fica guardado',
    );
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('in english the armed text reads «tap again: the scenes and the '
      'translations are kept»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _naConferencia(tester, harness, lingua: 'en');

    await _tap(tester, 'record the whole passage in one go');

    expect(
      find.text('tap again: the scenes and the translations are kept'),
      findsOneWidget,
    );
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the first tap arms with «toquem de '
      'novo: isto abre de novo o rascunho aprovado»', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, aprovada: true);

    await _tap(tester, _wholeAtOnce);

    expect(
      find.text(_reopenArmed),
      findsOneWidget,
      reason: 'sobre o rascunho aprovado o dela avisa que abre de novo',
    );
    expect(harness.room.grainSwitches, isEmpty);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('a second tap 2 s later switches the grain through the room\'s '
      'door and lands on the whole-passage home', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    await _settles(tester);

    expect(harness.room.grainSwitches, [(grain: Grain.whole, reopens: false)]);
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'a troca acontecia e a equipe ficava na conferência',
    );
    expect(find.text(_homeLine), findsOneWidget);
    expect(find.text(_whole), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('over an approved draft the second tap switches with the reopen '
      'and lands on the whole-passage home', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, aprovada: true);

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _reopenArmed);
    await _settles(tester);

    expect(
      harness.room.grainSwitches,
      [(grain: Grain.whole, reopens: true)],
      reason: 'sem a reabertura a sala recusa a troca sobre o aprovado',
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
    expect(find.text(_homeLine), findsOneWidget);
    expect(find.text(_whole), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a check no join touched never offers it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, juntada: false);

    expect(
      find.text(_wholeAtOnce),
      findsNothing,
      reason: 'o dela só aparece sobre uma gravação juntada',
    );
    closeTheRoom(container);
  });

  testWidgets('the first listen of a joined recording, before the telling, '
      'never offers it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(
      tester,
      harness,
      primeiraEscuta: true,
    );

    expect(
      find.text(_wholeAtOnce),
      findsNothing,
      reason: 'o dela só aparece no passo de traduzir, não na primeira escuta',
    );
    closeTheRoom(container);
  });

  testWidgets('while a part sounds it is dimmed and a tap does not arm it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
    await _passo(tester);
    expect(harness.playback.sounding, isTrue);

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto algo soa',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the guide speaks it is dimmed and a tap does not arm it', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    await _umVeredito(tester, harness, container);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.voice.holdNextLine();
    await _tap(tester, 'ouvir a resposta de novo');
    expect(container.read(salaSessionProvider).channel, isA<GuideSpeaking>());

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a voz fala',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.voice.finishHeldLine();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the check is sent and its verdict awaited it is dimmed '
      'and a tap does not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.room.holdNextVerdict();
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.thinking);

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a conferência é enviada',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.room.finishHeldVerdict();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while a sentence re-record is open it is dimmed and a tap does '
      'not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    await _tap(tester, 'regravar a frase 1');
    await waitFor(
      'a frase tocar até o fim',
      () => !harness.playback.sounding,
      step: () async {
        harness.playback.finishPlayback();
        await _passo(tester);
      },
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).btRegravacao, isNotNull);
    expect(container.read(salaSessionProvider).channel, isA<Silence>());

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto uma frase é regravada',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the approval is on its way to the room it is dimmed and '
      'a tap does not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness, conferida: true);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    harness.room.holdNextRelease();
    unawaited(
      container.read(salaSessionProvider.notifier).aprovarRascunhoFinal(),
    );
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).aBackTranslationGestureActs,
      isFalse,
    );

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'o dela fica desligado enquanto a aprovação vai para a sala',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    harness.room.finishHeldRelease();
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the switch is in the air more taps never call the door '
      'again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    harness.room.holdTheGrainSwitch();

    await _tap(tester, _wholeAtOnce);
    await tester.pump(const Duration(seconds: 2));
    await _tap(tester, _wholeArmed);
    expect(container.read(salaSessionProvider).grainSwitching, isTrue);

    for (var vez = 0; vez < 2; vez++) {
      await tester.tap(find.byType(GrainChange));
      await tester.pump(const Duration(seconds: 2));
    }

    expect(
      harness.room.grainSwitches,
      hasLength(1),
      reason: 'um toque durante a troca chamava a porta da sala de novo',
    );
    harness.room.finishTheGrainSwitch();
    await _settles(tester);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  testWidgets('while the room is stopped for a person it is dimmed and a tap '
      'does not arm it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naConferencia(tester, harness);
    expect(_aberto(tester, _wholeAtOnce), isTrue);

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await _passo(tester);
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    expect(
      _aberto(tester, _wholeAtOnce),
      isFalse,
      reason: 'com a sala parada esperando uma pessoa a troca ainda armava',
    );
    await _tap(tester, _wholeAtOnce);
    expect(find.text(_wholeArmed), findsNothing);
    await tester.pump(_theArmLapses);
    closeTheRoom(container);
  });

  test('a switch to the whole from the check reports what was heard before '
      'the room\'s grain door, never after it', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar a primeira parte',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          it.harness.playback.sounding,
    );
    await ouvirAteOFim(it, partesDoEnsaio[0]);
    await waitFor(
      'a segunda parte entrar no ar',
      () => it.estado.btClipRodando,
    );
    await theClipOpens(it.harness);
    it.harness.playback.at = const Duration(seconds: 4);
    it.sala.ouvirGravacao();
    await waitFor('a segunda parte parar', () => !it.estado.btClipRodando);
    final primeira = it.partes[0].takeId!;
    final segunda = it.partes[1].takeId!;
    final relatos = it.harness.room.listeningReports.length;
    it.harness.room.holdTheGrainSwitch();

    it.sala.recordTheWholePassage();
    await waitFor(
      'a porta da sala ser chamada',
      () => it.harness.room.grainSwitches.isNotEmpty,
    );

    expect(
      it.harness.room.listeningReports.skip(relatos),
      [
        [
          {
            'take_id': primeira,
            'played_ranges': [
              [0, 10000],
            ],
            'clip_duration_ms': 10000,
          },
          {
            'take_id': segunda,
            'played_ranges': [
              [0, 4000],
            ],
            'clip_duration_ms': 0,
          },
        ],
      ],
      reason:
          'a troca tirava as partes antes do relato, e o que soou da '
          'segunda parte nunca chegava à sala',
    );
    it.harness.room.finishTheGrainSwitch();
    await settle();
  });
}
