import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, voiceOverTap;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        contarAteOFimDaParte,
        entrarNaTraducao,
        parte,
        tocar,
        tocarNoCirculo;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _cortes = [
  [Duration(seconds: 3), Duration(seconds: 6)],
  [
    Duration(milliseconds: 2500),
    Duration(seconds: 5),
    Duration(milliseconds: 7500),
  ],
];

Future<ProviderContainer> _seteFrasesContadas(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness);
  var contadas = 0;
  for (final cortes in _cortes) {
    for (final corte in cortes) {
      harness.playback.at = corte;
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
      await tocarNoCirculo(tester);
    }
    await contarAteOFimDaParte(tester, harness);
    contadas += cortes.length + 1;
    await waitFor(
      '$contadas frases ficarem contadas',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          contadas,
      step: () => _passo(tester),
    );
  }
  return container;
}

Future<void> _terminei(
  WidgetTester tester,
  ProviderContainer container,
  BtPhase chega,
) async {
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == chega,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

Future<ProviderContainer> _quatroFrasesContadas(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness);
  for (final corte in _cortes.first) {
    harness.playback.at = corte;
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
  }
  await contarAteOFimDaParte(tester, harness);
  harness.playback.at = _cortes.last.first;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await waitFor(
    '4 frases ficarem contadas',
    () =>
        container
            .read(salaSessionProvider)
            .btTrechos
            .where((trecho) => trecho.contado)
            .length ==
        4,
    step: () => _passo(tester),
  );
  return container;
}

Future<ProviderContainer> _vereditoNaFraseTres(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _seteFrasesContadas(tester, harness);
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 2
    ..verdictFindings = const [
      BtFinding(kind: BtFindingKind.addition, frase: 3, segmentId: 'trecho-3'),
    ];
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btVeredito,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _seteFrasesConferidas(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _seteFrasesContadas(tester, harness);
  harness.room
    ..verdictChecked = true
    ..verdictFindings = const [];
  await _terminei(tester, container, BtPhase.conferida);
  return container;
}

Future<ProviderContainer> _voltaAUmaTraducao(
  WidgetTester tester,
  SalaHarness harness, {
  required bool conferida,
}) async {
  _telaAlta(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1220');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final partes = [
    for (final n in [1, 2])
      KeptTake(
        scopeId: KeptScope.parte(n),
        path: (File('${pasta.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-$n',
      ),
  ];
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: partes,
  );
  harness.room.retroSoFar = BackTranslationProgress(
    checked: conferida,
    segments: const [
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
  await waitFor(
    'a tradução voltar com as duas frases',
    () =>
        container.read(salaSessionProvider).btTrechos.length == 2 &&
        container.read(salaSessionProvider).btPhase ==
            (conferida ? BtPhase.conferida : BtPhase.playing),
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _aprovar = 'Aprovar como rascunho final';

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

Future<void> _traduzirDeNovo(
  WidgetTester tester,
  ProviderContainer container, {
  String circulo = 'ouvindo a gravação de vocês…',
}) async {
  await tocar(tester, circulo);
  await tocar(tester, 'Tocar ao terminar');
  await _passo(tester);
  await waitFor(
    'a frase traduzida de novo pousar',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

void main() {
  testWidgets('a frase told again goes up on the tap that closes its '
      'microphone, with no confirm', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      conferida: true,
    );

    await tocar(tester, _barra(2));
    await tocar(tester, 'ouvindo a gravação de vocês…');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    await tocar(tester, 'Tocar ao terminar');
    await waitFor(
      'a frase traduzida de novo subir',
      () => harness.room.replacesAsked.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.replacesAsked,
      ['trecho-2@gravacao-2:0-5000'],
      reason:
          'o toque que fechava o microfone deixava a tradução esperando o '
          'botão verde',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict naming frase 3, a tap on frase 7 replays its '
      'piece and asks for the circle', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final parteDois = container.read(salaSessionProvider).partes[1].path;

    expect(
      byLabel(_barra(7)),
      findsOneWidget,
      reason: 'depois do veredito a frase 7 não aceitava toque',
    );
    final tocadas = harness.playback.played.length;
    await tocar(tester, _barra(7));

    expect(
      harness.playback.played.skip(tocadas),
      [parteDois],
      reason: 'o toque na frase não tocava o pedaço dela na gravação',
    );
    expect(harness.playback.ranges, ['7500-10000']);
    expect(
      find.text('traduzindo de novo a frase 7 — toquem no círculo'),
      findsOneWidget,
      reason: 'a tela não dizia qual frase estava sendo traduzida de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('frase 3 replayed to the end of its part stops there, not on '
      'into the next part', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final parteUm = container.read(salaSessionProvider).partes[0].path;
    final tocadas = harness.playback.played.length;
    await tocar(tester, _barra(3));
    expect(harness.playback.ranges, ['6000-10000']);

    harness.playback.finishPlayback();
    await _passo(tester);

    expect(
      harness.playback.played.skip(tocadas),
      [parteUm],
      reason: 'a frase tocada de novo no fim da parte seguia para a próxima',
    );
    expect(container.read(salaSessionProvider).btClipRodando, isFalse);
    closeTheRoom(container);
  });

  testWidgets('the circle after a tap on frase 7 tells exactly its span '
      'again through the replace door, not as a new frase', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final pedacos = harness.room.chunksSent;

    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);

    expect(
      harness.room.replacesAsked,
      ['trecho-7@gravacao-2:7500-10000'],
      reason: 'a nova tradução não ia pela porta de substituir a frase 7',
    );
    expect(
      harness.room.chunksSent,
      pedacos,
      reason: 'a frase traduzida de novo subia como uma frase nova',
    );
    closeTheRoom(container);
  });

  testWidgets('frase 7 told again keeps its number and the other marks, and '
      'no check starts until the team says terminei', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);
    for (var passo = 0; passo < 10; passo++) {
      await _passo(tester);
    }

    expect(
      harness.room.playedByTakeSent,
      hasLength(1),
      reason:
          'a sala pedia uma conferência sozinha depois da frase traduzida '
          'de novo',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 1',
      'acrescentado',
      '4',
      'parte 2',
      '5',
      'parte 2',
      '6',
      'parte 2',
      '7',
      'parte 2',
    ]);
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» leaves the earlier translation '
      'and the verdict, with nothing recorded', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final antes = container.read(salaSessionProvider).btTrechos[6];
    final pedacos = harness.room.chunksSent;
    final capturas = harness.recorder.captures;

    await tocar(tester, _barra(7));
    expect(
      byLabel('manter a tradução de antes'),
      findsOneWidget,
      reason: 'a frase tocada não tinha como voltar atrás',
    );
    await tocar(tester, 'manter a tradução de antes');
    for (var passo = 0; passo < 10; passo++) {
      await _passo(tester);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      estado.btPhase,
      BtPhase.playing,
      reason:
          'manter a tradução de antes voltava a um passo de achados que o '
          'relato dela não tem',
    );
    expect(estado.btVeredito, isTrue);
    expect(estado.btTrechoTraduzidoDeNovo, isNull);
    expect(estado.btTrechos[6].retroPath, antes.retroPath);
    expect(harness.room.replacesAsked, isEmpty);
    expect(harness.room.chunksSent, pedacos);
    expect(harness.recorder.captures, capturas);
    expect(
      find.text('traduzindo de novo a frase 7 — toquem no círculo'),
      findsNothing,
    );
    expect(byLabel('manter a tradução de antes'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a conferida telling with frase 2 told again is no longer '
      'conferida, until a new clean check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(2));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      2,
      reason: 'na tradução conferida a frase 2 não abria para traduzir de novo',
    );
    await _traduzirDeNovo(tester, container);

    expect(
      container.read(salaSessionProvider).btPhase,
      isNot(BtPhase.conferida),
      reason: 'a tela seguia dizendo conferida com a frase 2 traduzida de novo',
    );
    expect(byLabel(_aprovar), findsNothing);

    await _terminei(tester, container, BtPhase.conferida);

    expect(byLabel(_aprovar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» on a conferida telling leaves it '
      'conferida, with its approval', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(5));
    expect(
      container.read(salaSessionProvider).btPhase,
      isNot(BtPhase.conferida),
    );
    await tocar(tester, 'manter a tradução de antes');
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'desistir de traduzir de novo tirava a tradução de conferida',
    );
    expect(byLabel(_aprovar), findsOneWidget);
    expect(harness.room.replacesAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('after a frase is told again the verdict still stands: the '
      'sub-line is the verdict\'s and another frase still opens', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(2));
    await _traduzirDeNovo(tester, container);

    expect(
      find.text(
        'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar '
        'uma parte; ou toquem em terminei para conferir de novo.',
      ),
      findsOneWidget,
      reason:
          'a tela esquecia o veredito depois da primeira frase traduzida '
          'de novo',
    );
    await tocar(tester, _barra(5));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      5,
      reason: 'depois de uma frase traduzida de novo as outras não abriam mais',
    );
    closeTheRoom(container);
  });

  testWidgets('a conferida session picked back up still stands on its '
      'verdict after a frase is told again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      conferida: true,
    );

    await tocar(tester, _barra(1));
    await _traduzirDeNovo(
      tester,
      container,
      circulo: 'ouvindo a gravação de vocês…',
    );

    expect(
      find.text(
        'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar '
        'uma parte; ou toquem em terminei para conferir de novo.',
      ),
      findsOneWidget,
      reason: 'a sessão retomada esquecia o veredito que a leitura trazia',
    );
    await tocar(tester, _barra(2));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      2,
    );
    closeTheRoom(container);
  });

  testWidgets('three rounds in a row: each terminei is sent like the first, '
      'and only terminei sends one', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);
    expect(harness.room.playedByTakeSent, hasLength(1));
    await _terminei(tester, container, BtPhase.playing);

    await tocar(tester, _barra(3));
    await _traduzirDeNovo(tester, container);
    expect(harness.room.playedByTakeSent, hasLength(2));
    await _terminei(tester, container, BtPhase.playing);

    expect(
      harness.room.playedByTakeSent,
      hasLength(3),
      reason: 'o terceiro terminei não chegava à sala como o primeiro',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict with findings «terminei» stays lit, and a tap '
      'on it sends a new check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    expect(
      byLabel('terminei'),
      findsOneWidget,
      reason:
          'depois de um veredito com achado o terminei sumia até a equipe '
          'contar alguma frase de novo',
    );
    expect(aceso(tester, 'terminei'), isTrue);
    await tocar(tester, 'terminei');
    await waitFor(
      'a nova conferência chegar à sala',
      () => harness.room.playedByTakeSent.length == 2,
      step: () => _passo(tester),
    );
    expect(
      harness.room.playedByTakeSent,
      hasLength(2),
      reason: 'o terminei depois do veredito não pedia uma nova conferência',
    );
    closeTheRoom(container);
  });

  testWidgets('while the verdict is heard again «terminei» is dimmed and a tap '
      'sends no check, not a check that cuts the voice', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    harness.voice.holdNextLine();
    await tocar(tester, 'ouvir a resposta de novo');
    await waitFor(
      'a resposta falar de novo',
      () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      step: () => _passo(tester),
    );

    expect(
      aceso(tester, 'terminei'),
      isFalse,
      reason:
          'o terminei ficava aceso enquanto a voz repetia o veredito, e o '
          'dela fica fechado enquanto a voz fala',
    );
    await tester.tap(byLabel('terminei'));
    await _passo(tester);
    expect(
      harness.room.playedByTakeSent,
      hasLength(1),
      reason: 'o toque cortava a voz e pedia uma nova conferência',
    );

    harness.voice.finishHeldLine();
    await waitFor(
      'a voz terminar',
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(aceso(tester, 'terminei'), isTrue);
    closeTheRoom(container);
  });

  testWidgets('after a verdict with findings a frase row opens its frase to '
      'be told again, as it does before a verdict', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    await tocar(tester, _barra(5));
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      5,
      reason:
          'depois do veredito com achado a frase ficava muda, e antes '
          'dele abria para traduzir de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict with findings the screen offers none of the '
      'controls her telling does not have', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    expect(
      byLabel('Ouvir o trecho e a tradução'),
      findsNothing,
      reason: 'o achado abria um passo nosso com um play que ela não tem',
    );
    expect(
      byLabel('Traduzir este trecho de novo'),
      findsNothing,
      reason:
          'o achado abria um passo nosso com um microfone azul que ela não tem',
    );
    closeTheRoom(container);
  });

  testWidgets('after a verdict that names a stretch, «voltar e regravar uma '
      'parte» is a written button, and it takes the team to the rehearsal', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    expect(
      find.text('voltar e regravar uma parte'),
      findsOneWidget,
      reason:
          'a volta ao ensaio era um microfone sem palavra, e na tela dela '
          'é um botão escrito',
    );
    await tocar(tester, 'voltar e regravar uma parte');

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.ensaio,
      reason: 'sem os três botões do achado a retro não tinha volta ao ensaio',
    );
    closeTheRoom(container);
  });

  testWidgets('after a clean verdict «ouvir a resposta de novo» shows and '
      'plays that verdict again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);
    final faladas = harness.voice.played.length;

    expect(
      find.text('ouvir a resposta de novo'),
      findsOneWidget,
      reason:
          'depois de um veredito limpo a equipe não tinha como ouvi-lo de novo',
    );
    await tocar(tester, 'ouvir a resposta de novo');
    await waitFor(
      'a resposta tocar de novo',
      () => harness.voice.played.length == faladas + 1,
      step: () => _passo(tester),
    );

    expect(harness.voice.played.last, falaDoVeredito);
    closeTheRoom(container);
  });

  testWidgets(
    'after a verdict with findings «ouvir a resposta de novo» still '
    'shows once a frase is told again, and plays the verdict, not the retell',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _vereditoNaFraseTres(tester, harness);
      await tocar(tester, _barra(7));
      await _traduzirDeNovo(tester, container);
      final faladas = harness.voice.played.length;

      expect(
        find.text('ouvir a resposta de novo'),
        findsOneWidget,
        reason:
            'a resposta só se ouvia de novo até a equipe começar a traduzir '
            'uma frase de novo',
      );
      await tocar(tester, 'ouvir a resposta de novo');
      await waitFor(
        'a resposta tocar de novo',
        () => harness.voice.played.length == faladas + 1,
        step: () => _passo(tester),
      );

      expect(harness.voice.played.last, falaDoVeredito);
      closeTheRoom(container);
    },
  );

  testWidgets('«recomeçar a tradução» takes «ouvir a resposta de novo» away', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(find.text('ouvir a resposta de novo'), findsOneWidget);

    notifier.recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 700));
    notifier.recomecarATraducao();
    await waitFor(
      'a tradução recomeçar',
      () => harness.room.restartsAsked.isNotEmpty,
      step: () => _passo(tester),
    );
    await _passo(tester);

    expect(
      find.text('ouvir a resposta de novo'),
      findsNothing,
      reason: 'a tradução recomeçada ainda oferecia a resposta de antes',
    );
    closeTheRoom(container);
  });

  testWidgets('a new «terminei» puts its own verdict behind «ouvir a resposta '
      'de novo», not the one before it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.verdictCheckAt = 'primeira';
    final container = await _vereditoNaFraseTres(tester, harness);
    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);
    harness.room.verdictCheckAt = 'segunda';
    await _terminei(tester, container, BtPhase.playing);
    final faladas = harness.voice.played.length;

    await tocar(tester, 'ouvir a resposta de novo');
    await waitFor(
      'a resposta tocar de novo',
      () => harness.voice.played.length == faladas + 1,
      step: () => _passo(tester),
    );

    expect(
      harness.room.heardStamps.last,
      'segunda',
      reason: 'o botão repetia o veredito da conferência anterior',
    );
    closeTheRoom(container);
  });

  testWidgets('a VoiceOver double-tap on «ouvir a resposta de novo» plays the '
      'verdict again, and the resting button offers no tap', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const []
      ..verdictNamedNuance = const BtFinding(
        kind: BtFindingKind.nuance,
        frase: 4,
        segmentId: 'trecho-4',
      );
    await _terminei(tester, container, BtPhase.conferida);
    final faladas = harness.voice.played.length;

    harness.voice.holdNextLine();
    voiceOverTap(tester, 'ouvir a resposta de novo');
    await _passo(tester);
    expect(
      harness.voice.played,
      hasLength(faladas + 1),
      reason:
          'o VoiceOver anunciava o botão e o toque duplo não repetia a resposta',
    );
    expect(
      tester.getSemantics(byLabel('ouvir a resposta de novo')),
      isSemantics(hasTapAction: false),
      reason: 'com a resposta soando o botão apagado ainda aceitava o toque',
    );
    harness.voice.finishHeldLine();
    await _passo(tester);
    await _passo(tester);
    closeTheRoom(container);
    semantics.dispose();
  });

  testWidgets('«ouvir a resposta de novo» rests while the verdict sounds and '
      'while a sentence is recorded again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const []
      ..verdictNamedNuance = const BtFinding(
        kind: BtFindingKind.nuance,
        frase: 4,
        segmentId: 'trecho-4',
      );
    await _terminei(tester, container, BtPhase.conferida);
    bool? acesa() => tester
        .widget<Semantics>(byLabel('ouvir a resposta de novo'))
        .properties
        .enabled;
    expect(acesa(), isTrue);

    harness.voice.holdNextLine();
    await tocar(tester, 'ouvir a resposta de novo');
    expect(
      acesa(),
      isFalse,
      reason: 'o botão aceitava outro toque com a resposta ainda soando',
    );
    harness.voice.finishHeldLine();
    await _passo(tester);
    await _passo(tester);
    expect(acesa(), isTrue);

    await tester.ensureVisible(find.text('regravar a frase 4'));
    await tester.tap(find.text('regravar a frase 4'));
    await _passo(tester);
    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);
    expect(
      container.read(salaSessionProvider).btRegravacao?.passo,
      PassoDaRegravacao.pronta,
    );
    expect(
      acesa(),
      isFalse,
      reason: 'com uma frase sendo regravada a resposta podia tocar por cima',
    );
    closeTheRoom(container);
  });

  testWidgets('«ouvir a resposta de novo» rests while the recording, a '
      'translation or a stretch sounds', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState estado() => container.read(salaSessionProvider);
    bool? acesa() => tester
        .widget<Semantics>(byLabel('ouvir a resposta de novo'))
        .properties
        .enabled;
    expect(acesa(), isTrue);

    notifier.ouvirGravacao();
    await waitFor(
      'a gravação tocar',
      () => estado().btClipRodando,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(acesa(), isFalse, reason: 'a resposta tocava por cima da gravação');
    notifier.ouvirGravacao();
    await waitFor(
      'a gravação parar',
      () => !estado().btClipRodando,
      step: () => _passo(tester),
    );

    notifier.ouvirOTrechoContado(0);
    await waitFor(
      'a tradução da frase tocar',
      () => estado().btRetroTocando,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(acesa(), isFalse, reason: 'a resposta tocava por cima da tradução');
    harness.playback.finishPlayback();
    await waitFor(
      'a tradução parar',
      () => !estado().btRetroTocando,
      step: () => _passo(tester),
    );

    await tocar(tester, _barra(2));
    await waitFor(
      'o trecho da frase tocar',
      () => estado().btTrechoTocando,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(acesa(), isFalse, reason: 'a resposta tocava por cima do trecho');
    closeTheRoom(container);
  });

  testWidgets('«voltar e regravar uma parte» rests while a frase is being told '
      'again, instead of taking a tap it would drop', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    await tocar(tester, _barra(7));
    await tocar(tester, 'ouvindo a gravação de vocês…');

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      tester
          .widget<Semantics>(byLabel('voltar e regravar uma parte'))
          .properties
          .enabled,
      isFalse,
      reason:
          'com o microfone aberto o botão ficava aceso e o toque não levava '
          'a lugar nenhum',
    );
    closeTheRoom(container);
  });

  testWidgets('a tap on «regravar a frase 4» is that button\'s, never the '
      'row\'s retell', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room
      ..verdictChecked = true
      ..verdictFindings = const []
      ..verdictNamedNuance = const BtFinding(
        kind: BtFindingKind.nuance,
        frase: 4,
        segmentId: 'trecho-4',
      );
    await _terminei(tester, container, BtPhase.conferida);

    await tester.ensureVisible(find.text('regravar a frase 4'));
    await tester.tap(find.text('regravar a frase 4'));
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo,
      isNull,
      reason: 'o toque em regravar a frase abria a frase para traduzir de novo',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    closeTheRoom(container);
  });

  testWidgets('before any verdict a tap on a frase of a telling picked back up '
      'opens it to be told again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducao(
      tester,
      harness,
      conferida: false,
    );
    final parteDois = container.read(salaSessionProvider).partes[1].path;
    final tocadas = harness.playback.played.length;
    final trechos = harness.playback.ranges.length;

    await tocar(tester, _barra(2));

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.segmentId,
      'trecho-2',
      reason:
          'antes de qualquer conferência a frase não abria para traduzir de '
          'novo, e a dela abre',
    );
    expect(harness.playback.played.skip(tocadas), [parteDois]);
    expect(harness.playback.ranges.skip(trechos), ['0-5000']);
    closeTheRoom(container);
  });

  testWidgets('in an English session the retell speaks her English words', (
    tester,
  ) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await tocar(tester, retroLabelFor('pauseAtTheTap', 'en'));
    await tocar(tester, retroLabelFor('recording', 'en'));
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await _passo(tester);
    await tocar(tester, retroLabelFor('endOfTheRecording', 'en'));
    await tocar(tester, retroLabelFor('endOfTheRecording', 'en'));
    await tocar(tester, retroLabelFor('recording', 'en'));
    await waitFor(
      'o terminei acender',
      () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
      step: () => _passo(tester),
    );
    harness.room
      ..verdictChecked = false
      ..verdictFindingPlace = 0
      ..verdictFindings = const [
        BtFinding(
          kind: BtFindingKind.addition,
          frase: 1,
          segmentId: 'trecho-1',
        ),
      ];
    await _terminei(tester, container, BtPhase.playing);

    await tocar(tester, 'Hear this sentence again and translate it again — 2');

    expect(
      find.text('translating sentence 2 again — tap the circle'),
      findsOneWidget,
      reason: 'a sessão em inglês dizia a linha em português',
    );
    expect(byLabel('keep the earlier translation'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('after a verdict a bead tapped on frase 5 opens it to be told '
      'again and plays its piece of the recording, not its translation', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);
    await tocar(tester, _barra(2));
    await _traduzirDeNovo(tester, container);
    final aqui = container.read(salaSessionProvider);
    expect(aqui.btPhase, BtPhase.playing);
    final parteDois = aqui.partes[1].path;
    final tocadas = harness.playback.played.length;
    final trechos = harness.playback.ranges.length;

    container
        .read(salaSessionProvider.notifier)
        .traduzirAFraseDeNovo(
          aqui.btTrechos.indexWhere((trecho) => trecho.frase == 5),
        );
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      5,
      reason: 'a conta só tocava a frase, e a barra dela abre a frase de novo',
    );
    expect(
      harness.playback.played.skip(tocadas),
      [parteDois],
      reason: 'a conta tocava a tradução da frase 5, não a gravação',
    );
    expect(harness.playback.ranges.skip(trechos), ['2500-5000']);
    closeTheRoom(container);
  });

  testWidgets('a second frase tapped before anything is told keeps the way '
      'back to the conferida telling', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(2));
    await tocar(tester, _barra(5));
    await tocar(tester, 'manter a tradução de antes');
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.conferida,
      reason: 'a segunda frase tocada apagava o caminho de volta à conferida',
    );
    expect(byLabel(_aprovar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a conferida session picked back up with no rehearsal on this '
      'tablet opens no frase and calls nobody', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    harness.emAberto.rows['Ruth/P01/pt'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      checked: true,
      segments: [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 5000,
          frase: 1,
        ),
        SegmentView(
          segmentId: 'trecho-2',
          takeId: 'gravacao-1',
          startsMs: 5000,
          endsMs: 9000,
          frase: 2,
        ),
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
    await waitFor(
      'a tradução conferida voltar sem gravação neste tablet',
      () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
      step: () => _passo(tester),
    );
    await _passo(tester);
    expect(container.read(salaSessionProvider).partes, isEmpty);

    await tocar(tester, _barra(1));
    for (var passo = 0; passo < 5; passo++) {
      await _passo(tester);
    }

    expect(
      container.read(salaSessionProvider).needsPerson,
      isFalse,
      reason: 'tocar numa frase sem gravação neste tablet parava a sala',
    );
    expect(harness.room.personsAsked, 0);
    expect(container.read(salaSessionProvider).btTrechoTraduzidoDeNovo, isNull);
    expect(
      tester.widget<Semantics>(byLabel(_barra(1))).properties.enabled,
      isFalse,
      reason: 'a frase se oferecia ao toque sem nada para tocar',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase told this session carries the name the room gave it '
      'as soon as the room answers', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesContadas(tester, harness);

    expect(
      [
        for (final trecho in container.read(salaSessionProvider).btTrechos)
          trecho.segmentId,
      ],
      [
        'trecho-1',
        'trecho-2',
        'trecho-3',
        'trecho-4',
        'trecho-5',
        'trecho-6',
        'trecho-7',
      ],
      reason:
          'a frase contada nesta sessão ficava sem nome até a próxima '
          'leitura, e a porta de substituir não a alcançava',
    );
    closeTheRoom(container);
  });

  testWidgets('before any check, a tap on frase 7 told this session replays '
      'its piece and the circle tells it again through the replace door', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesContadas(tester, harness);
    final parteDois = container.read(salaSessionProvider).partes[1].path;
    final pedacos = harness.room.chunksSent;
    final tocadas = harness.playback.played.length;
    final trechos = harness.playback.ranges.length;

    await tocar(tester, _barra(7));

    expect(
      harness.playback.played.skip(tocadas),
      [parteDois],
      reason: 'antes de uma conferência a frase não aceitava toque',
    );
    expect(harness.playback.ranges.skip(trechos), ['7500-10000']);
    expect(
      find.text('traduzindo de novo a frase 7 — toquem no círculo'),
      findsOneWidget,
    );

    await _traduzirDeNovo(tester, container);

    expect(
      harness.room.replacesAsked,
      ['trecho-7@gravacao-2:7500-10000'],
      reason: 'a nova tradução não ia pela porta de substituir a frase 7',
    );
    expect(harness.room.chunksSent, pedacos);
    expect(
      harness.room.playedByTakeSent,
      isEmpty,
      reason: 'a frase traduzida de novo pedia a conferência sozinha',
    );
    closeTheRoom(container);
  });

  testWidgets('after frase 4 is told again in the middle of its part, the '
      'next pause on that part tells from where the telling stood', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesContadas(tester, harness);

    await tocar(tester, _barra(4));
    await _traduzirDeNovo(tester, container);
    expect(harness.room.replacesAsked, ['trecho-4@gravacao-2:0-2500']);

    await tocar(tester, 'Ouvir');
    harness.playback.at = const Duration(seconds: 5);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase seguinte subir',
      () => harness.room.chunkSpans.length == 5,
      step: () => _passo(tester),
    );

    expect(
      [harness.room.chunkTakes.last, harness.room.chunkSpans.last],
      ['gravacao-2', '2500-5000'],
      reason:
          'o cursor voltava ao fim da parte 1, e a parte 2 não aceitava '
          'mais pausa até passar dele',
    );
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» on frase 4 in the middle of its '
      'part replaces nothing, and the next pause tells from where the telling '
      'stood', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesContadas(tester, harness);

    await tocar(tester, _barra(4));
    await tocar(tester, 'manter a tradução de antes');
    await _passo(tester);
    expect(container.read(salaSessionProvider).btTrechoTraduzidoDeNovo, isNull);

    await tocar(tester, 'Ouvir');
    harness.playback.at = const Duration(seconds: 5);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await tocarNoCirculo(tester);
    await waitFor(
      'a frase seguinte subir',
      () => harness.room.chunkSpans.length == 5,
      step: () => _passo(tester),
    );

    expect(harness.room.replacesAsked, isEmpty);
    expect(
      [harness.room.chunkTakes.last, harness.room.chunkSpans.last],
      ['gravacao-2', '2500-5000'],
      reason:
          'manter a tradução de antes voltava o cursor ao fim da parte 1, e a '
          'parte 2 não aceitava mais pausa até passar dele',
    );
    closeTheRoom(container);
  });
}
