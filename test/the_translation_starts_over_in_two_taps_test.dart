import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aprovar,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        ouvir,
        tocar,
        tocarNoCirculo;
import 'session_notifier_test.dart'
    show inConversaWithoutPausing, tellTwoStretches;

const _recomecar = 'recomeçar a tradução';
const _armado = 'toque de novo para apagar as 4 frases traduzidas';
const _naoDeu = 'não deu para recomeçar agora — tentem de novo';
const _semFrase = 'ainda não tem frase traduzida';
const _naoEntendi = 'não entendi — traduzam de novo esse pedaço';
const _ensaioSalvo = 'Ensaio salvo';
const _pronto = 'Pronto';
const _recomecada = 'tradução recomeçada — o ensaio da passagem ficou';

const _quatroFrases = [
  SegmentView(
    segmentId: 'trecho-1',
    takeId: 'gravacao-1',
    startsMs: 0,
    endsMs: 4000,
    frase: 1,
  ),
  SegmentView(
    segmentId: 'trecho-2',
    takeId: 'gravacao-1',
    startsMs: 4000,
    endsMs: 9000,
    frase: 2,
  ),
  SegmentView(
    segmentId: 'trecho-3',
    takeId: 'gravacao-2',
    startsMs: 0,
    endsMs: 6000,
    frase: 3,
  ),
  SegmentView(
    segmentId: 'trecho-4',
    takeId: 'gravacao-2',
    startsMs: 6000,
    endsMs: 8000,
    frase: 4,
  ),
];

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

double _drawnAt(WidgetTester tester, String label) => tester
    .widgetList<Opacity>(
      find.descendant(of: byLabel(label), matching: find.byType(Opacity)),
    )
    .fold(1.0, (opacity, veil) => opacity * veil.opacity);

Tristate _enabledAt(WidgetTester tester, String label) => tester
    .getSemantics(byLabel(label))
    .getSemanticsData()
    .flagsCollection
    .isEnabled;

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  List<SegmentView> frases,
) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final pasta = Directory.systemTemp.createTempSync('sala-1223');
  addTearDown(() => pasta.deleteSync(recursive: true));
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      for (final n in [1, 2])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: (File(
            '${pasta.path}/p$n.m4a',
          )..writeAsBytesSync([1, 2, 3])).path,
          takeId: 'gravacao-$n',
        ),
    ],
  );
  harness.room.retroSoFar = BackTranslationProgress(segments: frases);
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
  await waitFor(
    'a tradução voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length == frases.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _contadaAoVivo(
  WidgetTester tester,
  SalaHarness harness,
) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await gravarATraducao(tester);
  await waitFor(
    'a primeira frase chegar',
    () => container.read(salaSessionProvider).btTrechos.length == 1,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<void> _recomecarNaTela(
  WidgetTester tester,
  ProviderContainer container,
  String armado,
) async {
  await tocar(tester, _recomecar);
  await tester.pump(const Duration(milliseconds: 700));
  await tocar(tester, armado);
  await waitFor(
    'a tradução recomeçar',
    () => container.read(salaSessionProvider).btTrechos.isEmpty,
    step: () => _passo(tester),
  );
  await tester.pump(const Duration(seconds: 7));
}

void main() {
  testWidgets(
    'the screen offers «recomeçar a tradução» under the frases, and not before there is one',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      expect(
        byLabel(_recomecar),
        findsOneWidget,
        reason: 'não havia como recomeçar a tradução sem gravar de novo',
      );
      expect(
        find.text(_recomecar),
        findsOneWidget,
        reason: 'a palavra dela fica escrita no botão',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the first tap only arms it, and the button says what the second one costs',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);

      expect(
        find.text(_armado),
        findsOneWidget,
        reason: 'um toque só apagava as frases sem dizer o custo',
      );
      expect(byLabel(_armado), findsOneWidget);
      expect(harness.room.restartsAsked, isEmpty);
      expect(container.read(salaSessionProvider).btTrechos, hasLength(4));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a second tap before 0.6 s is the same touch, and starts nothing over',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byLabel(_armado));
      await _passo(tester);

      expect(
        harness.room.restartsAsked,
        isEmpty,
        reason: 'um toque duplo apagava as frases sem a equipe decidir',
      );
      expect(find.text(_armado), findsOneWidget);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the armed button is drawn dimmed and disabled while it is still asleep',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_armado), findsOneWidget);
      expect(
        _drawnAt(tester, _armado),
        0.4,
        reason:
            'o botão armado aparecia aceso e não fazia nada por meio segundo',
      );
      expect(
        _enabledAt(tester, _armado),
        Tristate.isFalse,
        reason:
            'o leitor de tela anunciava um botão que ainda ignorava o toque',
      );
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the armed button is lit once it wakes and stays lit for the rest of the window',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text(_armado), findsOneWidget);
      expect(
        _drawnAt(tester, _armado),
        1.0,
        reason: 'o botão ficava apagado a janela inteira, depois de acordar',
      );
      expect(_enabledAt(tester, _armado), Tristate.isTrue);

      await tester.pump(const Duration(seconds: 5));

      expect(find.text(_armado), findsOneWidget);
      expect(_drawnAt(tester, _armado), 1.0);
      expect(_enabledAt(tester, _armado), Tristate.isTrue);
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(container);
    },
  );

  testWidgets('after six seconds the button is back to its own words and lit', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await _voltaATraducao(tester, harness, _quatroFrases);

    await tester.tap(byLabel(_recomecar));
    await tester.pump(const Duration(milliseconds: 6100));

    expect(find.text(_recomecar), findsOneWidget);
    expect(find.text(_armado), findsNothing);
    expect(
      _drawnAt(tester, _recomecar),
      1.0,
      reason: 'o botão voltava às palavras dele ainda apagado',
    );
    expect(_enabledAt(tester, _recomecar), Tristate.isTrue);
    closeTheRoom(container);
  });

  testWidgets(
    'one tap and then seven seconds of nothing leave it disarmed, with nothing changed',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);
      await tester.pump(const Duration(seconds: 7));

      expect(
        find.text(_recomecar),
        findsOneWidget,
        reason: 'o botão ficava armado para sempre, e um toque tardio apagava',
      );
      expect(find.text(_armado), findsNothing);
      expect(harness.room.restartsAsked, isEmpty);
      expect(container.read(salaSessionProvider).btTrechos, hasLength(4));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a translation started over says so under the circle for six seconds',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byLabel(_armado));
      await waitFor(
        'a tradução recomeçar',
        () => container.read(salaSessionProvider).btTrechos.isEmpty,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        find.text(_recomecada),
        findsOneWidget,
        reason: 'as frases sumiam da tela sem nada dizer o que aconteceu',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(_recomecada), findsNothing);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a restart the room refuses keeps every frase and says so in her words',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);
      harness.room.failRestartWith = const Refused('HTTP_409');

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byLabel(_armado));
      await waitFor(
        'a sala recusar o recomeço',
        () => harness.room.restartsAsked.isNotEmpty,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        find.text(_naoDeu),
        findsOneWidget,
        reason: 'o recomeço falhava calado e a equipe esperava à toa',
      );
      expect(container.read(salaSessionProvider).btTrechos, hasLength(4));
      expect(find.text(_recomecar), findsOneWidget);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'starting over takes the refusal of the last «terminei» off the screen',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _contadaAoVivo(tester, harness);
      await contarAteOFimDaParte(tester, harness);
      harness.room.verdictRefusal = CheckRefusal.nothingTranslated;
      await tocar(tester, conferir);
      await waitFor(
        'a recusa voltar',
        () => container.read(salaSessionProvider).btRecusa != null,
        step: () => _passo(tester),
      );
      await _passo(tester);
      expect(find.text(_semFrase), findsOneWidget);

      await _recomecarNaTela(
        tester,
        container,
        'toque de novo para apagar as 2 frases traduzidas',
      );

      expect(
        find.text(_semFrase),
        findsNothing,
        reason: 'a recusa de antes do recomeço voltava à tela depois da nota',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('starting over takes «não entendi» off the screen', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _contadaAoVivo(tester, harness);
    harness.room.failChunkWith = const Refused(RefusalCode.wordlessTelling);
    harness.playback.at = const Duration(seconds: 7);
    await tester.pump(const Duration(seconds: 1));
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    await waitFor(
      'a fala vazia voltar',
      () => container.read(salaSessionProvider).wordlessTelling,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(find.text(_naoEntendi), findsOneWidget);
    harness.room.failChunkWith = null;

    await _recomecarNaTela(
      tester,
      container,
      'toque de novo para apagar as 1 frases traduzidas',
    );

    expect(
      find.text(_naoEntendi),
      findsNothing,
      reason: 'o «não entendi» de antes do recomeço ficava na tela',
    );
    closeTheRoom(container);
  });

  testWidgets('a restart tapped while a frase is being recorded arms nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _contadaAoVivo(tester, harness);
    harness.playback.at = const Duration(seconds: 7);
    await tester.pump(const Duration(seconds: 1));
    await tocarNoCirculo(tester);
    await tocar(
      tester,
      'a pausa ficou no toque — toquem no círculo para traduzir',
    );
    await waitFor(
      'o microfone abrir',
      () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
      step: () => _passo(tester),
    );

    await tocar(tester, _recomecar);

    expect(
      container.read(salaSessionProvider).btRecomeco,
      isNull,
      reason: 'o recomeço armava por cima de uma frase sendo gravada',
    );
    expect(find.text(_recomecar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets(
    'a restart tapped while a frase is on its way to the room arms nothing',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _contadaAoVivo(tester, harness);
      harness.room.holdNextChunk();
      harness.playback.at = const Duration(seconds: 7);
      await tester.pump(const Duration(seconds: 1));
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await waitFor(
        'a frase ir para a sala',
        () => container.read(salaSessionProvider).btPhase == BtPhase.thinking,
        step: () => _passo(tester),
      );

      await tocar(tester, _recomecar);

      expect(
        container.read(salaSessionProvider).btRecomeco,
        isNull,
        reason: 'o recomeço armava com uma frase ainda a caminho da sala',
      );
      harness.room.finishHeldChunk();
      await _passo(tester);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the marks of the last check leave with the frases, and the new frase 1 carries none',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _contadaAoVivo(tester, harness);
      await contarAteOFimDaParte(tester, harness);
      harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true
        ..verdictFindingSegmentId = 'trecho-1'
        ..verdictFindings = const [
          BtFinding(
            kind: BtFindingKind.addition,
            frase: 1,
            segmentId: 'trecho-1',
          ),
        ];
      await tocar(tester, conferir);
      await waitFor(
        'a marca chegar',
        () => container.read(salaSessionProvider).btFindings.isNotEmpty,
        step: () => _passo(tester),
      );
      await _passo(tester);
      expect(find.text('acrescentado'), findsOneWidget);

      await _recomecarNaTela(
        tester,
        container,
        'toque de novo para apagar as 2 frases traduzidas',
      );
      harness.playback.at = cabeca;
      await tester.pump(const Duration(seconds: 1));
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await waitFor(
        'a nova frase 1 chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 1,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        find.text('acrescentado'),
        findsNothing,
        reason: 'a marca da conferência de antes caía na nova frase 1',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'an arm left when the telling is entered again goes with it, never stays armed',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);
      container.read(salaSessionProvider.notifier).startRetro();
      await waitFor(
        'a tradução abrir de novo',
        () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
        step: () => _passo(tester),
      );
      await tester.pump(const Duration(seconds: 7));

      expect(
        container.read(salaSessionProvider).btRecomeco,
        isNull,
        reason: 'o recomeço ficava armado para sempre depois de sair e voltar',
      );
      expect(find.text(_recomecar), findsOneWidget);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);
      expect(find.text(_armado), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'an armed restart is idle once «Pronto» leaves the Saved screen, and one tap arms it again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.verdictChecked = true;
      final container = await _contadaAoVivo(tester, harness);
      await contarAteOFimDaParte(tester, harness);
      await tocar(tester, conferir);
      await waitFor(
        'a sala conferir',
        () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
        step: () => _passo(tester),
      );
      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      expect(container.read(salaSessionProvider).btRecomeco, BtRecomeco.pronto);

      harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await tocar(tester, aprovar);
      await waitFor(
        'o ensaio salvo',
        () => find.text(_ensaioSalvo).evaluate().isNotEmpty,
        step: () => _passo(tester),
      );
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        find.text(_recomecar),
        findsOneWidget,
        reason: 'o recomeço armado antes da aprovação voltava armado',
      );
      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      expect(container.read(salaSessionProvider).btRecomeco, BtRecomeco.pronto);
      expect(harness.room.restartsAsked, isEmpty);
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a second tap in time starts the translation over once and leaves nothing armed',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byLabel(_armado));
      await waitFor(
        'a sala receber o recomeço',
        () => harness.room.restartsAsked.isNotEmpty,
        step: () => _passo(tester),
      );
      await tester.pump(const Duration(seconds: 7));

      expect(harness.room.restartsAsked, hasLength(1));
      expect(container.read(salaSessionProvider).btRecomeco, isNull);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'her failure line leaves on the next tap of the button and when a frase is told',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _contadaAoVivo(tester, harness);
      harness.room.failRestartWith = const Refused('HTTP_409');
      await tocar(tester, _recomecar);
      await tester.pump(const Duration(milliseconds: 700));
      await tocar(tester, 'toque de novo para apagar as 1 frases traduzidas');
      await waitFor(
        'a sala recusar o recomeço',
        () => container.read(salaSessionProvider).btAviso != null,
        step: () => _passo(tester),
      );
      await _passo(tester);
      expect(find.text(_naoDeu), findsOneWidget);

      await tocar(tester, _recomecar);
      expect(
        find.text(_naoDeu),
        findsNothing,
        reason: 'a falha de antes ficava escrita por cima do botão armado',
      );

      await tester.pump(const Duration(seconds: 7));
      await tocar(tester, _recomecar);
      await tester.pump(const Duration(milliseconds: 700));
      await tocar(tester, 'toque de novo para apagar as 1 frases traduzidas');
      await waitFor(
        'a sala recusar de novo',
        () => container.read(salaSessionProvider).btAviso != null,
        step: () => _passo(tester),
      );
      await tocar(tester, ouvir);
      harness.playback.at = const Duration(seconds: 7);
      await tester.pump(const Duration(seconds: 1));
      await tocarNoCirculo(tester);
      await gravarATraducao(tester);
      await waitFor(
        'a segunda frase chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 2,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        find.text(_naoDeu),
        findsNothing,
        reason: 'a falha do recomeço ficava na tela a passagem inteira',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the rows after a restart are the ones the room answers with, never a list the tablet empties',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);
      harness.room.standingAfterRestart = const [
        SegmentView(
          segmentId: 'trecho-9',
          takeId: 'gravacao-2',
          startsMs: 0,
          endsMs: 3000,
        ),
      ];

      await tester.tap(byLabel(_recomecar));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byLabel(_armado));
      await waitFor(
        'a sala responder o recomeço',
        () => harness.room.restartsAsked.isNotEmpty,
        step: () => _passo(tester),
      );
      await tester.pump(const Duration(seconds: 7));

      expect(
        [
          for (final trecho in container.read(salaSessionProvider).btTrechos)
            trecho.segmentId,
        ],
        ['trecho-9'],
        reason:
            'a tela apagava as linhas por conta própria em vez de ler a sala',
      );
      expect(
        find.descendant(of: find.byType(FraseList), matching: find.text('1')),
        findsOneWidget,
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a second tap five seconds after the first still starts the translation over',
    (tester) async {
      final harness = SalaHarness();
      final container = await _voltaATraducao(tester, harness, _quatroFrases);

      await tester.tap(byLabel(_recomecar));
      await _passo(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(byLabel(_armado));
      await waitFor(
        'a sala ser chamada',
        () => harness.room.restartsAsked.isNotEmpty,
        step: () => _passo(tester),
      );

      expect(
        harness.room.restartsAsked,
        hasLength(1),
        reason: 'o botão desarmava antes dos seis segundos dela',
      );
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(container);
    },
  );

  testWidgets('with no frase told there is nothing to start over', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await _voltaATraducao(tester, harness, const []);

    expect(byLabel(_recomecar), findsNothing);
    closeTheRoom(container);
  });

  test(
    'a second tap starts the translation over: the frases go, P1 is said, and the next frase is the first of part 1',
    () async {
      final harness = SalaHarness();
      final container = await inConversaWithoutPausing(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await tellTwoStretches(harness, container);

      notifier.recomecarATraducao();
      await settle(const Duration(milliseconds: 700));
      notifier.recomecarATraducao();
      await waitFor(
        'a tradução recomeçar',
        () =>
            harness.room.restartsAsked.isNotEmpty &&
            container.read(salaSessionProvider).btTrechos.isEmpty,
      );

      expect(harness.room.restartsAsked, hasLength(1));
      expect(
        container.read(salaSessionProvider).btTrechos,
        isEmpty,
        reason: 'as frases de antes continuavam na tela depois do recomeço',
      );
      await waitFor(
        'a voz dizer P1',
        () => harness.voice.fixedLines.any((line) => line.$1 == 'P1'),
      );
      expect(
        [for (final line in harness.voice.fixedLines) line.$1],
        contains('P1'),
        reason: 'o recomeço não dizia a instrução de traduzir',
      );

      await waitFor('o clipe voltar a rodar', () {
        final estado = container.read(salaSessionProvider);
        return estado.btPhase == BtPhase.playing &&
            estado.btClipRodando &&
            !estado.btCortado &&
            estado.btTraducaoPendente == null;
      });
      final enviados = harness.room.chunkSpans.length;
      harness.playback.at = const Duration(seconds: 5);
      notifier.retroTap();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await waitFor(
        'a primeira frase do recomeço chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 1,
      );

      expect(
        harness.room.chunkSpans.sublist(enviados).first,
        startsWith('0-'),
        reason: 'a frase nova começava onde a antiga terminava',
      );
      expect(
        container.read(salaSessionProvider).btTrechos.single.frase,
        1,
        reason: 'a numeração continuava de onde parou',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    },
  );
}
