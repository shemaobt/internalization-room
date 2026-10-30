import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show byLabel, intoTheRecordingHome, offTheRows, relaunch, settle;

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
  Scene(sceneId: 'S4', title: 'A chegada a Belém'),
];

const _scenes = [
  Scene(sceneId: 'S1', title: 'Famine in Bethlehem'),
  Scene(sceneId: 'S2', title: 'Naomi decides to return'),
  Scene(sceneId: 'S3', title: 'Ruth clings to Naomi'),
  Scene(sceneId: 'S4', title: 'Arrival in Bethlehem'),
];

const _aviso = 'Uma gravação ainda está neste computador e não foi enviada.';
const _falhou = 'falhou — toque para tentar de novo';
const _enviando = 'enviando…';
const _salvo = '✓ salvo';
const _enviarAGravacao = 'Enviar a gravação';
const _tentarDeNovo = 'Tentar enviar de novo';
const _gravar = 'Gravar';
const _gravarDeNovo = 'Gravar de novo';
const _parar = 'Parar';
const _ouvir = 'Ouvir';
const _traduzir = 'Traduzir a gravação';
const _conferir = 'ouvir e conferir o Ensaio Final';

String _enviarAgora(int n, String mss) => 'Cena $n · $mss — enviar agora';

const _nossasPalavras = [
  'Tocar para gravar o ensaio',
  'Tocar para gravar a próxima parte',
  'Ouvir o ensaio até aqui',
  'Pausar o ensaio',
  'Confirmar esta parte',
  'Ir para a tradução',
  'ainda não enviada',
  'Tocar ao terminar',
  'Tocar para gravar esta parte de novo',
];

const _umaParte = Duration(seconds: 48);

class _Casa {
  final WidgetTester tester;
  SalaHarness harness;
  ProviderContainer container;
  final List<Scene> cenas;

  _Casa(this.tester, this.harness, this.container, this.cenas);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get envios => room.calls.where((call) => call == 'sendTake').length;

  List<String> get naSala => room.takesKept;

  Finder linha(int n) => byLabel(
    '${cenas == _cenas ? 'Cena' : 'Scene'} $n — ${cenas[n - 1].title}',
  );

  Finder naLinha(int n, Finder alvo) =>
      find.descendant(of: linha(n), matching: alvo);

  Future<void> emTempoReal(Future<void> Function() corpo) async {
    await tester.runAsync(corpo);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tocar(Finder alvo) => emTempoReal(() async {
    await tester.ensureVisible(alvo);
    await tester.tap(alvo);
    await settle(const Duration(milliseconds: 400));
  });

  bool falhou(int n) {
    final linha = estado.sceneRows.firstWhere((row) => row.number == n);
    return linha.inTheAir == null &&
        linha.unsent?.failure == SendFailure.failed;
  }

  bool enviada(int n) {
    final linha = estado.sceneRows.firstWhere((row) => row.number == n);
    return linha.inTheAir == null && linha.unsent == null;
  }

  Future<void> tocarAte(Finder alvo, String what, bool Function() done) =>
      emTempoReal(() async {
        await tester.ensureVisible(alvo);
        await tester.tap(alvo);
        await waitFor(what, done, limit: const Duration(seconds: 30));
      });

  Future<void> gravar(int n) => emTempoReal(() async {
    sala.gravarACena(n);
    await waitFor(
      'a cena $n gravar',
      () => estado.ensaio == EnsaioStatus.recording,
    );
    sala.gravarACena(n);
    await waitFor(
      'a gravação da cena $n esperar o visto',
      () => estado.ensaio == EnsaioStatus.recorded,
    );
  });

  Future<void> guardar(int n) async {
    await gravar(n);
    await emTempoReal(() async {
      final antes = envios;
      sala.takeKeep();
      await waitFor('a cena $n subir', () => envios > antes);
      await waitFor('a cena $n assentar', () {
        final linha = estado.sceneRows.firstWhere((row) => row.number == n);
        return linha.inTheAir == null &&
            (linha.saved || linha.unsent?.failure != null);
      }, limit: const Duration(seconds: 30));
    });
  }

  Future<void> relancar({String? lingua}) async {
    late SalaHarness de;
    late ProviderContainer para;
    await tester.runAsync(() async {
      container.dispose();
      await harness.takes.flush();
      (de, para) = await relaunch(harness, container, lingua: lingua);
      de.playback.measured = _umaParte;
      para.read(salaSessionProvider);
    });
    harness = de;
    container = para;
    await tester.pumpWidget(_aCasa(container));
    await emTempoReal(() async {
      await _lancar(container);
      await waitFor(
        'a sala voltar à conversa',
        () => estado.stage == SalaStage.conversa && !estado.awaitingTheGuide,
      );
      container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
      await waitFor(
        'o ponto laranja decidir a tela',
        () =>
            estado.ensaioFinalPlan is PlanRead ||
            estado.station == const Ensaio(),
      );
      container.read(salaSessionProvider.notifier).recordSceneByScene();
      await waitFor(
        'a sala voltar à casa do ensaio',
        () =>
            estado.stage == SalaStage.ensaio &&
            estado.sceneRows.length == cenas.length,
      );
      await settle(const Duration(milliseconds: 600));
    });
  }

  void controles({required String madeira}) {
    expect(offTheRows(madeira), findsOneWidget, reason: 'o play de madeira');
    expect(
      offTheRows(_enviarAGravacao),
      findsOneWidget,
      reason: 'o visto verde',
    );
    expect(offTheRows(_traduzir), findsOneWidget, reason: 'o disco');
    _nenhumaPalavraNossa();
  }
}

Future<ProviderContainer> Function() _aoVivo(SalaHarness harness) =>
    () async => harness.container()..read(salaSessionProvider);

Widget _aCasa(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: EnsaioView()),
  ),
);

Future<void> _lancar(ProviderContainer container) async {
  final sala = container.read(salaSessionProvider.notifier);
  await container.read(deviceLinkProvider.notifier).findTheTeam();
  await sala.refreshUnsent();
  await sala.openTheRoom();
}

ButtonMood _oDisco(WidgetTester tester) => tester
    .widget<RoundActionButton>(
      find.ancestor(
        of: offTheRows(_traduzir),
        matching: find.byType(RoundActionButton),
      ),
    )
    .mood;

ButtonMood _aMadeira(WidgetTester tester) => tester
    .widget<RoundActionButton>(
      find.ancestor(
        of: offTheRows(_ouvir),
        matching: find.byType(RoundActionButton),
      ),
    )
    .mood;

/// Scenes 1 to 3 kept and landed, and scene 4 kept with the Outbox's count after its
/// copy held and its upload held at the room's door.
Future<(_Casa, ({Completer<void> asking, Completer<void> answer}))>
_aQuartaGuardadaComAContaPresa(WidgetTester tester) async {
  late QueueHeldOnTheNextTally fila;
  final casa = await _naCasa(
    tester,
    harness: SalaHarness(
      lingua: 'pt',
      takesOverride: (room, home, recordings) => fila = QueueHeldOnTheNextTally(
        room: room,
        home: () async => home,
        recordings: recordings,
      ),
    ),
  );
  for (final n in [1, 2, 3]) {
    await casa.guardar(n);
  }
  await casa.gravar(4);
  final contagem = fila.holdTheNextTally();
  casa.room.holdNextTake('parte-4');
  await casa.emTempoReal(() async {
    casa.sala.takeKeep();
    await waitFor(
      'a contagem da cena 4 começar',
      () => contagem.asking.isCompleted,
      limit: const Duration(seconds: 5),
    );
  });
  return (casa, contagem);
}

Future<_Casa> _comAQuartaNaFila(WidgetTester tester) async {
  final casa = await _naCasa(tester);
  for (final n in [1, 2, 3]) {
    await casa.guardar(n);
  }
  casa.room.unreachableTake = 'ensaio/parte-4';
  await casa.guardar(4);
  await casa.emTempoReal(
    () => waitFor('a cena 4 falhar', () => casa.falhou(4)),
  );
  expect(casa.estado.everySceneHasItsPart, isTrue);
  expect(casa.estado.unsentParts.keys, [4]);
  return casa;
}

void _umIpadEmPe(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_Casa> _naCasa(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> cenas = _cenas,
  SalaHarness? harness,
}) async {
  _umIpadEmPe(tester);
  final sala = harness ?? SalaHarness(lingua: lingua);
  sala.room.passageScenes = cenas;
  sala.playback.measured = _umaParte;
  final container = (await tester.runAsync(_aoVivo(sala)))!;
  addTearDown(container.dispose);
  await tester.pumpWidget(_aCasa(container));
  final casa = _Casa(tester, sala, container, cenas);
  await casa.emTempoReal(() async {
    await _lancar(container);
    await casa.sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a sessão abrir',
      () => casa.estado.sessionId != null && !casa.estado.awaitingTheGuide,
    );
    await settle();
    casa.sala.goEnsaio();
    await waitFor(
      'as cenas chegarem',
      () => casa.estado.sceneRows.length == cenas.length,
    );
    await settle();
  });
  return casa;
}

Future<void> _retomarComAParte1(
  WidgetTester tester, {
  required String? origin,
}) async {
  _umIpadEmPe(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1420-juntou');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passageScenes = _cenas
    ..room.takes.add(
      TakeView(
        takeId: 'gravacao-1',
        kind: 'ensaio',
        scope: 'parte-1',
        ordinal: 1,
        origin: origin,
      ),
    );
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: '${pasta.path}/p1.m4a',
        takeId: 'gravacao-1',
      ),
    ],
  );
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  await tester.runAsync(notifier.abrirEscolha);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(
    () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'a sala pousar na conversa',
    () =>
        container.read(salaSessionProvider).station is Canvas &&
        !container.read(salaSessionProvider).awaitingTheGuide,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  notifier.openTheEnsaioFinal();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void _nenhumaPalavraNossa() {
  for (final nossa in _nossasPalavras) {
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(nossa))),
      findsNothing,
      reason: '«$nossa» é palavra nossa, não dela',
    );
  }
}

void main() {
  testWidgets(
    'a scene take recorded on an earlier visit and never sent shows the '
    'notice and «Cena 2 · 0:48 — enviar agora», and a tap sends it',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);

      await casa.relancar();

      expect(find.text(_aviso), findsOneWidget);
      expect(
        casa.naLinha(2, find.text(_enviarAgora(2, '0:48'))),
        findsOneWidget,
      );

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        find.text(_enviarAgora(2, '0:48')),
        'a cena 2 ficar enviada',
        () => casa.enviada(2),
      );

      expect(casa.naSala, contains('ensaio/parte-2'));
      expect(find.text(_aviso), findsNothing);
      expect(find.text(_enviarAgora(2, '0:48')), findsNothing);
      expect(casa.naLinha(2, byLabel(_ouvir)), findsOneWidget);
      expect(casa.naLinha(2, byLabel(_gravarDeNovo)), findsOneWidget);
    },
  );

  testWidgets(
    'an upload that fails in this visit keeps «falhou — toque para tentar de '
    'novo» on its row, and a tap tries again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(find.text(_aviso), findsNothing);

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        casa.naLinha(2, find.text(_falhou)),
        'a cena 2 ficar enviada',
        () => casa.enviada(2),
      );

      expect(casa.naSala, contains('ensaio/parte-2'));
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets('a take left unsent for a long time is never spoken about', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.unreachableTake = 'ensaio/parte-2';
    await casa.guardar(2);
    await casa.emTempoReal(
      () => waitFor('a cena 2 falhar', () => casa.falhou(2)),
    );
    final antes = casa.envios;
    for (var toque = 0; toque < 3; toque++) {
      final antesDoToque = casa.envios;
      await casa.tocarAte(
        casa.naLinha(2, find.text(_falhou)),
        'o toque ${toque + 1} falhar de novo',
        () => casa.envios > antesDoToque && casa.falhou(2),
      );
    }
    expect(casa.envios - antes, greaterThanOrEqualTo(9));

    expect(
      casa.harness.voice.assets.where((a) => a.contains('gravacao_presa')),
      isEmpty,
    );
    expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

    await casa.relancar();

    expect(
      casa.harness.voice.assets.where((a) => a.contains('gravacao_presa')),
      isEmpty,
    );
    expect(find.text(_aviso), findsOneWidget);
    expect(casa.naLinha(2, find.text(_enviarAgora(2, '0:48'))), findsOneWidget);
  });

  testWidgets('every recording and translation control reads her words', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    try {
      final casa = await _naCasa(tester);
      casa.controles(madeira: _ouvir);
      expect(casa.naLinha(1, byLabel(_gravar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.sala.gravarACena(1);
        await waitFor(
          'a cena 1 gravar',
          () => casa.estado.ensaio == EnsaioStatus.recording,
        );
      });
      casa.controles(madeira: _ouvir);
      expect(casa.naLinha(1, byLabel(_parar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.sala.gravarACena(1);
        await waitFor(
          'a gravação esperar o visto',
          () => casa.estado.ensaio == EnsaioStatus.recorded,
        );
      });
      casa.controles(madeira: _ouvir);

      await casa.emTempoReal(() async {
        final antes = casa.envios;
        casa.sala.takeKeep();
        await waitFor('a cena 1 subir', () => casa.envios > antes);
        await settle(const Duration(milliseconds: 300));
      });
      await casa.guardar(3);
      casa.controles(madeira: _ouvir);

      await casa.tocar(offTheRows(_ouvir));
      casa.controles(madeira: _parar);
      await casa.tocar(offTheRows(_parar));

      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      casa.room.refuseTake = 'ensaio/parte-4';
      await casa.guardar(4);
      casa.controles(madeira: _ouvir);
      expect(
        casa.naLinha(2, byLabel(_tentarDeNovo)),
        findsOneWidget,
        reason: 'a cena 2 falhou nesta visita',
      );
      expect(
        casa.naLinha(4, find.text('não foi aceita — grave de novo')),
        findsOneWidget,
        reason: 'a sala recusou a cena 4 de vez',
      );

      await casa.relancar();
      casa.controles(madeira: _ouvir);
      expect(casa.naLinha(2, byLabel(_enviarAGravacao)), findsOneWidget);
    } finally {
      semantica.dispose();
    }
  });

  testWidgets('the controls read her English words in an English room', (
    tester,
  ) async {
    final casa = await _naCasa(tester, lingua: 'en', cenas: _scenes);

    expect(casa.naLinha(2, byLabel('Record')), findsOneWidget);
    expect(offTheRows('Listen'), findsOneWidget);
    expect(offTheRows('Send the recording'), findsOneWidget);
    expect(offTheRows('Translate the recording'), findsOneWidget);

    await casa.emTempoReal(() async {
      casa.sala.gravarACena(2);
      await waitFor(
        'scene 2 records',
        () => casa.estado.ensaio == EnsaioStatus.recording,
      );
    });
    expect(casa.naLinha(2, byLabel('Stop')), findsOneWidget);
    await casa.emTempoReal(() async {
      casa.sala.gravarACena(2);
      await waitFor(
        'the recording waits for the check',
        () => casa.estado.ensaio == EnsaioStatus.recorded,
      );
    });

    casa.room.unreachableTake = 'ensaio/parte-2';
    await casa.emTempoReal(() async {
      final antes = casa.envios;
      casa.sala.takeKeep();
      await waitFor('scene 2 goes up', () => casa.envios > antes);
      await waitFor(
        'scene 2 fails',
        () => casa.falhou(2),
        limit: const Duration(seconds: 30),
      );
    });
    expect(casa.naLinha(2, find.text('failed — tap to try again')), findsOne);
    casa.room.refuseTake = 'ensaio/parte-3';
    await casa.guardar(3);
    expect(
      casa.naLinha(3, find.text('not accepted — record it again')),
      findsOne,
    );

    await casa.relancar(lingua: 'en');
    expect(
      find.text('A recording is still on this computer and has not been sent.'),
      findsOneWidget,
    );
    expect(
      casa.naLinha(2, find.text('Scene 2 · 0:48 — send it now')),
      findsOneWidget,
    );
  });

  testWidgets(
    'after a join the advance disc reads «ouvir e conferir o Ensaio Final»',
    (tester) async {
      await _retomarComAParte1(tester, origin: 'ensaio-da-cena-1');

      expect(byLabel(_conferir), findsOneWidget);
      expect(byLabel(_traduzir), findsNothing);
    },
  );

  testWidgets('without a join the advance disc reads «Traduzir a gravação»', (
    tester,
  ) async {
    await _retomarComAParte1(tester, origin: null);

    expect(byLabel(_traduzir), findsOneWidget);
    expect(byLabel(_conferir), findsNothing);
  });

  testWidgets(
    '«enviar agora» on a take refused for good sends it once more with its '
    'tries given back',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.refuseTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.relancar();

      expect(find.text(_aviso), findsOneWidget);
      final botao = casa.naLinha(2, find.textContaining('— enviar agora'));
      expect(botao, findsOneWidget);

      final antes = casa.envios;
      await casa.tocarAte(
        botao,
        'a cena 2 ser enviada de novo',
        () => casa.envios > antes,
      );
      expect(casa.envios - antes, 1);

      await casa.emTempoReal(() async {
        for (var vez = 0; vez < 5; vez++) {
          await casa.harness.takes.flush();
          await settle(const Duration(milliseconds: 30));
        }
      });
      expect(casa.envios - antes, 1);
    },
  );

  testWidgets(
    'a take kept in this visit and still on its first try shows nothing new',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.room.holdNextTake('parte-2');
        casa.sala.takeKeep();
        await casa.room.untilTakeHeld().timeout(const Duration(seconds: 10));
        await settle();
      });

      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);
      expect(find.text(_falhou), findsNothing);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await waitFor(
          'a cena 2 chegar à sala',
          () => casa.naSala.contains('ensaio/parte-2'),
        );
        await settle();
      });

      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets('«enviar agora» on row 3 sends only scene 3\'s take', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.refuseTake = 'ensaio/parte-2';
    await casa.guardar(2);
    casa.room.takeAnswersFirst.add(const Refused('UNKNOWN_REFERENCE'));
    await casa.guardar(3);
    await casa.relancar();

    expect(find.text(_aviso), findsOneWidget);
    expect(casa.naLinha(2, find.text(_enviarAgora(2, '0:48'))), findsOneWidget);
    expect(casa.naLinha(3, find.text(_enviarAgora(3, '0:48'))), findsOneWidget);

    final antes = casa.envios;
    await casa.tocarAte(
      find.text(_enviarAgora(3, '0:48')),
      'a cena 3 ficar enviada',
      () => casa.enviada(3),
    );

    expect(casa.envios - antes, 1, reason: 'só a cena 3 foi tentada');
    expect(casa.naSala, contains('ensaio/parte-3'));
    expect(casa.naSala, isNot(contains('ensaio/parte-2')));
    expect(casa.naLinha(2, find.text(_enviarAgora(2, '0:48'))), findsOneWidget);
  });

  testWidgets(
    'a scene recorded again over its failed take sends only the newer: the '
    'failed one left at the tap to record again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        final antes = casa.envios;
        casa.sala.takeKeep();
        await waitFor('a nova subir', () => casa.envios > antes);
        await waitFor(
          'a nova falhar',
          () => casa.falhou(2),
          limit: const Duration(seconds: 30),
        );
      });
      expect(
        casa.naLinha(2, find.text(_falhou)),
        findsOneWidget,
        reason: 'a nova também não chegou',
      );
      await casa.relancar();
      expect(casa.naSala, isNot(contains('ensaio/parte-2')));

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        casa.naLinha(2, find.textContaining('enviar agora')),
        'a cena 2 ser enviada',
        () => casa.room.takePasses.isNotEmpty,
      );

      expect(casa.room.takePasses, [2]);
    },
  );

  testWidgets(
    'a tap on a part that failed never sends again an earlier recording of it '
    'the room refused for good',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.refuseTake = 'ensaio/parte-2';
      await casa.guardar(2);
      casa.room
        ..refuseTake = null
        ..unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      final antes = casa.room.takePasses.length;

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        casa.naLinha(2, find.text(_falhou)),
        'a cena 2 ser enviada de novo',
        () => casa.room.takePasses.length > antes,
      );

      expect(casa.room.takePasses.sublist(antes), [2]);
    },
  );

  testWidgets(
    'takes waiting in an Outbox written before this update show through the '
    'notice and are not lost',
    (tester) async {
      _umIpadEmPe(tester);
      final casaDasTomadas = Directory.systemTemp.createTempSync('sala-1420');
      addTearDown(() => casaDasTomadas.deleteSync(recursive: true));
      final guardadas = Directory('${casaDasTomadas.path}/guardadas')
        ..createSync();
      final audio = File('${guardadas.path}/ensaio-parte-1.m4a')
        ..writeAsBytesSync([1, 2, 3, 4]);
      File('${guardadas.path}/fila.json').writeAsStringSync(
        jsonEncode([
          PendingTake(
            id: 'antiga-1',
            path: audio.path,
            sessionId: 'sessao-antiga',
            kind: 'ensaio',
            scope: 'parte-1',
            passNumber: 1,
            chunkIndex: 1,
            waits: 3,
            lastTry: DateTime.now(),
          ).toJson(),
        ]),
      );
      final harness = SalaHarness(takesHome: casaDasTomadas)
        ..room.passageScenes = _cenas
        ..room.unreachableTake = 'ensaio/parte-1'
        ..playback.measured = _umaParte;
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: [KeptTake(scopeId: KeptScope.parte(1), path: audio.path)],
      );
      final container = (await tester.runAsync(_aoVivo(harness)))!;
      addTearDown(container.dispose);
      await tester.pumpWidget(_aCasa(container));
      final casa = _Casa(tester, harness, container, _cenas);
      await casa.emTempoReal(() async {
        await casa.sala.abrirEscolha();
        await settle();
        await casa.sala.goConversa(book: 'Ruth', pericope: 'P01');
        await intoTheRecordingHome(casa.sala, () => casa.estado);
        await waitFor(
          'a sala voltar à casa do ensaio',
          () =>
              casa.estado.stage == SalaStage.ensaio &&
              casa.estado.sceneRows.length == _cenas.length,
        );
        await settle(const Duration(milliseconds: 600));
      });

      expect(find.text(_aviso), findsOneWidget);
      expect(casa.naLinha(1, find.text(_enviarAgora(1, '0:48'))), findsOne);
      expect(audio.existsSync(), isTrue);

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        find.text(_enviarAgora(1, '0:48')),
        'a cena 1 chegar à sala',
        () => casa.naSala.contains('ensaio/parte-1'),
      );

      expect(casa.naSala, contains('ensaio/parte-1'));
    },
  );

  testWidgets(
    'a keep the Outbox could not take shows as failed on its row, and the tap '
    'puts it in and sends it',
    (tester) async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => _QueueThatRefusesOnce(
          room: room,
          home: () async => home,
          recordings: recordings,
        ),
      );
      final casa = await _naCasa(tester, harness: harness);
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor('a cena 2 falhar', () => casa.falhou(2));
      });

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

      await casa.tocarAte(
        casa.naLinha(2, find.text(_falhou)),
        'a cena 2 chegar à sala',
        () => casa.naSala.contains('ensaio/parte-2') && !casa.falhou(2),
      );

      expect(casa.naSala, contains('ensaio/parte-2'));
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets(
    'a double tap on «falhou» for a keep the Outbox could not take sends it '
    'once',
    (tester) async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => _QueueThatRefusesOnce(
          room: room,
          home: () async => home,
          recordings: recordings,
        ),
      );
      final casa = await _naCasa(tester, harness: harness);
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor(
          'a cena 2 falhar',
          () => casa.falhou(2),
          limit: const Duration(seconds: 30),
        );
      });
      final falhou = casa.naLinha(2, find.text(_falhou));

      await casa.emTempoReal(() async {
        await tester.ensureVisible(falhou);
        await tester.tap(falhou);
        await tester.tap(falhou);
        await waitFor(
          'a cena 2 chegar à sala',
          () => casa.room.takesReceived.any((take) => take.scope == 'parte-2'),
          limit: const Duration(seconds: 30),
        );
        await settle(const Duration(milliseconds: 800));
      });

      expect(
        casa.room.takesReceived.where((take) => take.scope == 'parte-2'),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a keep the Outbox refuses after the team left the passage never shows '
    'on the next passage\'s rows',
    (tester) async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => _QueueThatRefusesWhenLetGo(
          room: room,
          home: () async => home,
          recordings: recordings,
        ),
      );
      final casa = await _naCasa(tester, harness: harness);
      final fila = harness.takes as _QueueThatRefusesWhenLetGo;
      await casa.gravar(3);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor('a Outbox segurar a cena 3', () => fila.holding);
        casa.sala.leaveThePassage();
        await settle();
        await casa.sala.goConversa(book: 'Ruth', pericope: 'P02');
        await waitFor(
          'a passagem nova abrir',
          () => casa.estado.sessionId != null && !casa.estado.awaitingTheGuide,
        );
        casa.sala.goEnsaio();
        await waitFor(
          'as cenas chegarem',
          () => casa.estado.sceneRows.length == _cenas.length,
        );
        fila.letGo();
        await settle(const Duration(milliseconds: 300));
        await casa.sala.refreshUnsent();
        await settle();
      });

      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets(
    'a take recorded over by a newer recording the room holds is not unsent, '
    'here or after a relaunch',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.refuseTake = 'ensaio/parte-2';
      await casa.guardar(2);
      casa.room.refuseTake = null;
      await casa.guardar(2);
      expect(casa.room.takePasses.last, 2);

      expect(casa.naLinha(2, find.text(_falhou)), findsNothing);
      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);
      expect(casa.naLinha(2, byLabel(_ouvir)), findsOneWidget);

      final antes = casa.envios;
      await casa.relancar();

      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);
      expect(find.text(_falhou), findsNothing);
      expect(
        casa.envios,
        antes,
        reason: 'a gravação de baixo não sobe de novo',
      );
    },
  );

  for (final (como, lost) in [
    ('written off', true),
    ('refused for good and never written off', false),
  ]) {
    testWidgets(
      'a row whose audio is gone is not an unsent take, and its scene can be '
      'recorded: $como',
      (tester) async {
        _umIpadEmPe(tester);
        final casaDasTomadas = Directory.systemTemp.createTempSync('sala-1420');
        addTearDown(() => casaDasTomadas.deleteSync(recursive: true));
        final guardadas = Directory('${casaDasTomadas.path}/guardadas')
          ..createSync();
        final parte2 = File('${guardadas.path}/ensaio-parte-2.m4a')
          ..writeAsBytesSync([5, 6, 7, 8]);
        File('${guardadas.path}/fila.json').writeAsStringSync(
          jsonEncode([
            PendingTake(
              id: 'perdida-1',
              path: '${guardadas.path}/ensaio-parte-1.m4a',
              sessionId: 'sessao-antiga',
              kind: 'ensaio',
              scope: 'parte-1',
              passNumber: 1,
              chunkIndex: 1,
              lost: lost,
              waits: lost ? 2 : 0,
              attempts: lost ? 0 : takeUploadAttempts,
              refusal: lost ? null : 'UNKNOWN_REFERENCE',
            ).toJson(),
          ]),
        );
        final harness = SalaHarness(takesHome: casaDasTomadas)
          ..room.passageScenes = _cenas
          ..playback.measured = _umaParte;
        harness.room.takes.add(
          const TakeView(
            takeId: 'gravacao-2',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        );
        harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.ensaio,
          takes: [
            KeptTake(
              scopeId: KeptScope.parte(2),
              path: parte2.path,
              takeId: 'gravacao-2',
            ),
          ],
        );
        final container = (await tester.runAsync(_aoVivo(harness)))!;
        addTearDown(container.dispose);
        await tester.pumpWidget(_aCasa(container));
        final casa = _Casa(tester, harness, container, _cenas);
        await casa.emTempoReal(() async {
          await casa.sala.abrirEscolha();
          await settle();
          await casa.sala.goConversa(book: 'Ruth', pericope: 'P01');
          await intoTheRecordingHome(casa.sala, () => casa.estado);
          await waitFor(
            'a sala voltar à casa do ensaio',
            () =>
                casa.estado.stage == SalaStage.ensaio &&
                casa.estado.sceneRows.length == _cenas.length,
          );
          await settle(const Duration(milliseconds: 600));
        });

        expect(find.text(_aviso), findsNothing);
        expect(find.textContaining('enviar agora'), findsNothing);
        expect(casa.naLinha(1, find.text(_falhou)), findsNothing);
        expect(casa.naLinha(1, byLabel(_gravar)), findsOneWidget);
      },
    );
  }

  testWidgets(
    'a recount while this visit\'s keep is being written never shows the '
    'earlier-visit notice',
    (tester) async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => _QueueHeldAfterWriting(
          room: room,
          home: () async => home,
          recordings: recordings,
        ),
      );
      final casa = await _naCasa(tester, harness: harness);
      final fila = harness.takes as _QueueHeldAfterWriting;
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor('a linha ser escrita', () => fila.written);
        await casa.sala.refreshUnsent();
        await settle();
      });

      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);

      await casa.emTempoReal(() async {
        fila.letGo();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    'a scene recorded again while its first keep is still being written never '
    'shows the earlier-visit notice when the first one finishes',
    (tester) async {
      final harness = SalaHarness(
        takesOverride: (room, home, recordings) => _QueueHeldPerKeep(
          room: room,
          home: () async => home,
          recordings: recordings,
        ),
      );
      final casa = await _naCasa(tester, harness: harness);
      final fila = harness.takes as _QueueHeldPerKeep;
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor('a primeira linha ser escrita', () => fila.written == 1);
      });
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await waitFor('a segunda linha ser escrita', () => fila.written == 2);
        fila.letGo(0);
        await settle(const Duration(milliseconds: 300));
        await casa.sala.refreshUnsent();
        await settle();
      });

      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);

      await casa.emTempoReal(() async {
        fila.letGo(1);
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    'a take that failed in this visit still shows «falhou» after the team '
    'leaves the passage and comes back to it',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      final sessao = casa.estado.sessionId;

      await casa.emTempoReal(() async {
        casa.sala.leaveThePassage();
        await settle();
        await casa.sala.goConversa(book: 'Ruth', pericope: 'P01');
        await intoTheRecordingHome(casa.sala, () => casa.estado);
        await waitFor(
          'a sala voltar à casa do ensaio',
          () =>
              casa.estado.stage == SalaStage.ensaio &&
              casa.estado.sceneRows.length == _cenas.length,
        );
        await settle(const Duration(milliseconds: 600));
      });

      expect(casa.estado.sessionId, sessao, reason: 'a mesma sessão');
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(find.text(_aviso), findsNothing);
      expect(find.textContaining('enviar agora'), findsNothing);
    },
  );

  testWidgets('while a row records, the send button does nothing', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.refuseTake = 'ensaio/parte-2';
    await casa.guardar(2);
    await casa.relancar();
    casa.room.refuseTake = null;

    await casa.emTempoReal(() async {
      casa.sala.gravarACena(1);
      await waitFor(
        'a cena 1 gravar',
        () => casa.estado.ensaio == EnsaioStatus.recording,
      );
    });
    final antes = casa.envios;
    await casa.tocar(find.text(_enviarAgora(2, '0:48')));
    expect(casa.envios, antes);

    await casa.emTempoReal(() async {
      casa.sala.gravarACena(1);
      await waitFor(
        'a gravação esperar o visto',
        () => casa.estado.ensaio == EnsaioStatus.recorded,
      );
    });
    await casa.tocarAte(
      find.text(_enviarAgora(2, '0:48')),
      'a cena 2 ficar enviada',
      () => casa.enviada(2),
    );
    expect(casa.naSala, contains('ensaio/parte-2'));
  });

  testWidgets(
    'a part still in the Outbox keeps the advance disc dark, as her translate '
    'button waits for the room to hold every part',
    (tester) async {
      await _comAQuartaNaFila(tester);

      expect(
        _oDisco(tester),
        ButtonMood.dimmed,
        reason:
            'o disco acenava com a cena 4 ainda na fila, e o botão dela fica '
            'desligado até a sala ter todas as partes',
      );
    },
  );

  testWidgets(
    'the check asked for with a part still in the Outbox stays on the '
    'recording home, as hers does after a join',
    (tester) async {
      final casa = await _comAQuartaNaFila(tester);

      await casa.emTempoReal(() async {
        casa.sala.startRetro();
        await settle(const Duration(milliseconds: 400));
      });

      expect(
        casa.estado.stage,
        SalaStage.ensaio,
        reason:
            'a conferência abria com a cena 4 na fila e a contava como não '
            'ouvida; a dela não abre',
      );
    },
  );

  testWidgets(
    'once the part in the Outbox lands, the disc lights and its tap opens the '
    'check',
    (tester) async {
      final casa = await _comAQuartaNaFila(tester);

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        casa.naLinha(4, find.text(_falhou)),
        'a cena 4 chegar',
        () => casa.estado.everyPartIsSent,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(casa.estado.everyPartIsSent, isTrue);
      expect(
        _oDisco(tester),
        ButtonMood.beckoning,
        reason: 'a cena 4 chegou à sala e o disco ficava apagado',
      );

      await casa.tocar(offTheRows(_traduzir));

      expect(
        casa.estado.stage,
        SalaStage.retro,
        reason: 'com todas as partes na sala, a conferência não abria',
      );
    },
  );

  testWidgets(
    'with three parts in the room and the fourth in the Outbox, the home says '
    '«gravem todas as partes primeiro», as hers',
    (tester) async {
      await _comAQuartaNaFila(tester);

      expect(
        find.text('gravem todas as partes primeiro'),
        findsOneWidget,
        reason:
            'a casa contava a cena 4 da fila como gravada e calava a linha que '
            'a dela mostra',
      );
    },
  );

  testWidgets(
    'with the only part recorded still in the Outbox, the home does not say '
    '«gravem todas as partes primeiro», as hers counts what the room holds',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.estado.unsentParts.keys, [2]);

      expect(
        find.text('gravem todas as partes primeiro'),
        findsNothing,
        reason:
            'a casa contava a cena 2 da fila como gravada; na dela, sem parte '
            'nenhuma na sala, a linha não aparece',
      );
    },
  );

  testWidgets(
    'after a relaunch, a part from the earlier visit still in the Outbox keeps '
    'the check closed until it lands, and then the check opens',
    (tester) async {
      final casa = await _comAQuartaNaFila(tester);
      await casa.relancar();
      expect(casa.estado.unsentParts.keys, [4]);

      await casa.emTempoReal(() async {
        casa.sala.startRetro();
        await settle(const Duration(milliseconds: 400));
      });
      expect(
        casa.estado.stage,
        SalaStage.ensaio,
        reason: 'depois de relançar, a conferência abria com a cena 4 na fila',
      );

      casa.room.unreachableTake = null;
      await casa.tocarAte(
        casa.naLinha(4, find.textContaining('enviar agora')),
        'a cena 4 chegar',
        () => casa.estado.everyPartIsSent,
      );
      await casa.emTempoReal(() async {
        casa.sala.startRetro();
        await settle(const Duration(milliseconds: 400));
      });

      expect(
        casa.estado.stage,
        SalaStage.retro,
        reason:
            'a cena 4 chegou à sala sem o tablet saber o nome dela, e a '
            'conferência ficava fechada a visita toda',
      );
    },
  );

  testWidgets(
    'a keep the Outbox has taken but not yet counted keeps the advance disc '
    'dark',
    (tester) async {
      final (casa, contagem) = await _aQuartaGuardadaComAContaPresa(tester);

      expect(_oDisco(tester), ButtonMood.dimmed, reason: 'a cena 4 sem conta');
      casa.sala.startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      expect(casa.estado.stage, SalaStage.ensaio);

      await casa.emTempoReal(() async {
        contagem.answer.complete();
        await waitFor('a cena 4 chegar à porta', () => casa.room.takeHeld);
        await settle();
      });
      expect(_oDisco(tester), ButtonMood.dimmed, reason: 'a cena 4 subindo');
      casa.sala.startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      expect(casa.estado.stage, SalaStage.ensaio);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await waitFor(
          'o disco acender com a cena 4 na sala',
          () => casa.estado.ensaioDone,
          limit: const Duration(seconds: 30),
        );
      });
      expect(_oDisco(tester), ButtonMood.beckoning);
    },
  );

  testWidgets(
    'a take of an earlier visit sent by «enviar agora» reads «✓ salvo» once '
    'the room holds it, as a take of this visit does',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.relancar();
      casa.room.unreachableTake = null;

      await casa.tocarAte(
        find.text(_enviarAgora(2, '0:48')),
        'a sala guardar a cena 2',
        () => casa.naSala.contains('ensaio/parte-2') && casa.enviada(2),
      );
      await casa.emTempoReal(settle);

      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a take the room turned the tablet away on reads «falhou — toque para '
    'tentar de novo», never «enviando…» without a tap, and its tap sends it',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = 'UNAUTHORIZED';
      await casa.gravar(2);
      await casa.emTempoReal(() async {
        final antes = casa.envios;
        casa.sala.takeKeep();
        await waitFor('a cena 2 subir', () => casa.envios > antes);
        await waitFor('a cena 2 descer do ar', () {
          final linha = casa.estado.sceneRows.firstWhere(
            (row) => row.number == 2,
          );
          return linha.inTheAir == null && linha.unsent != null;
        });
        await settle(const Duration(milliseconds: 600));
      });

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(casa.naLinha(2, find.text(_enviando)), findsNothing);
      await casa.emTempoReal(() => settle(const Duration(seconds: 3)));
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(casa.naLinha(2, find.text(_enviando)), findsNothing);

      casa.room.refuseTake = null;
      await casa.tocarAte(
        casa.naLinha(2, find.text(_falhou)),
        'a sala guardar a cena 2',
        () => casa.naSala.contains('ensaio/parte-2'),
      );
    },
  );
  testWidgets(
    'the wood play stays dark from the keep tap until the room holds the part',
    (tester) async {
      final (casa, contagem) = await _aQuartaGuardadaComAContaPresa(tester);

      expect(
        _aMadeira(tester),
        ButtonMood.dimmed,
        reason: 'guardando a cena 4',
      );

      await casa.emTempoReal(() async {
        contagem.answer.complete();
        await waitFor(
          'a cena 4 subir',
          () => casa.estado.sceneRows[3].inTheAir != null,
        );
        await settle();
      });
      expect(_aMadeira(tester), ButtonMood.dimmed, reason: 'a cena 4 no ar');

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await waitFor(
          'a cena 4 chegar à sala',
          () => casa.naSala.contains('ensaio/parte-4') && casa.enviada(4),
          limit: const Duration(seconds: 30),
        );
        await settle();
      });
      expect(_aMadeira(tester), ButtonMood.lit);
    },
  );

  testWidgets(
    'a part failed in the Outbox leaves the wood play lit and «Ouvir tudo» '
    'hidden',
    (tester) async {
      final casa = await _comAQuartaNaFila(tester);
      await casa.emTempoReal(settle);

      expect(_aMadeira(tester), ButtonMood.lit);
      expect(find.text('Ouvir tudo'), findsNothing);
    },
  );
  testWidgets(
    'a take of an earlier visit whose tapped send fails still offers «Cena 2 · '
    '0:48 — enviar agora»',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.relancar();
      final antes = casa.envios;

      await casa.tocarAte(
        find.text(_enviarAgora(2, '0:48')),
        'o envio da cena 2 cair',
        () => casa.envios > antes && casa.estado.sceneRows[1].inTheAir == null,
      );
      await casa.emTempoReal(() async {
        await settle(const Duration(seconds: 2));
        casa.sala.leaveTheRecording();
        await settle();
        casa.sala.goEnsaio();
        await waitFor(
          'a casa voltar com as cenas',
          () =>
              casa.estado.stage == SalaStage.ensaio &&
              casa.estado.sceneRows.length == _cenas.length,
        );
        await settle(const Duration(seconds: 1));
      });

      expect(casa.naSala, isNot(contains('ensaio/parte-2')));
      expect(
        casa.naLinha(2, find.text(_enviarAgora(2, '0:48'))),
        findsOneWidget,
      );
      expect(casa.naLinha(2, find.text(_falhou)), findsNothing);
    },
  );
}

class _QueueThatRefusesOnce extends TakeUploadQueue {
  _QueueThatRefusesOnce({
    required super.room,
    super.home,
    required super.recordings,
  });

  bool _refused = false;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    if (!_refused) {
      _refused = true;
      throw const FileSystemException('o disco está cheio');
    }
    return super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }
}

class _QueueThatRefusesWhenLetGo extends TakeUploadQueue {
  _QueueThatRefusesWhenLetGo({
    required super.room,
    super.home,
    required super.recordings,
  });

  final _held = Completer<void>();
  bool holding = false;

  void letGo() => _held.complete();

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    holding = true;
    await _held.future;
    throw const FileSystemException('o disco está cheio');
  }
}

class _QueueHeldAfterWriting extends TakeUploadQueue {
  _QueueHeldAfterWriting({
    required super.room,
    super.home,
    required super.recordings,
  });

  final _held = Completer<void>();
  bool written = false;

  void letGo() => _held.complete();

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final row = await super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
    written = true;
    await _held.future;
    return row;
  }
}

class _QueueHeldPerKeep extends TakeUploadQueue {
  _QueueHeldPerKeep({
    required super.room,
    super.home,
    required super.recordings,
  });

  final List<Completer<void>> _held = [];
  int written = 0;

  void letGo(int keep) => _held[keep].complete();

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    final held = Completer<void>();
    _held.add(held);
    final row = await super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
    written++;
    await held.future;
    return row;
  }
}
