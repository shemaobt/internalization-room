import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, relaunch, settle;
import 'package:internalization_room/features/sala/domain/ensaio_final_plan.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';

const _falhou = 'falhou — toque para tentar de novo';
const _perdida = 'falhou — grave de novo';
const _perdidaNoMicrofone = 'falhou';
const _grandeDemais = 'grande demais para o servidor — grave em partes menores';
const _naoFoiAceita = 'não foi aceita — grave de novo';
const _naoDeuParaGuardar =
    'não deu para guardar o ensaio da cena — gravem de novo';
const _gravando = 'gravando';
const _enviando = 'enviando…';
const _salvo = '✓ salvo';
const _parar = 'parar';
final _aprovar = byLabel(retroLabelFor('approve', 'pt'));
const _gravarNaLinha = 'Gravar';
const _ouvirNaLinha = 'Ouvir';
const _gravarDeNovoNaLinha = 'Gravar de novo';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

final _aQuarta = byLabel('Cena 4');

Finder _naQuarta(Finder alvo) => find.descendant(of: _aQuarta, matching: alvo);

final _grandeDemaisParaASala = Uint8List(largestTakeTheRoomKeeps + 1);

const _presaDemais = Duration(minutes: 2);

Future<T?> _semPrender<T>(WidgetTester tester, Future<T> Function() corpo) =>
    tester.runAsync(() => corpo().timeout(_presaDemais));

Future<void> _esperar(String what, FutureOr<bool> Function() ready) =>
    waitFor(what, ready, limit: const Duration(seconds: 30));

Future<void> _batida(WidgetTester tester) async {
  await _semPrender(
    tester,
    () => Future<void>.delayed(const Duration(milliseconds: 15)),
  );
  await tester.pump();
}

Future<void> _ate(
  WidgetTester tester,
  String what,
  bool Function() done,
) async {
  final waited = Stopwatch()..start();
  for (
    var vez = 0;
    !done() && (vez < 200 || waited.elapsed < const Duration(seconds: 30));
    vez++
  ) {
    await _batida(tester);
  }
  expect(done(), isTrue, reason: what);
}

Future<void> _ateVer(WidgetTester tester, Finder alvo) =>
    _ate(tester, 'ver $alvo', () => alvo.evaluate().isNotEmpty);

class _Casa {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Casa(this.tester, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get envios => room.calls.where((call) => call == 'sendTake').length;

  int get leiturasDaLista =>
      room.calls.where((call) => call == 'takesOf').length;

  List<String> get falas => [
    for (final som in harness.sounds)
      if (const {'voice:line', 'voice:asset', 'voice:fixed'}.contains(som)) som,
  ];

  List<File> get copias {
    final guardadas = Directory('${harness.takesHome.path}/guardadas');
    if (!guardadas.existsSync()) return const [];
    return [
      for (final entry in guardadas.listSync())
        if (entry is File && !entry.path.contains('fila.json')) entry,
    ];
  }

  Future<void> guardarEFalharDeNovo(int n) async {
    await guardar(n);
    room.unreachableTake = 'ensaio/parte-$n';
    await guardar(n);
  }

  Future<void> perderAGravacao(int n) {
    final gravacao = estado.partes[estado.partIndexOf(n)!].path;
    return emTempoReal(() async => File(gravacao).deleteSync());
  }

  Future<void> perderAsCopias() => emTempoReal(() async {
    for (final copia in copias) {
      copia.deleteSync();
    }
    await sala.refreshUnsent();
    await settle();
  });

  Finder linha(int n) => byLabel('Cena $n — ${_cenas[n - 1].title}');

  Finder naLinha(int n, Finder alvo) =>
      find.descendant(of: linha(n), matching: alvo);

  Future<void> emTempoReal(Future<void> Function() corpo) async {
    await _semPrender(tester, corpo);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> ate(String what, bool Function() done) =>
      _ate(tester, what, done);

  SceneRow linhaDe(int n) =>
      estado.sceneRows.firstWhere((row) => row.number == n);

  bool assentou(int n) {
    final row = linhaDe(n);
    final unsent = row.unsent;
    return row.inTheAir == null &&
        (unsent == null ? row.saved : unsent.failure != null);
  }

  Future<void> ve(Finder alvo) => _ateVer(tester, alvo);

  bool sendoGuardada(int n) =>
      estado.machine.beingKept(estado.sessionId, estado.scopeOfRow(n));

  Future<void> abrirAPassagem(String pericope) => emTempoReal(() async {
    final antes = estado.sessionId;
    sala.leaveThePassage();
    await _esperar(
      'a sala abrir a Escolha',
      () => estado.stage == SalaStage.escolha && estado.naRoda != null,
    );
    await sala.goConversa(book: 'Ruth', pericope: pericope);
    await _esperar(
      'a passagem $pericope abrir',
      () =>
          estado.sessionId != null &&
          estado.sessionId != antes &&
          !estado.awaitingTheGuide,
    );
    await settle();
    sala.goEnsaio();
    await _esperar(
      'as cenas chegarem',
      () => estado.sceneRows.length == _cenas.length,
    );
    await settle();
  });

  Future<void> voltarAPassagem(String pericope) => emTempoReal(() async {
    final antes = estado.sessionId;
    sala.leaveThePassage();
    await _esperar(
      'a sala abrir a Escolha',
      () => estado.stage == SalaStage.escolha && estado.naRoda != null,
    );
    await sala.goConversa(book: 'Ruth', pericope: pericope);
    await _esperar(
      'a passagem $pericope abrir',
      () =>
          estado.sessionId != null &&
          estado.sessionId != antes &&
          !estado.awaitingTheGuide,
    );
    sala.goEnsaio();
    await settle(const Duration(milliseconds: 300));
  });

  Future<void> deixarATela() => tester.pumpWidget(const SizedBox());

  Future<void> voltarATela() => tester.pumpWidget(_aCasa(container));

  Future<void> tocar(Finder alvo) => emTempoReal(() async {
    await tester.ensureVisible(alvo);
    await tester.tap(alvo);
    await settle(const Duration(milliseconds: 400));
  });

  Future<void> comecarAGravar(int n) => emTempoReal(() async {
    sala.gravarACena(n);
    await _esperar(
      'a cena $n gravar',
      () => estado.ensaio == EnsaioStatus.recording,
    );
  });

  Future<void> gravar(int n) async {
    await comecarAGravar(n);
    await emTempoReal(() async {
      sala.gravarACena(n);
      await _esperar(
        'a gravação da cena $n esperar o visto',
        () => estado.ensaio == EnsaioStatus.recorded,
      );
    });
  }

  Future<void> guardar(int n) async {
    await gravar(n);
    await emTempoReal(() async {
      final antes = envios;
      sala.takeKeep();
      await _esperar('a cena $n subir', () => envios > antes);
    });
    await ate('a cena $n assentar', () => assentou(n));
  }

  Future<void> quinzeMinutos() async {
    for (var minuto = 0; minuto < 15; minuto++) {
      await tester.pump(const Duration(minutes: 1));
      await emTempoReal(() => settle(const Duration(milliseconds: 100)));
    }
  }

  Future<void> ateVer(Finder alvo) async {
    final waited = Stopwatch()..start();
    for (
      var vez = 0;
      alvo.evaluate().isEmpty &&
          (vez < 100 || waited.elapsed < const Duration(seconds: 30));
      vez++
    ) {
      await emTempoReal(() => settle(const Duration(milliseconds: 100)));
    }
    expect(alvo.evaluate(), isNotEmpty, reason: 'ver $alvo');
  }

  Future<void> guardarSemEsperar(int n) async {
    await gravar(n);
    await emTempoReal(() async => sala.takeKeep());
    await ate('a cena $n entrar na fila', () {
      final row = linhaDe(n);
      return !sendoGuardada(n) &&
          (row.unsent != null || row.inTheAir != null || row.saved);
    });
  }

  Future<void> gravarAPassagemInteira() => emTempoReal(() async {
    sala.recordTheWholePassageInstead();
    await _esperar(
      'a passagem inteira ser a linha',
      () => estado.recordsTheWhole && estado.sceneRows.length == 1,
    );
    await settle();
  });

  Future<void> gravarCenaPorCena() => emTempoReal(() async {
    sala.recordSceneByScene();
    await _esperar(
      'as cenas voltarem a ser as linhas',
      () => !estado.recordsTheWhole && estado.sceneRows.length == _cenas.length,
    );
    await settle();
  });

  Future<void> umaTomadaDeOutraVisita(int n, {required int pass}) =>
      emTempoReal(() async {
        await harness.takes.enqueue(
          harness.recorder.aFile('de-outra-visita-$n-$pass'),
          sessionId: estado.sessionId!,
          kind: partTakeKind,
          scope: KeptScope.parte(n),
          passNumber: pass,
        );
        await harness.takes.flush();
        await sala.refreshUnsent();
        await settle();
      });
}

Future<_Casa> _comAsQuatroPartesNaSala(WidgetTester tester) {
  final sala = SalaHarness(takesHome: aTempHome('sala-1872'));
  sala.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: [
      for (final n in [1, 2, 3, 4])
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: sala.recorder.aFile('parte-$n').path,
          takeId: 'gravacao-$n',
        ),
    ],
  );
  return _naCasa(tester, harness: sala);
}

Widget _aCasa(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: EnsaioView()),
  ),
);

Future<_Casa> _relancada(_Casa casa, {bool noPlano = false}) async {
  await casa.deixarATela();
  final (harness, container) = (await _semPrender(
    casa.tester,
    () => relaunch(casa.harness, casa.container),
  ))!;
  return _naCasa(
    casa.tester,
    harness: harness,
    relaunched: container,
    noPlano: noPlano,
  );
}

Future<_Casa> _naCasa(
  WidgetTester tester, {
  SalaHarness? harness,
  ProviderContainer? relaunched,
  bool noPlano = false,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sala = harness ?? SalaHarness();
  sala.room.passageScenes = _cenas;
  final container = (await _semPrender(
    tester,
    () async => (relaunched ?? sala.container())..read(salaSessionProvider),
  ))!;
  if (relaunched == null) addTearDown(container.dispose);
  await tester.pumpWidget(_aCasa(container));
  final casa = _Casa(tester, sala, container);
  await casa.emTempoReal(() async {
    await container.read(deviceLinkProvider.notifier).findTheTeam();
    await casa.sala.refreshUnsent();
    await casa.sala.openTheRoom();
    if (relaunched == null) {
      await casa.sala.goConversa(book: 'Ruth', pericope: 'P01');
    }
    await _esperar(
      'a sessão abrir',
      () => casa.estado.sessionId != null && !casa.estado.awaitingTheGuide,
    );
    await settle();
    if (relaunched != null) {
      casa.sala.openTheEnsaioFinal();
      await _esperar(
        'o ponto laranja decidir a tela',
        () =>
            casa.estado.ensaioFinalPlan is PlanRead ||
            casa.estado.station == const Ensaio(),
      );
      if (noPlano) return;
      casa.sala.recordSceneByScene();
    } else if (casa.estado.stage != SalaStage.ensaio) {
      casa.sala.goEnsaio();
    }
    await _esperar(
      'as cenas chegarem',
      () => casa.estado.sceneRows.length == _cenas.length,
    );
    await settle();
  });
  return casa;
}

Future<void> _recordAScene(SceneRoom room, {Uint8List? take}) async {
  room.harness.recorder.rehearsalSpeaks =
      take ?? Uint8List.fromList([for (var i = 0; i < 1200; i++) i % 251]);
  await theSceneMicrophoneOpens(room);
  room.sala.sceneTap();
  await _esperar(
    'o microfone da cena fechar',
    () => room.state.channel is! Microphone,
  );
}

Future<void> _pumpTheRoom(WidgetTester tester, SceneRoom room) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: room.container,
      child: const SalaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'a part take whose upload fails reads falhou and a tap sends the same take '
    'again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

      casa.room.unreachableTake = null;
      await casa.tocar(casa.naLinha(2, find.text(_falhou)));
      await casa.ve(casa.naLinha(2, find.text(_salvo)));

      expect(casa.room.takesKept, ['ensaio/parte-2']);
      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets(
    'a part take the room refuses as too large reads grande demais para o '
    'servidor',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.harness.recorder.rehearsalSpeaks = _grandeDemaisParaASala;
      await casa.guardarSemEsperar(2);
      await casa.ateVer(casa.naLinha(2, find.text(_grandeDemais)));

      expect(casa.naLinha(2, find.text(_grandeDemais)), findsOneWidget);
      expect(casa.envios, 0, reason: 'a sala não recebe o que não guardaria');
      expect(casa.copias, isNotEmpty);
    },
  );

  testWidgets(
    'a part take the room refuses for another reason reads não foi aceita',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = 'BAD_REQUEST';
      await casa.guardar(2);

      expect(casa.naLinha(2, find.text(_naoFoiAceita)), findsOneWidget);
      expect(casa.envios, 1, reason: 'uma recusa final não se tenta de novo');

      await casa.tocar(casa.naLinha(2, find.text(_naoFoiAceita)));

      expect(casa.envios, 1, reason: 'as palavras dela pedem gravar de novo');
    },
  );

  testWidgets(
    'a part the room refused is not offered under the plan\'s notice, where '
    'the home asks to record it again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = 'BAD_REQUEST';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_naoFoiAceita)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.sala.leaveTheRecording();
        await settle();
        casa.sala.openTheEnsaioFinal();
        await _esperar(
          'o plano ser lido',
          () => casa.estado.ensaioFinalPlan is PlanRead,
        );
        await settle();
      });

      expect(casa.estado.station, const Ensaio(step: EnsaioStep.plan));
      expect(casa.estado.unsentParts[2]?.failure, SendFailure.refused);
      expect(
        find.textContaining('enviar agora'),
        findsNothing,
        reason:
            'o plano oferecia enviar de novo uma gravação que a sala recusou, '
            'e a casa pede para gravar de novo',
      );
    },
  );

  testWidgets(
    'a send past eight seconds shows parar and its tap keeps the take reading '
    'falhou',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await tester.pump(const Duration(seconds: 7));
      expect(find.text(_parar), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      await casa.tocar(casa.naLinha(2, find.text(_parar)));
      await casa.ve(casa.naLinha(2, find.text(_falhou)));

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(find.text(_parar), findsNothing);
      expect(casa.copias, hasLength(1), reason: 'a gravação fica no tablet');
      expect(casa.envios, 1, reason: 'nada mais sobe nesta passada');
    },
  );

  testWidgets(
    'a whole-passage recording on its way reads enviando and shows parar past '
    'eight seconds',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.gravarAPassagemInteira();
      casa.room.holdNextTake(KeptScope.whole);
      await casa.guardarSemEsperar(1);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await tester.pump(const Duration(seconds: 8));

      expect(find.text(_enviando), findsOneWidget);
      expect(find.text(_parar), findsOneWidget);
    },
  );

  testWidgets(
    'a sentence held from a gone session keeps the approval from being '
    'offered until it is sent',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.retroSoFar = const BackTranslationProgress(checked: true);
      final frase = (await _semPrender(
        tester,
        () => casa.harness.takes.enqueue(
          casa.harness.recorder.aFile('frase-de-outra-visita'),
          sessionId: null,
          passage: 'Ruth/P01/pt',
          kind: sentenceKind,
          scope: '3',
        ),
      ))!;
      for (final n in [1, 2, 3]) {
        await casa.guardar(n);
      }
      await casa.emTempoReal(() async {
        await casa.sala.refreshUnsent();
        await settle();
      });

      expect(_aprovar, findsNothing);

      await casa.emTempoReal(() async {
        await casa.harness.takes.withdraw(frase);
        await casa.sala.refreshUnsent();
        await settle();
      });
      await casa.ateVer(_aprovar);

      expect(_aprovar, findsOneWidget);
    },
  );

  testWidgets(
    'after a switch to the whole passage the approval is offered while a part '
    'take spent before it is still on its way, and that take goes up with the '
    "team's next tap",
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room
        ..retroSoFar = const BackTranslationProgress(checked: true)
        ..unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

      await casa.gravarAPassagemInteira();
      await casa.guardar(1);
      await casa.ateVer(_aprovar);

      final aprovacoes = _aprovar.evaluate().length;
      final naSala = [...casa.room.takesKept];

      expect(aprovacoes, 1);
      expect(naSala, ['ensaio/${KeptScope.whole}']);

      casa.room.unreachableTake = null;
      await casa.quinzeMinutos();
      expect(casa.room.takesKept, naSala);

      await casa.guardar(1);

      expect(casa.room.takesKept, [
        'ensaio/${KeptScope.whole}',
        'ensaio/${KeptScope.whole}',
        'ensaio/parte-2',
      ]);
    },
  );

  testWidgets(
    'after a switch to scene by scene the approval is offered while a whole '
    'take spent before it is still on its way, and that take goes up with the '
    "team's next tap",
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.retroSoFar = const BackTranslationProgress(checked: true);
      await casa.gravarAPassagemInteira();
      casa.room.unreachableTake = 'ensaio/${KeptScope.whole}';
      await casa.guardar(1);
      expect(find.text(_falhou), findsOneWidget);

      await casa.gravarCenaPorCena();
      for (final n in [1, 2, 3]) {
        await casa.guardar(n);
      }
      await casa.ateVer(_aprovar);

      final aprovacoes = _aprovar.evaluate().length;
      final naSala = [...casa.room.takesKept];

      expect(aprovacoes, 1);
      expect(naSala, ['ensaio/parte-1', 'ensaio/parte-2', 'ensaio/parte-3']);

      casa.room.unreachableTake = null;
      await casa.quinzeMinutos();
      expect(casa.room.takesKept, naSala);

      await casa.guardar(3);

      expect(casa.room.takesKept.last, 'ensaio/${KeptScope.whole}');
    },
  );

  testWidgets(
    'a part take refused as too large blocks no approval once the passage is '
    'recorded whole, and stays on the tablet',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.retroSoFar = const BackTranslationProgress(checked: true);
      casa.harness.recorder.rehearsalSpeaks = _grandeDemaisParaASala;
      await casa.guardarSemEsperar(2);
      await casa.ateVer(casa.naLinha(2, find.text(_grandeDemais)));
      casa.harness.recorder.rehearsalSpeaks = null;

      await casa.gravarAPassagemInteira();
      await casa.guardar(1);
      await casa.ateVer(_aprovar);

      expect(_aprovar, findsOneWidget);
      expect(casa.copias, hasLength(1), reason: 'a parte 2 fica no tablet');
    },
  );

  testWidgets(
    'a spent whole-passage take is held for its tap while the grain is not '
    'known',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.gravarAPassagemInteira();
      casa.room.unreachableTake = 'ensaio/${KeptScope.whole}';
      await casa.guardar(1);
      expect(find.text(_falhou), findsOneWidget);
      final daInteira = casa.estado.sessionId;
      await casa.abrirAPassagem('P02');
      final ondeParou = casa.harness.emAberto.rows['Ruth/P01/pt']!;
      casa.harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: ondeParou.sessionId,
        stage: ondeParou.stage,
        savedAt: ondeParou.savedAt,
        language: ondeParou.language,
        wholeHeldByTheRoom: ondeParou.wholeHeldByTheRoom,
      );
      casa.room
        ..unreachableTake = null
        ..failTakesWith = const NetworkFailed('sem rede');

      await casa.voltarAPassagem('P01');
      final antes = casa.envios;
      await casa.emTempoReal(() async {
        await casa.harness.takes.flush();
        await settle(const Duration(milliseconds: 300));
      });

      expect(casa.estado.sessionId, daInteira);
      expect(casa.estado.grainInForce, isNull);
      expect(casa.envios, antes);
      expect(casa.room.takesKept, isNot(contains('ensaio/${KeptScope.whole}')));
    },
  );

  testWidgets(
    'a whole-passage take in the air reads nothing on scene 1 after a switch '
    'to scene by scene',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.gravarAPassagemInteira();
      casa.room.holdNextTake(KeptScope.whole);
      await casa.guardarSemEsperar(1);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await casa.gravarCenaPorCena();
      await casa.ate('a cena 1 ficar vazia', () {
        final row = casa.linhaDe(1);
        return row.unsent == null && row.inTheAir == null;
      });
      await tester.pump(const Duration(seconds: 8));

      expect(casa.naLinha(1, find.text(_enviando)), findsNothing);
      expect(casa.naLinha(1, find.text(_parar)), findsNothing);
      casa.room.finishHeldTake();
    },
  );

  testWidgets(
    'a whole-passage take kept this visit reads nothing on scene 1 after a '
    'switch to scene by scene',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.gravarAPassagemInteira();
      await casa.guardar(1);
      expect(find.text(_salvo), findsOneWidget);

      await casa.gravarCenaPorCena();

      expect(casa.naLinha(1, find.text(_salvo)), findsNothing);
      expect(casa.naLinha(1, find.text(_enviando)), findsNothing);
      expect(casa.naLinha(1, find.text(_falhou)), findsNothing);
    },
  );

  testWidgets(
    'a part take kept this visit reads nothing on the whole-passage row after '
    'a switch to the whole passage',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardar(1);
      expect(casa.naLinha(1, find.text(_salvo)), findsOneWidget);

      await casa.gravarAPassagemInteira();

      expect(find.text(_salvo), findsNothing);
      expect(find.text(_enviando), findsNothing);
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets('a send that lands within eight seconds never shows parar', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.holdNextTake('parte-2');
    await casa.guardarSemEsperar(2);
    await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text(_parar), findsNothing);

    await casa.emTempoReal(() async {
      casa.room.finishHeldTake();
      await settle(const Duration(milliseconds: 400));
    });
    await casa.ve(casa.naLinha(2, find.text(_salvo)));
    await tester.pump(const Duration(seconds: 2));

    expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    expect(find.text(_parar), findsNothing);
  });

  testWidgets(
    "a part's next recording waits its own eight seconds before parar shows",
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await casa.guardarSemEsperar(2);
      await tester.pump(const Duration(seconds: 8));
      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      casa.room
        ..finishHeldTake()
        ..holdNextTake('parte-2');
      await casa.ate(
        'a sala segurar a gravação seguinte',
        () => casa.room.takeHeld,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(casa.room.takesKept, ['ensaio/parte-2']);
      expect(find.text(_parar), findsNothing);
      await tester.pump(const Duration(seconds: 8));
      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    "a part saved in one session never reads salvo in the next session's "
    'rehearsal',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
      final primeira = casa.estado.sessionId;

      await casa.emTempoReal(() async {
        casa.sala.leaveThePassage();
        await _esperar(
          'a sala abrir a Escolha',
          () =>
              casa.estado.stage == SalaStage.escolha &&
              casa.estado.naRoda != null,
        );
        await casa.sala.goConversa(book: 'Ruth', pericope: 'P02');
        await _esperar(
          'a outra passagem abrir',
          () =>
              casa.estado.sessionId != null &&
              casa.estado.sessionId != primeira &&
              !casa.estado.awaitingTheGuide,
        );
        await settle();
        casa.sala.goEnsaio();
        await _esperar(
          'as cenas chegarem',
          () => casa.estado.sceneRows.length == _cenas.length,
        );
        await settle();
      });

      expect(find.text(_salvo), findsNothing);
    },
  );

  testWidgets(
    'a tap on falhou reads enviando at once and offers parar after eight '
    'seconds of the resend',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

      casa.room
        ..unreachableTake = null
        ..holdNextTake('parte-2');
      await casa.tocar(casa.naLinha(2, find.text(_falhou)));
      await casa.ve(casa.naLinha(2, find.text(_enviando)));

      expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);
      expect(find.text(_falhou), findsNothing);

      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await tester.pump(const Duration(seconds: 8));
      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
      await casa.ve(casa.naLinha(2, find.text(_salvo)));
      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a tap on falhou while another take is in the air reads enviando at once',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      casa.room
        ..unreachableTake = null
        ..holdNextTake('parte-3');
      await casa.guardarSemEsperar(3);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await casa.tocar(casa.naLinha(2, find.text(_falhou)));
      await casa.ve(casa.naLinha(2, find.text(_enviando)));

      expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);
      expect(find.text(_falhou), findsNothing);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await _esperar(
          'as duas cenas subirem',
          () => casa.room.takesKept.length == 2,
        );
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    'a take stopped while another take waits to go reads falhou at once',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await casa.guardarSemEsperar(3);
      casa.room.holdNextTakesList();
      final antes = casa.leiturasDaLista;
      await tester.pump(const Duration(seconds: 8));

      await casa.emTempoReal(() async {
        await tester.tap(casa.naLinha(2, find.text(_parar)));
        await _esperar(
          'a cena 3 subir e esperar a lista',
          () => casa.leiturasDaLista > antes,
        );
        await settle();
      });

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(casa.room.takesKept, ['ensaio/parte-3']);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTakesList();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets('a part being kept again reads enviando, never salvo', (
    tester,
  ) async {
    late _AQueueThatHoldsTheKeep fila;
    final casa = await _naCasa(
      tester,
      harness: SalaHarness(
        takesOverride: (room, home, recordings) =>
            fila = _AQueueThatHoldsTheKeep(
              room: room,
              home: () async => home,
              recordings: recordings,
            ),
      ),
    );
    await casa.guardar(2);
    expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);

    await casa.gravar(2);
    fila.segurar = Completer<void>();
    await casa.emTempoReal(() async {
      casa.sala.takeKeep();
      await settle();
    });

    expect(casa.naLinha(2, find.text(_salvo)), findsNothing);
    expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);

    await casa.emTempoReal(() async {
      fila.segurar?.complete();
      await _esperar(
        'a cena 2 subir de novo',
        () => casa.room.takesKept.length == 2,
      );
      await settle(const Duration(milliseconds: 400));
    });
  });

  testWidgets(
    'parar counts eight seconds from when the take left, across a screen '
    'left and reopened',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await tester.pump(const Duration(seconds: 5));

      await casa.deixarATela();
      await casa.voltarATela();
      await tester.pump(const Duration(milliseconds: 2800));
      expect(find.text(_parar), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));

      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    "a part whose newest take is lost never reads salvo for an earlier one",
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);

      await casa.emTempoReal(() async {
        for (final copia in casa.copias) {
          copia.deleteSync();
        }
        await casa.sala.refreshUnsent();
        await settle();
      });
      await casa.ve(casa.naLinha(2, find.text(_perdida)));

      expect(find.text(_salvo), findsNothing);
      expect(casa.naLinha(2, find.text(_perdida)), findsOneWidget);
    },
  );

  testWidgets(
    'a part whose newest take is gone still reads falhou — grave de novo after a relaunch, with nothing to play',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      await casa.perderAsCopias();
      await casa.ve(casa.naLinha(2, find.text(_perdida)));
      expect(casa.naLinha(2, find.text(_perdida)), findsOneWidget);

      final depois = await _relancada(casa);
      await depois.ve(depois.naLinha(2, find.text(_perdida)));

      expect(depois.naLinha(2, find.text(_perdida)), findsOneWidget);
      expect(depois.naLinha(2, find.byType(TextButton)), findsNothing);
      expect(depois.naLinha(2, byLabel(_ouvirNaLinha)), findsNothing);
    },
  );

  testWidgets(
    'a part whose copies are gone is never offered on the plan after a '
    'relaunch, where no tap could send it',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.perderAsCopias();
      await casa.ve(casa.naLinha(2, find.text(_perdida)));

      final depois = await _relancada(casa, noPlano: true);
      await depois.emTempoReal(settle);

      expect(depois.estado.station, const Ensaio(step: EnsaioStep.plan));
      expect(depois.estado.unsentParts[2]?.failure, SendFailure.gone);
      expect(
        find.textContaining('enviar agora'),
        findsNothing,
        reason:
            'o plano oferecia enviar uma gravação que já não existia, e o '
            'toque não fazia nada',
      );
    },
  );

  testWidgets(
    'a part saved before whose newest recording is gone reads falhou — grave de novo after a relaunch and still plays the room\'s part',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardarEFalharDeNovo(2);
      await casa.perderAGravacao(2);
      await casa.perderAsCopias();

      final depois = await _relancada(casa);
      await depois.ve(depois.naLinha(2, find.text(_perdida)));

      expect(depois.naLinha(2, find.text(_perdida)), findsOneWidget);
      expect(depois.naLinha(2, find.byType(TextButton)), findsNothing);
      expect(depois.naLinha(2, byLabel(_ouvirNaLinha)), findsOneWidget);
      expect(find.text(_salvo), findsNothing);
    },
  );

  testWidgets(
    'a gone part recorded again after a relaunch reads salvo once its take lands',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardarEFalharDeNovo(2);
      await casa.perderAGravacao(2);
      await casa.perderAsCopias();
      casa.room.unreachableTake = null;
      final depois = await _relancada(casa);
      await depois.ve(depois.naLinha(2, find.text(_perdida)));
      expect(depois.naLinha(2, find.text(_perdida)), findsOneWidget);

      await depois.guardar(2);
      await depois.ateVer(depois.naLinha(2, find.text(_salvo)));

      expect(depois.naLinha(2, find.text(_salvo)), findsOneWidget);
      expect(depois.naLinha(2, find.text(_perdida)), findsNothing);
    },
  );
  testWidgets(
    'an older pass that lands keeps telling its part\'s newer gone take, '
    'also after a relaunch',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await casa.guardarSemEsperar(2);
      final aNova = (await _semPrender(
        tester,
        casa.harness.takes.entries,
      ))!.lastWhere((row) => row.scope == 'parte-2');
      await casa.emTempoReal(() async {
        File(aNova.path).deleteSync();
        await casa.sala.refreshUnsent();
        await settle();
      });

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await _esperar(
          'a passagem 1 subir',
          () => casa.room.takesKept.isNotEmpty,
        );
        await settle(const Duration(milliseconds: 400));
      });
      await casa.ve(casa.naLinha(2, find.text(_perdida)));

      expect(casa.naLinha(2, find.text(_perdida)), findsOneWidget);
      expect(find.text(_salvo), findsNothing);
      await casa.emTempoReal(
        () => _esperar('a fila parar de escrever', () async {
          final linhas = await casa.harness.takes.entries();
          return linhas.length == 1 && linhas.single.lost;
        }),
      );
      final depois = await _relancada(casa);
      await depois.ve(depois.naLinha(2, find.text(_perdida)));
      expect(depois.naLinha(2, find.text(_perdida)), findsOneWidget);
      expect(find.text(_salvo), findsNothing);
    },
  );

  testWidgets('a part whose newest take is gone offers nothing to play', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.unreachableTake = 'ensaio/parte-2';
    await casa.guardar(2);
    await casa.perderAsCopias();
    await casa.ve(casa.naLinha(2, find.text(_perdida)));

    expect(casa.naLinha(2, find.text(_perdida)), findsOneWidget);
    expect(casa.naLinha(2, byLabel(_ouvirNaLinha)), findsNothing);
    expect(casa.naLinha(2, byLabel(_gravarDeNovoNaLinha)), findsOneWidget);
  });

  testWidgets('a tap on a row whose take is being sent sends nothing', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.holdNextTake('parte-2');
    await casa.guardarSemEsperar(2);
    await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
    final antes = casa.envios;

    expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);
    expect(casa.naLinha(2, find.byType(TextButton)), findsNothing);
    await casa.tocar(casa.naLinha(2, find.text(_enviando)));

    expect(casa.envios, antes);

    await casa.emTempoReal(() async {
      casa.room.finishHeldTake();
      await settle(const Duration(milliseconds: 400));
    });
    await casa.ve(casa.naLinha(2, find.text(_salvo)));
    expect(casa.envios, antes);
    expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
  });

  testWidgets(
    'a part that failed in a passage still reads falhou when the team comes '
    'back to it in the same run',
    (tester) async {
      final casa = await _naCasa(tester);
      final primeira = casa.estado.sessionId;
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

      await casa.abrirAPassagem('P02');
      await casa.abrirAPassagem('P01');
      await casa.ve(casa.naLinha(3, find.text(_falhou)));

      expect(casa.estado.sessionId, primeira);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
      expect(find.textContaining('enviar agora'), findsNothing);
    },
  );

  testWidgets(
    'a part saved in a passage still reads salvo when the team comes back to '
    'it in the same run',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);

      await casa.abrirAPassagem('P02');
      await casa.abrirAPassagem('P01');

      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a take still in the air when the team comes back to its passage offers '
    'parar and reads salvo once it lands',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-2');
      await casa.guardarSemEsperar(2);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await casa.abrirAPassagem('P02');
      await casa.abrirAPassagem('P01');
      await tester.pump(const Duration(seconds: 8));

      expect(casa.naLinha(2, find.text(_parar)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
      await casa.ve(casa.naLinha(2, find.text(_salvo)));

      expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a kept take whose copy is gone reads falhou, grave de novo at once',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.holdNextTake('parte-1');
      await casa.guardarSemEsperar(1);
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
      await casa.guardarSemEsperar(2);

      await casa.emTempoReal(() async {
        final linhas = await casa.harness.takes.entries();
        File(
          linhas.singleWhere((row) => row.scope == 'parte-2').path,
        ).deleteSync();
        await casa.sala.refreshUnsent();
        await settle();
      });
      await casa.ve(casa.naLinha(2, find.text(_perdida)));

      expect(casa.naLinha(2, find.text(_perdida)), findsOneWidget);
      expect(casa.naLinha(2, find.byType(TextButton)), findsNothing);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets(
    'a tap on a part whose newest take never reached the Outbox sends it, the '
    'spent take before it having left at the tap to record again',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

      fila.falhar = false;
      casa.room.unreachableTake = null;
      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.ve(casa.naLinha(3, find.text(_salvo)));

      expect(casa.room.takePasses, [2]);
      expect(casa.naLinha(3, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a tap on a part whose take never reached the Outbox, on a dead link, makes '
    'three attempts before falhou',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      fila.falhar = false;
      await casa.ve(casa.naLinha(3, find.text(_falhou)));
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
      casa.room.unreachableTake = 'ensaio/parte-3';

      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.ate(
        'as três tentativas',
        () => casa.envios == 3 && casa.assentou(3),
      );

      expect(casa.envios, 3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
    },
  );

  testWidgets(
    "a tap on a part never sends another session's spent take when the team "
    'moves to it during the send',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      await casa.abrirAPassagem('P02');
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
      await casa.abrirAPassagem('P01');

      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      fila.falhar = false;
      casa.room
        ..unreachableTake = null
        ..holdNextTake('parte-3');
      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);

      await casa.abrirAPassagem('P02');
      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 600));
      });

      expect(
        casa.room.takesKept.where((take) => take == 'ensaio/parte-3'),
        hasLength(1),
        reason: 'só a tomada de P01 que a equipe tocou subiu',
      );
    },
  );

  testWidgets(
    "under the whole passage another session's spent part take stays held for "
    'its tap and does not go up on the next pass',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.abrirAPassagem('P02');
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

      await casa.abrirAPassagem('P01');
      await casa.gravarAPassagemInteira();
      casa.room.unreachableTake = null;
      await casa.guardar(1);
      await casa.emTempoReal(() => settle(const Duration(milliseconds: 600)));

      expect(casa.room.takesKept, ['ensaio/${KeptScope.whole}']);
    },
  );

  testWidgets(
    'a part whose newest take never reached the Outbox and is gone reads '
    'falhou, grave de novo with no tap once the team taps it',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_salvo)), findsOneWidget);
      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      fila.falhar = false;
      await casa.ve(casa.naLinha(3, find.text(_falhou)));
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
      File(casa.harness.recorder.lastPath!).deleteSync();

      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.ve(casa.naLinha(3, find.text(_perdida)));

      expect(casa.naLinha(3, find.text(_perdida)), findsOneWidget);
      expect(casa.naLinha(3, find.byType(TextButton)), findsNothing);
      expect(find.text(_salvo), findsNothing);
    },
  );

  testWidgets(
    'a part whose newest take is gone is sent again by recording it again: '
    'the keep sends the new take alone, the spent pass having left at the tap '
    'to record again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      await casa.guardarSemEsperar(3);
      await casa.emTempoReal(() async {
        final linhas = await casa.harness.takes.entries();
        File(
          linhas.where((row) => row.scope == 'parte-3').last.path,
        ).deleteSync();
        await casa.sala.refreshUnsent();
        await settle();
      });
      await casa.ve(casa.naLinha(3, find.text(_perdida)));
      expect(casa.naLinha(3, find.text(_perdida)), findsOneWidget);
      expect(casa.naLinha(3, find.byType(TextButton)), findsNothing);
      casa.room.unreachableTake = null;
      final antes = casa.envios;
      await casa.emTempoReal(() async {
        casa.sala.enviarACena(3);
        await settle(const Duration(milliseconds: 400));
      });
      expect(casa.envios, antes);

      await casa.gravar(3);
      await casa.emTempoReal(() async => casa.sala.takeKeep());
      await casa.ve(casa.naLinha(3, find.text(_salvo)));

      expect(casa.room.takePasses, [3]);
      expect(casa.naLinha(3, find.text(_salvo)), findsOneWidget);
    },
  );

  testWidgets(
    'a tap on a part whose newest take again cannot reach the Outbox sends '
    'nothing, the spent pass having left at the tap to record again',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      casa.room.unreachableTake = null;

      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.emTempoReal(() => settle(const Duration(milliseconds: 400)));

      expect(casa.room.takePasses, isEmpty);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);
    },
  );

  testWidgets(
    'a tap on a part whose newest take is gone sends nothing, even with a '
    'spent pass ahead of it',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      fila.falhar = true;
      await casa.guardarSemEsperar(3);
      fila.falhar = false;
      File(casa.harness.recorder.lastPath!).deleteSync();
      await casa.tocar(casa.naLinha(3, find.text(_falhou)));
      await casa.ve(casa.naLinha(3, find.text(_perdida)));
      expect(casa.naLinha(3, find.text(_perdida)), findsOneWidget);
      final antes = casa.envios;

      await casa.emTempoReal(() async {
        casa.sala.enviarACena(3);
        await settle(const Duration(milliseconds: 400));
      });

      expect(casa.envios, antes);
    },
  );

  testWidgets('a row beyond the last scene offers no Gravar', (tester) async {
    final casa = await _naCasa(tester);
    casa.room.unreachableTake = 'ensaio/parte-4';
    await casa.umaTomadaDeOutraVisita(4, pass: 1);

    expect(_naQuarta(find.textContaining('enviar agora')), findsOneWidget);
    expect(_naQuarta(byLabel(_gravarNaLinha)), findsNothing);
  });

  testWidgets(
    'a row beyond the last scene offers neither Ouvir nor Gravar de novo, '
    'even over a part the room holds',
    (tester) async {
      final casa = await _comAsQuatroPartesNaSala(tester);
      casa.room.unreachableTake = 'ensaio/parte-4';
      await casa.umaTomadaDeOutraVisita(4, pass: 2);

      expect(_naQuarta(find.textContaining('enviar agora')), findsOneWidget);
      expect(_naQuarta(byLabel(_ouvirNaLinha)), findsNothing);
      expect(_naQuarta(byLabel(_gravarDeNovoNaLinha)), findsNothing);
    },
  );

  testWidgets('recording on a row beyond the last scene records nothing', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.unreachableTake = 'ensaio/parte-4';
    await casa.umaTomadaDeOutraVisita(4, pass: 1);
    final antes = casa.harness.recorder.captures;

    await casa.emTempoReal(() async {
      casa.sala.gravarACena(4);
      await settle(const Duration(milliseconds: 300));
    });

    expect(casa.harness.recorder.captures, antes);
    expect(casa.estado.ensaio, EnsaioStatus.idle);
  });

  testWidgets(
    'a tap on a part beyond the last scene sends its older pass first',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-4';
      await casa.umaTomadaDeOutraVisita(4, pass: 1);
      await casa.umaTomadaDeOutraVisita(4, pass: 2);

      casa.room.unreachableTake = null;
      await casa.tocar(_naQuarta(find.textContaining('enviar agora')));
      await casa.ate(
        'as duas passadas subirem',
        () => casa.room.takePasses.length == 2,
      );

      expect(casa.room.takePasses, [1, 2]);
    },
  );

  testWidgets(
    'an earlier-visit take of a part beyond the last scene reads on its own '
    'numbered row, its tap sends it, and the row leaves',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-4';
      await casa.umaTomadaDeOutraVisita(4, pass: 1);
      expect(_aQuarta, findsOneWidget);
      expect(_naQuarta(find.textContaining('enviar agora')), findsOneWidget);

      casa.room.unreachableTake = null;
      await casa.tocar(_naQuarta(find.textContaining('enviar agora')));
      await casa.ate(
        'a quarta subir e sair',
        () =>
            casa.room.takesKept.contains('ensaio/parte-4') &&
            _aQuarta.evaluate().isEmpty,
      );

      expect(casa.room.takesKept, contains('ensaio/parte-4'));
      expect(_aQuarta, findsNothing);
    },
  );

  testWidgets('a part reads enviando from the moment its keep starts', (
    tester,
  ) async {
    late _AQueueThatHoldsTheKeep fila;
    final casa = await _naCasa(
      tester,
      harness: SalaHarness(
        takesOverride: (room, home, recordings) =>
            fila = _AQueueThatHoldsTheKeep(
              room: room,
              home: () async => home,
              recordings: recordings,
            ),
      ),
    );
    fila.falhar = true;
    await casa.guardarSemEsperar(3);
    fila.falhar = false;
    await casa.gravar(3);

    casa.sala.takeKeep();

    expect(casa.estado.sceneRows[2].unsent, isNotNull);
    expect(casa.estado.sceneRows[2].unsent?.failure, isNull);
    await casa.emTempoReal(() => settle(const Duration(milliseconds: 400)));
  });

  testWidgets('a tap on a part being kept sends nothing', (tester) async {
    late _AQueueThatHoldsTheKeep fila;
    final casa = await _naCasa(
      tester,
      harness: SalaHarness(
        takesOverride: (room, home, recordings) =>
            fila = _AQueueThatHoldsTheKeep(
              room: room,
              home: () async => home,
              recordings: recordings,
            ),
      ),
    );
    casa.room.unreachableTake = 'ensaio/parte-3';
    await casa.guardar(3);
    fila.falhar = true;
    await casa.guardarSemEsperar(3);
    fila.falhar = false;
    casa.room.unreachableTake = null;
    await casa.gravar(3);
    final antes = casa.envios;

    await casa.emTempoReal(() async {
      fila.segurar = Completer<void>();
      casa.sala.takeKeep();
      casa.sala.enviarACena(3);
      fila.segurar?.complete();
      await settle(const Duration(milliseconds: 400));
    });

    expect(
      casa.envios,
      antes + 1,
      reason: 'só a própria guarda manda a tomada; o toque não manda nada',
    );
  });

  testWidgets('a tap whose app run ends while it reads the Outbox sends '
      'nothing', (tester) async {
    late _AQueueThatHoldsTheKeep fila;
    final casa = await _naCasa(
      tester,
      harness: SalaHarness(
        takesOverride: (room, home, recordings) =>
            fila = _AQueueThatHoldsTheKeep(
              room: room,
              home: () async => home,
              recordings: recordings,
            ),
      ),
    );
    casa.room.unreachableTake = 'ensaio/parte-3';
    await casa.guardar(3);
    casa.room.unreachableTake = null;
    final antes = casa.envios;

    await casa.emTempoReal(() async {
      fila.segurarAContagem = Completer<void>();
      casa.sala.enviarACena(3);
      await settle();
      casa.container.invalidate(salaSessionProvider);
      fila.segurarAContagem?.complete();
      await settle(const Duration(milliseconds: 400));
    });

    expect(casa.envios, antes);
  });

  testWidgets(
    'a part being kept again reads enviando and offers no tap, even over a '
    'failed take',
    (tester) async {
      late _AQueueThatHoldsTheKeep fila;
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) =>
              fila = _AQueueThatHoldsTheKeep(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      casa.room.unreachableTake = 'ensaio/parte-3';
      await casa.guardar(3);
      expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

      await casa.gravar(3);
      fila.segurar = Completer<void>();
      await casa.emTempoReal(() async {
        casa.sala.takeKeep();
        await settle();
      });

      expect(casa.naLinha(3, find.text(_enviando)), findsOneWidget);
      expect(casa.naLinha(3, find.byType(TextButton)), findsNothing);

      await casa.emTempoReal(() async {
        fila.segurar?.complete();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets("a take reads salvo only after the room's list holds it", (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.holdNextTakesList();
    final antes = casa.leiturasDaLista;
    await casa.guardarSemEsperar(2);
    await casa.emTempoReal(
      () => _esperar('a lista ser lida', () => casa.leiturasDaLista > antes),
    );

    expect(casa.room.takesKept, ['ensaio/parte-2']);
    expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);
    expect(find.text(_salvo), findsNothing);

    await casa.emTempoReal(() async {
      casa.room.finishHeldTakesList();
      await settle(const Duration(milliseconds: 400));
    });
    await casa.ve(casa.naLinha(2, find.text(_salvo)));

    expect(casa.naLinha(2, find.text(_salvo)), findsOneWidget);
    expect(find.text(_enviando), findsNothing);
  });

  testWidgets(
    'an upload the room answers but does not list is a failed attempt and its '
    'copy stays',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unlistedTake = 'ensaio/parte-2';
      await casa.guardar(2);

      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(find.text(_salvo), findsNothing);
      expect(casa.copias, hasLength(1));
    },
  );

  testWidgets(
    'three failed attempts stop at falhou and no fourth upload leaves without '
    'a tap',
    (tester) async {
      final casa = await _naCasa(
        tester,
        harness: SalaHarness()
          ..takeSpacing = const [Duration(seconds: 1), Duration(seconds: 3)],
      );
      casa.room.unlistedTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.emTempoReal(
        () => _esperar('a terceira tentativa', () => casa.envios == 3),
      );
      await casa.emTempoReal(() => settle(const Duration(seconds: 1)));

      expect(casa.envios, 3);
      final enviadas = casa.room.takesSentAt;
      expect(
        enviadas[1].difference(enviadas[0]),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(
        enviadas[2].difference(enviadas[1]),
        greaterThanOrEqualTo(const Duration(seconds: 3)),
      );
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
    },
  );

  testWidgets('a network failure counts as one of the three attempts', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    casa.room.takeAnswersFirst.addAll(const [
      NetworkFailed('sem rede'),
      NetworkFailed('sem rede'),
      NetworkFailed('sem rede'),
    ]);
    await casa.guardar(2);
    await casa.emTempoReal(() => settle(const Duration(milliseconds: 500)));

    expect(casa.envios, 3);
    expect(casa.room.takesKept, isEmpty);
    expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
  });

  testWidgets(
    'a tap after three failed attempts gives the take three attempts again',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      await casa.emTempoReal(() => settle(const Duration(milliseconds: 500)));
      expect(casa.envios, 3);

      await casa.tocar(casa.naLinha(2, find.text(_falhou)));
      await casa.ate(
        'mais três tentativas',
        () => casa.envios == 6 && casa.assentou(2),
      );

      expect(casa.envios, 6);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
    },
  );

  testWidgets(
    'a scene take that fails on the red microphone shows não deu para guardar '
    'o ensaio da cena as visible text and falhou as its tap',
    (tester) async {
      late SceneRoom room;
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.failSceneWith = const NetworkFailed('sem rede');
        await _recordAScene(room);
        await _esperar(
          'o ensaio ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
      });
      await _pumpTheRoom(tester, room);

      expect(find.text(_naoDeuParaGuardar), findsOneWidget);
      expect(find.text(_falhou), findsOneWidget);

      final antes = room.asked('keepSceneRehearsal');
      room.harness.room.failSceneWith = null;
      await tester.tap(find.text(_falhou));
      for (
        var i = 0;
        i < 50 && room.asked('keepSceneRehearsal') == antes;
        i++
      ) {
        await _semPrender(tester, settle);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _semPrender(tester, settle);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_falhou), findsNothing);
      expect(find.text(_naoDeuParaGuardar), findsNothing);
      expect(room.asked('keepSceneRehearsal'), greaterThan(antes));
    },
  );

  testWidgets(
    'a scene take whose copy is gone reads falhou with no tap on the red '
    'microphone, and a re-send of it is refused',
    (tester) async {
      late SceneRoom room;
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.failSceneWith = const NetworkFailed('sem rede');
        await _recordAScene(room);
        await _esperar(
          'o ensaio ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        room.harness.room.failSceneWith = null;
        final linhas = await room.harness.takes.entries();
        File(
          linhas.singleWhere((row) => row.kind == sceneTakeKind).path,
        ).deleteSync();
      });
      await _pumpTheRoom(tester, room);
      await _ateVer(tester, find.text(_falhou));
      await tester.tap(find.text(_falhou));
      for (var i = 0; i < 100 && room.state.scene.keep is Keeping; i++) {
        await _semPrender(tester, settle);
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text(_naoDeuParaGuardar), findsOneWidget);
      expect(find.text(_perdidaNoMicrofone), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, _perdidaNoMicrofone),
        findsNothing,
      );
      expect(find.text(_falhou), findsNothing);

      room.sala.sendTheSceneTakeAgain();

      expect(room.state.scene.keep, isA<NotKept>());
      expect(room.harness.room.sceneTakesSent, isEmpty);
    },
  );

  testWidgets(
    'a scene take that never reached the Outbox and whose recording is gone '
    'reads falhou with no tap on the red microphone',
    (tester) async {
      late SceneRoom room;
      late _AQueueThatHoldsTheKeep fila;
      await _semPrender(tester, () async {
        room = await atRest(
          SalaHarness(
            takesOverride: (sala, home, recordings) =>
                fila = _AQueueThatHoldsTheKeep(
                  room: sala,
                  home: () async => home,
                  recordings: recordings,
                ),
          ),
        );
        await theScreenOpens(room);
        fila.falhar = true;
        await _recordAScene(room);
        await _esperar(
          'o ensaio ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        File(room.harness.recorder.lastPath!).deleteSync();
      });
      await _pumpTheRoom(tester, room);
      await _ateVer(tester, find.text(_falhou));
      await tester.tap(find.text(_falhou));
      for (var i = 0; i < 100 && room.state.scene.keep is Keeping; i++) {
        await _semPrender(tester, settle);
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text(_perdidaNoMicrofone), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, _perdidaNoMicrofone),
        findsNothing,
      );
      expect(find.text(_falhou), findsNothing);
    },
  );

  testWidgets(
    'parar on the red microphone stops a spent scene take sent ahead of the '
    'new one, and a tap sends both in the order recorded',
    (tester) async {
      late SceneRoom room;
      final a = Uint8List.fromList([for (var i = 0; i < 1200; i++) i % 7]);
      final b = Uint8List.fromList([for (var i = 0; i < 1200; i++) i % 11]);
      int keeps() => room.asked('keepSceneRehearsal');
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.failSceneWith = const NetworkFailed('sem rede');
        await _recordAScene(room, take: a);
        await _esperar(
          'a tomada A ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        room.harness.room
          ..failSceneWith = null
          ..holdNextKeepBeforeTheRoomActs();
        final antes = keeps();
        await _recordAScene(room, take: b);
        await _esperar('a tomada A subir na frente', () => keeps() > antes);
      });
      await _pumpTheRoom(tester, room);
      await tester.pump(const Duration(seconds: 8));
      expect(find.text(_parar), findsOneWidget);

      await _semPrender(tester, () async {
        await tester.tap(find.text(_parar));
        await _esperar(
          'a tomada B ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        room.harness.room.finishHeldKeep();
        await settle();
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(_naoDeuParaGuardar), findsOneWidget);
      expect(find.text(_falhou), findsOneWidget);
      expect(room.harness.room.sceneTakesSent, [a], reason: 'B nunca subiu');
      final copias = await _semPrender(tester, room.harness.takes.entries);
      expect(copias!.where((row) => row.kind == sceneTakeKind), hasLength(2));
      for (final row in copias) {
        expect(File(row.path).existsSync(), isTrue);
      }

      await tester.tap(find.text(_falhou));
      await _ate(
        tester,
        'as duas tomadas subirem',
        () => room.harness.room.sceneTakesSent.length == 3,
      );

      expect(room.harness.room.sceneTakesSent.skip(1), [a, b]);
    },
  );

  testWidgets(
    "parar on the red microphone counts eight seconds from when the keep's "
    'first take left, across the takes ahead of it',
    (tester) async {
      late SceneRoom room;
      int keeps() => room.asked('keepSceneRehearsal');
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.failSceneWith = const NetworkFailed('sem rede');
        await _recordAScene(
          room,
          take: Uint8List.fromList([for (var i = 0; i < 1200; i++) i % 7]),
        );
        await _esperar(
          'a tomada A ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
        room.harness.room
          ..failSceneWith = null
          ..holdNextKeepBeforeTheRoomActs();
        final antes = keeps();
        await _recordAScene(
          room,
          take: Uint8List.fromList([for (var i = 0; i < 1200; i++) i % 11]),
        );
        await _esperar('a tomada A subir na frente', () => keeps() > antes);
      });
      await _pumpTheRoom(tester, room);
      await tester.pump(const Duration(seconds: 5));

      await _semPrender(tester, () async {
        final antes = keeps();
        room.harness.room
          ..finishHeldKeep()
          ..holdNextKeepBeforeTheRoomActs();
        await _esperar('a tomada B subir', () => keeps() > antes);
        await settle();
      });
      await tester.pump(const Duration(milliseconds: 2800));
      expect(find.text(_parar), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_parar), findsOneWidget);

      await _semPrender(tester, () async {
        room.harness.room.finishHeldKeep();
        await translateOpens(room);
      });
    },
  );

  testWidgets(
    'a scene take too large on the red microphone shows grande demais para o '
    'servidor as visible text',
    (tester) async {
      late SceneRoom room;
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        await _recordAScene(room, take: _grandeDemaisParaASala);
        await _esperar(
          'o ensaio ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
      });
      await _pumpTheRoom(tester, room);
      await _ateVer(tester, find.text(_grandeDemais));

      expect(find.text(_grandeDemais), findsOneWidget);
      expect(find.text(_falhou), findsOneWidget);
      expect(room.asked('keepSceneRehearsal'), 0);
    },
  );

  testWidgets(
    'a scene take reads «guardando o ensaio da cena…» on the red microphone, '
    "never enviando, until the room's scene rehearsals list holds it, and "
    'opens on translate after',
    (tester) async {
      late SceneRoom room;
      late int antes;
      await _semPrender(tester, () async {
        room = await atRest();
        await theScreenOpens(room);
        antes = room.asked('sceneRehearsalsOf');
        room.harness.room.holdNextSceneList();
        await _recordAScene(room);
        await _esperar(
          'a lista dos ensaios da cena ser lida',
          () => room.asked('sceneRehearsalsOf') > antes,
        );
        await settle();
      });
      await _pumpTheRoom(tester, room);

      expect(room.asked('keepSceneRehearsal'), 1);
      expect(
        find.text('guardando o ensaio da cena…'),
        findsOneWidget,
        reason: 'o microfone vermelho escrevia «enviando…», que não é dela',
      );
      expect(find.text(_enviando), findsNothing);
      expect(room.state.scene.step, SceneStep.record);

      await _semPrender(tester, () async {
        room.harness.room.finishHeldSceneList();
        await translateOpens(room);
      });
    },
  );

  testWidgets(
    "a take's row reads gravando while recording and enviando while its send "
    'is in flight',
    (tester) async {
      final casa = await _naCasa(tester);
      await casa.comecarAGravar(2);

      expect(casa.naLinha(2, find.text('$_gravando · 0:00')), findsOneWidget);

      casa.room.holdNextTake('parte-2');
      await casa.emTempoReal(() async {
        casa.sala.gravarACena(2);
        await _esperar(
          'a gravação esperar o visto',
          () => casa.estado.ensaio == EnsaioStatus.recorded,
        );
        casa.sala.takeKeep();
        await _esperar('a cena subir', () => casa.envios > 0);
        await settle();
      });

      expect(casa.naLinha(2, find.textContaining(_gravando)), findsNothing);
      expect(casa.naLinha(2, find.text(_enviando)), findsOneWidget);

      await casa.emTempoReal(() async {
        casa.room.finishHeldTake();
        await settle(const Duration(milliseconds: 400));
      });
    },
  );

  testWidgets('no line is spoken when an upload fails, is refused or is '
      'stopped', (tester) async {
    final casa = await _naCasa(tester);
    final antes = casa.falas.length;
    expect(antes, greaterThan(0), reason: 'a voz falou ao abrir a passagem');

    casa.room.unreachableTake = 'ensaio/parte-1';
    await casa.guardar(1);
    expect(casa.naLinha(1, find.text(_falhou)), findsOneWidget);

    casa.room
      ..refuseTake = 'ensaio/parte-2'
      ..refuseTakeCode = 'BAD_REQUEST';
    await casa.guardar(2);
    expect(casa.naLinha(2, find.text(_naoFoiAceita)), findsOneWidget);

    casa.room.holdNextTake('parte-3');
    await casa.guardarSemEsperar(3);
    await casa.ate('a sala segurar a gravação', () => casa.room.takeHeld);
    await tester.pump(const Duration(seconds: 8));
    await casa.tocar(casa.naLinha(3, find.text(_parar)));
    await casa.ve(casa.naLinha(3, find.text(_falhou)));
    expect(casa.naLinha(3, find.text(_falhou)), findsOneWidget);

    await casa.emTempoReal(() => settle(const Duration(milliseconds: 500)));
    expect(casa.falas.skip(antes), isEmpty);
  });
}

class _AQueueThatHoldsTheKeep extends TakeUploadQueue {
  _AQueueThatHoldsTheKeep({
    required super.room,
    super.home,
    required super.recordings,
  });

  Completer<void>? segurar;
  Completer<void>? segurarAContagem;
  bool falhar = false;

  @override
  Future<OutboxTally> tally({
    required String? sessionId,
    String? passage,
  }) async {
    await segurarAContagem?.future;
    return super.tally(sessionId: sessionId, passage: passage);
  }

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
    await segurar?.future;
    if (falhar) throw const FileSystemException('o disco encheu');
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
