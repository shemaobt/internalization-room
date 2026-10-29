import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'support/temp.dart';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _quatroCenas = [
  ..._cenas,
  Scene(sceneId: 'S4', title: 'A chegada a Belém'),
];

const _ouvir = 'Ouvir';
const _gravar = 'Gravar';
const _gravarDeNovo = 'Gravar de novo';
const _parar = 'Parar';
const _enviarAGravacao = 'Enviar a gravação';
const _irParaATraducao = 'Traduzir a gravação';
const _sessao = 'sessao-antiga';
const _linhaDoTablet = 'Ruth/P01/pt';

String _daSala(int n) => 'da-sala-$n';

Finder _linha(int n) => byLabel('Cena $n — ${_quatroCenas[n - 1].title}');

Finder _naLinha(int n, String controle) =>
    find.descendant(of: _linha(n), matching: byLabel(controle));

bool _acesa(WidgetTester tester, Finder controle) =>
    tester.widget<Semantics>(controle).properties.enabled == true;

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

List<String> _buscadas(SalaHarness harness) => [
  for (final url in harness.room.clipsFetched)
    if (url.contains('/takes/')) url.split('/takes/')[1].split('/')[0],
];

TakeView _naSala(int n, {int? pass}) => TakeView(
  takeId: _daSala(n),
  kind: 'ensaio',
  scope: 'parte-$n',
  ordinal: n,
  pass: pass,
);

Future<void> _passo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _passos(WidgetTester tester, [int quantos = 4]) async {
  for (var i = 0; i < quantos; i++) {
    await _passo(tester);
  }
}

/// The held part lands, and the next part asked for is held in its turn.
Future<void> _chegaUma(WidgetTester tester, SalaHarness harness) async {
  await tester.runAsync(() async {
    harness.room.finishHeldClip();
    harness.room.holdNextClip();
  });
  await _passos(tester);
}

Future<void> _chegamTodas(WidgetTester tester, SalaHarness harness) async {
  await tester.runAsync(() async => harness.room.finishHeldClip());
  await _passos(tester, 8);
}

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _gravarNaLinha(
  WidgetTester tester,
  int n, {
  bool deNovo = false,
}) async {
  await _tocar(tester, _naLinha(n, deNovo ? _gravarDeNovo : _gravar));
  await _tocar(tester, _naLinha(n, _parar));
  await _tocar(tester, offTheRows(_enviarAGravacao));
  await letTheRehearsalReachTheRoom(tester);
}

Future<ProviderContainer> _abrir(
  WidgetTester tester,
  SalaHarness harness, {
  bool aLeituraFicaNoAr = false,
}) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  await tester.runAsync(notifier.abrirEscolha);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() async {
    final abrindo = notifier.goConversa(book: 'Ruth', pericope: 'P01');
    if (!aLeituraFicaNoAr) await abrindo;
  });
  await _passos(tester, 6);
  return container;
}

/// A passage reopened on the Rehearsal on a tablet that holds, of the parts [numeros]
/// its Resume point names, only the files of [aqui]; the room lists [naSala].
Future<ProviderContainer> _retomar(
  WidgetTester tester,
  SalaHarness harness, {
  List<int> numeros = const [1, 2, 3],
  Set<int> aqui = const {},
  List<TakeView>? naSala,
  List<Scene> cenas = _cenas,
  bool aLeituraFicaNoAr = false,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final casa = aTempDir('sala-1762-retomada');
  harness
    ..room.passageScenes = cenas
    ..room.takes.addAll(naSala ?? [for (final n in numeros) _naSala(n)]);
  for (final n in numeros) {
    harness.room.takeAudio[_daSala(n)] = Uint8List.fromList([n, n, n]);
  }
  harness.emAberto.rows[_linhaDoTablet] = ResumePoint(
    sessionId: _sessao,
    stage: SalaStage.ensaio,
    takes: [
      for (final n in numeros)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: aqui.contains(n)
              ? (File('${casa.path}/p$n.m4a')..writeAsBytesSync([n])).path
              : '${casa.path}/p$n.m4a',
          takeId: _daSala(n),
        ),
    ],
  );
  return _abrir(tester, harness, aLeituraFicaNoAr: aLeituraFicaNoAr);
}

void main() {
  testWidgets(
    'three parts the tablet does not hold show three rows before any part '
    'comes down, and play lights one by one as each lands',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.holdNextClip();
      final container = await _retomar(tester, harness);

      expect(_estado(container).stage, SalaStage.ensaio);
      expect(_estado(container).awaitingTheGuide, isFalse);
      for (var n = 1; n <= 3; n++) {
        expect(_naLinha(n, _ouvir), findsOneWidget);
        expect(_naLinha(n, _gravarDeNovo), findsOneWidget);
        expect(_acesa(tester, _naLinha(n, _ouvir)), isFalse);
      }
      expect(_buscadas(harness), [_daSala(1)]);

      await _chegaUma(tester, harness);
      expect(_acesa(tester, _naLinha(1, _ouvir)), isTrue);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isFalse);
      expect(_acesa(tester, _naLinha(3, _ouvir)), isFalse);
      expect(_buscadas(harness), [_daSala(1), _daSala(2)]);

      await _chegaUma(tester, harness);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isTrue);
      expect(_acesa(tester, _naLinha(3, _ouvir)), isFalse);

      await _chegamTodas(tester, harness);
      expect(_acesa(tester, _naLinha(3, _ouvir)), isTrue);
      expect(_buscadas(harness), [_daSala(1), _daSala(2), _daSala(3)]);
    },
  );

  testWidgets(
    'the home is there while a part fetch hangs past the watchdog, and no one '
    'is called',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        busyCeiling: const Duration(milliseconds: 200),
      );
      harness.room.holdNextClip();
      final container = await _retomar(tester, harness);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump(const Duration(seconds: 1));

      for (var n = 1; n <= 3; n++) {
        expect(_naLinha(n, _ouvir), findsOneWidget);
      }
      expect(_estado(container).needsPerson, isFalse);

      await _chegamTodas(tester, harness);
      expect(_acesa(tester, _naLinha(1, _ouvir)), isTrue);
    },
  );

  testWidgets(
    'a fetch that fails leaves its row, and the next tap fetches it again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room
        ..failClipOf[_daSala(2)] = const NetworkFailed('sem rede')
        ..holdNextClip();
      final container = await _retomar(tester, harness);
      final vozes = [...harness.voice.assets];

      await _chegamTodas(tester, harness);

      expect(_acesa(tester, _naLinha(1, _ouvir)), isTrue);
      expect(_acesa(tester, _naLinha(3, _ouvir)), isTrue);
      expect(_naLinha(2, _ouvir), findsOneWidget);
      expect(_naLinha(2, _gravarDeNovo), findsOneWidget);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isTrue);
      expect(harness.playback.played, isEmpty);
      expect(_estado(container).needsPerson, isFalse);
      expect(harness.voice.assets, vozes);

      harness.room.failClipOf.clear();
      await _tocar(tester, _naLinha(2, _ouvir));
      await _passos(tester, 6);

      expect(_buscadas(harness), [
        _daSala(1),
        _daSala(2),
        _daSala(3),
        _daSala(2),
      ]);
      expect(harness.playback.played, isEmpty);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isTrue);

      await _tocar(tester, _naLinha(2, _ouvir));
      expect(harness.playback.played.last, contains(_daSala(2)));
    },
  );

  testWidgets(
    'a refusal of one part audio no longer sends the team to the Choice',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.failClipOf[_daSala(2)] = const Refused(
        RefusalCode.forbidden,
      );
      final container = await _retomar(tester, harness);
      await _passos(tester, 8);

      expect(_estado(container).stage, SalaStage.ensaio);
      expect(_estado(container).needsPerson, isFalse);
      for (var n = 1; n <= 3; n++) {
        expect(_naLinha(n, _gravarDeNovo), findsOneWidget);
      }

      harness.room.failClipOf.clear();
      await _tocar(tester, _naLinha(2, _ouvir));
      await _passos(tester, 6);
      await _tocar(tester, _naLinha(2, _ouvir));
      expect(harness.playback.played.last, contains(_daSala(2)));
    },
  );

  testWidgets(
    'a part the tablet still holds is not fetched and plays at once',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.holdNextClip();
      await _retomar(tester, harness, aqui: {2});

      expect(_acesa(tester, _naLinha(2, _ouvir)), isTrue);
      expect(_acesa(tester, _naLinha(1, _ouvir)), isFalse);
      expect(_acesa(tester, _naLinha(3, _ouvir)), isFalse);
      await _tocar(tester, _naLinha(2, _ouvir));
      expect(harness.playback.played.last, endsWith('/p2.m4a'));

      await _chegamTodas(tester, harness);
      expect(_buscadas(harness), [_daSala(1), _daSala(3)]);
    },
  );

  testWidgets(
    'the parts keep their order and the stretches keep their parts while '
    'they come down',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room
        ..retroSoFar = BackTranslationProgress(
          segments: [
            for (final n in [1, 2, 3])
              SegmentView(
                segmentId: 'trecho-$n',
                takeId: _daSala(n),
                startsMs: 0,
                endsMs: 10000,
              ),
          ],
        )
        ..holdNextClip();
      final container = await _retomar(tester, harness);

      expect(
        [for (final trecho in _estado(container).btTrechos) trecho.parte],
        [0, 1, 2],
      );

      for (var n = 1; n <= 3; n++) {
        await _chegaUma(tester, harness);
        await _tocar(tester, _naLinha(n, _ouvir));
        expect(harness.playback.played.last, contains(_daSala(n)));
      }
      expect(
        [for (final trecho in _estado(container).btTrechos) trecho.parte],
        [0, 1, 2],
      );
    },
  );

  testWidgets(
    'what the team heard of a part fetched behind its row is reported under '
    'that part own recording, and nothing for the parts it never heard',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      await _retomar(tester, harness);
      await _passos(tester, 8);

      harness.playback.length = const Duration(seconds: 10);
      await _tocar(tester, _naLinha(1, _ouvir));
      for (var i = 0; i < 20 && !harness.playback.open; i++) {
        await _passo(tester);
      }
      await tester.runAsync(() async {
        harness.playback
          ..at = const Duration(seconds: 10)
          ..finishPlayback();
      });
      await _passos(tester);

      final relato = {
        for (final parte in harness.room.listeningReports.last)
          parte['take_id']! as String: parte['played_ranges'],
      };
      expect(relato[_daSala(1)], [
        [0, 10000],
      ]);
      expect(relato.containsKey(_daSala(2)), isFalse);
      expect(relato.containsKey(_daSala(3)), isFalse);
    },
  );

  testWidgets(
    'the wood play and the advance disc stay dark until every part is here',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.holdNextClip();
      final container = await _retomar(tester, harness);

      expect(_acesa(tester, offTheRows(_ouvir)), isFalse);
      expect(_acesa(tester, inTheHome(_irParaATraducao)), isFalse);
      container.read(salaSessionProvider.notifier).startRetro();
      await _passos(tester);
      expect(_estado(container).stage, SalaStage.ensaio);

      await _chegaUma(tester, harness);
      await _chegaUma(tester, harness);
      expect(_acesa(tester, offTheRows(_ouvir)), isFalse);
      expect(_acesa(tester, inTheHome(_irParaATraducao)), isFalse);

      await _chegamTodas(tester, harness);
      expect(_acesa(tester, offTheRows(_ouvir)), isTrue);
      expect(_acesa(tester, inTheHome(_irParaATraducao)), isTrue);
    },
  );
  testWidgets(
    'recording a scene again while its part comes down goes above the room '
    'pass, and the room copy never replaces it',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.holdNextClip();
      await _retomar(
        tester,
        harness,
        naSala: [_naSala(1), _naSala(2, pass: 2), _naSala(3)],
      );
      await _chegaUma(tester, harness);
      expect(_buscadas(harness).last, _daSala(2));

      await _gravarNaLinha(tester, 2, deNovo: true);
      expect(harness.room.takePasses.last, 3);

      await _chegamTodas(tester, harness);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isTrue);
      expect(_acesa(tester, inTheHome(_irParaATraducao)), isTrue);
      await _tocar(tester, _naLinha(2, _ouvir));
      expect(harness.playback.played.last, isNot(contains(_daSala(2))));
      expect(
        harness.recorder.deleted.where(
          (arquivo) => arquivo.contains(_daSala(2)),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a part the room no longer has turns its row to Gravar, and a recording '
    'there goes above the room pass',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room
        ..refuseClipOf.add(_daSala(2))
        ..holdNextClip();
      await _retomar(
        tester,
        harness,
        naSala: [_naSala(1, pass: 1), _naSala(2, pass: 2), _naSala(3, pass: 1)],
      );
      expect(_naLinha(2, _gravarDeNovo), findsOneWidget);

      await _chegamTodas(tester, harness);
      expect(_naLinha(2, _gravar), findsOneWidget);
      expect(_naLinha(2, _ouvir), findsNothing);

      await _gravarNaLinha(tester, 2);
      expect(harness.room.takePasses.last, 3);
    },
  );

  testWidgets(
    'an app closed while the parts come down fetches them again on the next '
    'opening, and loses none',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.holdNextClip();
      final primeira = await _retomar(tester, harness, cenas: _quatroCenas);
      await _chegaUma(tester, harness);
      await _gravarNaLinha(tester, 4);

      await tester.pumpWidget(const SizedBox());
      primeira.dispose();
      await tester.runAsync(() async => harness.room.finishHeldClip());
      await _passos(tester);
      final antes = _buscadas(harness).length;

      await _abrir(tester, harness);
      await _passos(tester, 8);

      for (var n = 1; n <= 4; n++) {
        expect(_naLinha(n, _gravarDeNovo), findsOneWidget);
        expect(_acesa(tester, _naLinha(n, _ouvir)), isTrue);
      }
      final novas = _buscadas(harness).skip(antes).toList();
      expect(novas, isNot(contains(_daSala(1))));
      expect(novas, containsAll([_daSala(2), _daSala(3)]));
    },
  );

  testWidgets('leaving the passage stops the fetching', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.room.holdNextClip();
    final container = await _retomar(tester, harness);

    await tester.runAsync(
      container.read(salaSessionProvider.notifier).abrirEscolha,
    );
    await _passos(tester);
    final linha = harness.emAberto.rows[_linhaDoTablet];
    await _chegamTodas(tester, harness);

    expect(_buscadas(harness), [_daSala(1)]);
    expect(identical(harness.emAberto.rows[_linhaDoTablet], linha), isTrue);
  });

  testWidgets(
    'a part the room no longer has keeps its row dark until the session read '
    'answers, and its listen fetches nothing',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room
        ..refuseClipOf.add(_daSala(2))
        ..holdNextState();
      final container = await _retomar(tester, harness, aLeituraFicaNoAr: true);
      await _passos(tester, 8);

      expect(_buscadas(harness), [_daSala(1), _daSala(2), _daSala(3)]);
      expect(_naLinha(2, _gravarDeNovo), findsOneWidget);
      expect(_acesa(tester, _naLinha(2, _ouvir)), isFalse);
      container.read(salaSessionProvider.notifier).ouvirACena(2);
      await _passos(tester);
      expect(_buscadas(harness), hasLength(3));
      expect(harness.playback.played, isEmpty);

      await tester.runAsync(() async => harness.room.finishHeldState());
      await _passos(tester, 6);
      expect(_naLinha(2, _gravar), findsOneWidget);
    },
  );
}
