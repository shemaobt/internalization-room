import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'the_translation_is_recorded_over_until_the_check_test.dart'
    show cabeca, confirmar, gravarATraducao, parte, tesoura, tocar;

const _cenasEmPortugues = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
  Scene(sceneId: 'S4', title: 'A chegada a Belém'),
];

const _scenesInEnglish = [
  Scene(sceneId: 'S1', title: 'Famine in Bethlehem'),
  Scene(sceneId: 'S2', title: 'Naomi decides to return'),
  Scene(sceneId: 'S3', title: 'Ruth clings to Naomi'),
  Scene(sceneId: 'S4', title: 'Arrival in Bethlehem'),
];

const _titulo = 'Gravem o ensaio de vocês';
const _ensaioFinal = 'Ensaio Final';
const _subLinha = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _todasAsPartes = 'gravem todas as partes primeiro';
const _gravar = 'Gravar';
const _ouvir = 'Ouvir';
const _gravarDeNovo = 'Gravar de novo';
const _parar = 'Parar';
const _confirmar = 'Confirmar esta parte';
const _irParaATraducao = 'Ir para a tradução';

const _sessao = 'sessao-antiga';

/// An iPad held upright, the room's own screen.
void _umIpadEmPe(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _naCasaDoEnsaio(
  WidgetTester tester, {
  List<Scene> cenas = _cenasEmPortugues,
  SalaHarness? harness,
}) async {
  _umIpadEmPe(tester);
  final sala = harness ?? SalaHarness(filaEmMemoria: true);
  sala.room.passageScenes = cenas;
  final container = await pumpSala(tester, sala);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

String _cena(int n, {List<Scene> cenas = _cenasEmPortugues}) =>
    'Cena $n — ${cenas[n - 1].title}';

Finder _linha(int n, {List<Scene> cenas = _cenasEmPortugues}) =>
    byLabel(_cena(n, cenas: cenas));

Finder _naLinha(int n, String controle) =>
    find.descendant(of: _linha(n), matching: byLabel(controle));

Future<void> _tocar(WidgetTester tester, Finder alvo) async {
  await tester.ensureVisible(alvo);
  await tester.tap(alvo);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _confirmarAParte(WidgetTester tester) async {
  await _tocar(tester, byLabel(_confirmar));
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _gravarNaLinha(
  WidgetTester tester,
  int n, {
  bool deNovo = false,
}) async {
  await _tocar(tester, _naLinha(n, deNovo ? _gravarDeNovo : _gravar));
  await _tocar(tester, _naLinha(n, _parar));
  await _confirmarAParte(tester);
}

bool _discoAceso(WidgetTester tester) =>
    tester.widget<Semantics>(byLabel(_irParaATraducao)).properties.enabled ==
        true &&
    tester
            .widget<AnimatedOpacity>(
              find
                  .descendant(
                    of: byLabel(_irParaATraducao),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity ==
        1.0;

List<PendingTake> _naFila(SalaHarness harness) =>
    (harness.takes as FakeTakeQueue).rows;

Finder get _circulo => find.descendant(
  of: find.byType(EnsaioView),
  matching: find.byType(FacilitatorCircle),
);

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

KeptTake _aParte(ProviderContainer container, int n) => _estado(
  container,
).partes.singleWhere((take) => take.scopeId == KeptScope.parte(n));

/// A passage reopened in the Rehearsal on a tablet that holds [arquivos], from a row
/// naming the parts [numeros]; the room's own listing is [naSala].
Future<ProviderContainer> _retomarNoEnsaio(
  WidgetTester tester, {
  required List<int> numeros,
  bool arquivosNoTablet = true,
  List<TakeView> naSala = const [],
  List<Scene> cenas = _cenasEmPortugues,
  SalaHarness? harness,
  void Function(SalaHarness)? antes,
}) async {
  _umIpadEmPe(tester);
  final casa = Directory.systemTemp.createTempSync('sala-1406-retomada');
  addTearDown(() => casa.deleteSync(recursive: true));
  harness ??= SalaHarness(filaEmMemoria: true);
  harness
    ..room.passageScenes = cenas
    ..room.takes.addAll(naSala);
  antes?.call(harness);
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: _sessao,
    stage: SalaStage.ensaio,
    takes: [
      for (final n in numeros)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: arquivosNoTablet
              ? (File('${casa.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path
              : '${casa.path}/p$n.m4a',
          takeId: 'gravacao-$n',
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
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(
    _estado(container).stage,
    SalaStage.ensaio,
    reason: 'o caso precisa reabrir dentro do Ensaio',
  );
  return container;
}

void main() {
  testWidgets(
    'a passage of four scenes shows four rows, Cena 1 to Cena 4, each with '
    'its title',
    (tester) async {
      await _naCasaDoEnsaio(tester);

      for (var n = 1; n <= 4; n++) {
        expect(find.text('Cena $n'), findsOneWidget);
        expect(find.text(_cenasEmPortugues[n - 1].title), findsOneWidget);
        expect(_linha(n), findsOneWidget);
      }
      expect(find.text('Cena 5'), findsNothing);
    },
  );

  testWidgets(
    'two scenes of four recorded keep the main button closed and ask for '
    'every part',
    (tester) async {
      final container = await _naCasaDoEnsaio(tester);

      await _gravarNaLinha(tester, 1);
      await _gravarNaLinha(tester, 2);

      expect(_discoAceso(tester), isFalse);
      expect(find.text(_todasAsPartes), findsOneWidget);
      await _tocar(tester, byLabel(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.ensaio);
      container.read(salaSessionProvider.notifier).startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _estado(container).stage,
        SalaStage.ensaio,
        reason: 'o portão é da sala, não só do desenho do disco',
      );
    },
  );

  testWidgets('with every scene recorded the main button opens', (
    tester,
  ) async {
    final container = await _naCasaDoEnsaio(tester);

    for (var n = 1; n <= 4; n++) {
      await _gravarNaLinha(tester, n);
    }

    expect(_discoAceso(tester), isTrue);
    expect(find.text(_todasAsPartes), findsNothing);
    await _tocar(tester, byLabel(_irParaATraducao));
    expect(_estado(container).stage, SalaStage.retro);
    closeTheRoom(container);
  });

  testWidgets(
    'recording again on Cena 3 keeps the new take as scene 3 and leaves the '
    'others alone',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      for (var n = 1; n <= 4; n++) {
        await _gravarNaLinha(tester, n);
      }
      final antes = {
        for (final n in [1, 2, 4])
          n: (
            _aParte(container, n).path,
            _aParte(container, n).takeId,
            _aParte(container, n).pass,
          ),
      };

      await _gravarNaLinha(tester, 3, deNovo: true);

      final enviada = _naFila(harness).last;
      expect(
        (enviada.scope, enviada.chunkIndex, enviada.passNumber),
        (KeptScope.parte(3), 3, 2),
      );
      expect(_aParte(container, 3).path, enviada.path);
      expect({
        for (final n in [1, 2, 4])
          n: (
            _aParte(container, n).path,
            _aParte(container, n).takeId,
            _aParte(container, n).pass,
          ),
      }, antes);
    },
  );

  testWidgets('a recording made from a row belongs to that scene', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _naCasaDoEnsaio(tester, harness: harness);

    await _gravarNaLinha(tester, 2);

    final enviada = _naFila(harness).single;
    expect((enviada.scope, enviada.chunkIndex), (KeptScope.parte(2), 2));
    expect(_naLinha(1, _gravar), findsOneWidget);
    expect(_naLinha(2, _gravar), findsNothing);
    expect(_naLinha(2, _ouvir), findsOneWidget);
    expect(_naLinha(2, _gravarDeNovo), findsOneWidget);
  });

  testWidgets(
    'a Portuguese session shows the Portuguese titles under Cena N in a '
    'Portuguese room',
    (tester) async {
      await _naCasaDoEnsaio(tester);

      expect(find.text(_titulo), findsOneWidget);
      for (var n = 1; n <= 4; n++) {
        expect(find.text('Cena $n'), findsOneWidget);
        expect(find.text(_cenasEmPortugues[n - 1].title), findsOneWidget);
      }
    },
  );

  testWidgets(
    'an English session shows the map\'s English titles under Scene N in an '
    'English room',
    (tester) async {
      await _naCasaDoEnsaio(
        tester,
        cenas: _scenesInEnglish,
        harness: SalaHarness(filaEmMemoria: true, lingua: 'en'),
      );
      expect(find.text('Record your rehearsal'), findsOneWidget);
      for (var n = 1; n <= 4; n++) {
        expect(find.text('Scene $n'), findsOneWidget);
        expect(find.text(_scenesInEnglish[n - 1].title), findsOneWidget);
      }
    },
  );

  testWidgets(
    'after a join the title reads Ensaio Final: a part the room holds names '
    'the scene rehearsal it was joined from',
    (tester) async {
      await _retomarNoEnsaio(
        tester,
        numeros: [1],
        arquivosNoTablet: false,
        naSala: const [
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
            origin: 'ensaio-da-cena-1',
          ),
        ],
      );

      expect(find.text(_ensaioFinal), findsOneWidget);
      expect(find.text(_titulo), findsNothing);
    },
  );

  testWidgets(
    'a recording the room holds with no join keeps the title Gravem o ensaio '
    'de vocês',
    (tester) async {
      await _retomarNoEnsaio(
        tester,
        numeros: [1],
        arquivosNoTablet: false,
        naSala: const [
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
        ],
      );

      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_ensaioFinal), findsNothing);
    },
  );

  testWidgets(
    'a part joined and then recorded again by the team is no longer a joined '
    'recording',
    (tester) async {
      await _retomarNoEnsaio(
        tester,
        numeros: [1],
        arquivosNoTablet: false,
        naSala: const [
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
            pass: 1,
            origin: 'ensaio-da-cena-1',
          ),
          TakeView(
            takeId: 'gravacao-1b',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
            pass: 2,
          ),
        ],
      );

      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_ensaioFinal), findsNothing);
    },
  );

  test('the app reads where a joined part came from', () {
    final takes = TakeView.listFrom({
      'takes': [
        {
          'take_id': 'g-1',
          'kind': 'ensaio',
          'scope': 'parte-1',
          'ordinal': 1,
          'origin': 'ensaio-da-cena-1',
        },
        {'take_id': 'g-2', 'kind': 'ensaio', 'scope': 'parte-2', 'ordinal': 2},
      ],
    });

    expect([for (final take in takes) take.origin], ['ensaio-da-cena-1', null]);
  });

  test(
    'a Resume point written with a joined part reads its origin back',
    () async {
      final casa = Directory.systemTemp.createTempSync('sala-1406-linha');
      addTearDown(() => casa.deleteSync(recursive: true));
      WorkInProgress noDisco() =>
          WorkInProgress(home: () async => casa, recordings: () async => casa);

      await noDisco().remember(
        'Ruth',
        'P01',
        'pt',
        ResumePoint(
          sessionId: _sessao,
          stage: SalaStage.ensaio,
          takes: [
            KeptTake(
              scopeId: KeptScope.parte(1),
              path: '${casa.path}/p1.m4a',
              takeId: 'gravacao-1',
              origin: 'ensaio-da-cena-1',
            ),
            KeptTake(
              scopeId: KeptScope.parte(2),
              path: '${casa.path}/p2.m4a',
              takeId: 'gravacao-2',
            ),
          ],
        ),
      );

      final lida = await noDisco().of('Ruth', 'P01', 'pt');
      expect(
        [for (final take in lida!.takes) take.origin],
        ['ensaio-da-cena-1', null],
      );
    },
  );

  testWidgets('three parts kept before the rows existed show on rows 1 to 3', (
    tester,
  ) async {
    await _retomarNoEnsaio(tester, numeros: [1, 2, 3]);

    for (var n = 1; n <= 3; n++) {
      expect(_naLinha(n, _ouvir), findsOneWidget);
      expect(_naLinha(n, _gravarDeNovo), findsOneWidget);
    }
    expect(_naLinha(4, _gravar), findsOneWidget);
    expect(_discoAceso(tester), isFalse);
    expect(find.text(_todasAsPartes), findsOneWidget);
  });

  testWidgets('a room holding only part 3 brings it back on row 3, not row 1', (
    tester,
  ) async {
    await _retomarNoEnsaio(
      tester,
      numeros: [3],
      arquivosNoTablet: false,
      naSala: const [
        TakeView(
          takeId: 'gravacao-3',
          kind: 'ensaio',
          scope: 'parte-3',
          ordinal: 3,
        ),
      ],
    );

    expect(_naLinha(3, _ouvir), findsOneWidget);
    expect(_naLinha(1, _gravar), findsOneWidget);
    expect(_naLinha(2, _gravar), findsOneWidget);
  });

  testWidgets('the title and the sub-line are hers', (tester) async {
    await _naCasaDoEnsaio(tester);

    expect(find.text(_titulo), findsOneWidget);
    expect(find.text(_subLinha), findsOneWidget);
    expect(find.text(_todasAsPartes), findsNothing);
  });

  testWidgets('the rows say cena and the Back-translation still says parte', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    harness.playback
      ..measured = parte
      ..length = parte;
    final container = await _naCasaDoEnsaio(
      tester,
      cenas: _cenasEmPortugues.take(2).toList(),
      harness: harness,
    );
    await _gravarNaLinha(tester, 1);
    await _gravarNaLinha(tester, 2);
    expect(
      find.descendant(
        of: find.byType(EnsaioView),
        matching: find.textContaining(RegExp('[Pp]arte ')),
      ),
      findsNothing,
    );

    await theRoomNamesTheParts(tester, container, parts: 2);
    await _tocar(tester, byLabel(_irParaATraducao));
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester, harness);
    await tocar(tester, confirmar);
    await waitFor(
      'a frase traduzida entrar na lista',
      () => _estado(container).btTrechos.any((trecho) => trecho.contado),
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(
      find.descendant(
        of: find.byType(FraseList),
        matching: find.text('parte 1'),
      ),
      findsWidgets,
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the rehearsal so far plays the parts in scene order, whatever order they '
    'were recorded in',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      await _gravarNaLinha(tester, 3);
      await _gravarNaLinha(tester, 1);
      final antes = harness.playback.played.length;

      await _tocar(tester, byLabel('Ouvir o ensaio até aqui'));
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));

      expect(harness.playback.played.sublist(antes), [
        _aParte(container, 1).path,
        _aParte(container, 3).path,
      ]);
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('listen on a row plays that scene\'s part alone', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naCasaDoEnsaio(tester, harness: harness);
    await _gravarNaLinha(tester, 1);
    await _gravarNaLinha(tester, 2);
    final antes = harness.playback.played.length;

    await _tocar(tester, _naLinha(2, _ouvir));

    expect(harness.playback.played.sublist(antes), [
      _aParte(container, 2).path,
    ]);
  });

  testWidgets(
    'while the scene list has not answered, translation stays closed',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.failScenesWith = const NetworkFailed('sem rede');
      final container = await _naCasaDoEnsaio(tester, harness: harness);

      await _tocar(tester, _circulo);
      await _tocar(tester, _circulo);
      await _confirmarAParte(tester);
      expect(_estado(container).partes, hasLength(1));
      expect(_discoAceso(tester), isFalse);
      container.read(salaSessionProvider.notifier).startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_estado(container).stage, SalaStage.ensaio);

      harness.room.failScenesWith = null;
      await tester.pump(const Duration(seconds: 3));
      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
    },
  );

  testWidgets(
    'a scene list still missing after its retries is asked again when the '
    'team keeps a part',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.failScenesWith = const NetworkFailed('sem rede');
      await _naCasaDoEnsaio(tester, harness: harness);
      await tester.pump(const Duration(seconds: 12));

      await _tocar(tester, _circulo);
      harness.room.failScenesWith = null;
      await _tocar(tester, _circulo);
      await _confirmarAParte(tester);

      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
    },
  );

  testWidgets(
    'with the scene list missing, the circle never records past the parts the '
    'room holds',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _retomarNoEnsaio(
        tester,
        numeros: [1, 2, 3, 4],
        harness: harness,
        antes: (harness) =>
            harness.room.failScenesWith = const NetworkFailed('sem rede'),
      );
      await tester.pump(const Duration(seconds: 12));

      await _tocar(tester, _circulo);
      await _tocar(tester, _circulo);
      await _confirmarAParte(tester);

      expect([
        for (final linha in _naFila(harness)) linha.scope,
      ], isNot(contains(KeptScope.parte(5))));
      expect(harness.recorder.captures, 0);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'with the scene list still on its way, the circle never records past the '
    'parts the room holds',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      await _retomarNoEnsaio(
        tester,
        numeros: [1, 2, 3, 4],
        harness: harness,
        antes: (harness) => harness.room.holdNextScenes(),
      );

      await _tocar(tester, _circulo);
      await _tocar(tester, _circulo);
      await _confirmarAParte(tester);

      expect([
        for (final linha in _naFila(harness)) linha.scope,
      ], isNot(contains(KeptScope.parte(5))));
      expect(harness.recorder.captures, 0);
    },
  );

  testWidgets(
    'a tap on the circle asks again for a scene list that ran out of retries',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _retomarNoEnsaio(
        tester,
        numeros: [1, 2, 3, 4],
        harness: harness,
        antes: (harness) =>
            harness.room.failScenesWith = const NetworkFailed('sem rede'),
      );
      await tester.pump(const Duration(seconds: 12));
      harness.room.failScenesWith = null;

      await _tocar(tester, _circulo);
      await tester.pump(const Duration(milliseconds: 400));

      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
      expect(_discoAceso(tester), isTrue);
      await _tocar(tester, byLabel(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets('with every scene recorded a tap on the circle records nothing', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naCasaDoEnsaio(tester, harness: harness);
    for (var n = 1; n <= 4; n++) {
      await _gravarNaLinha(tester, n);
    }
    final gravacoes = harness.recorder.captures;

    await _tocar(tester, _circulo);

    expect(_estado(container).ensaio, EnsaioStatus.idle);
    expect(harness.recorder.captures, gravacoes);
  });

  testWidgets(
    'a part beyond the last scene has no row and is still kept and played',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _retomarNoEnsaio(
        tester,
        numeros: [1, 2, 3, 4, 5],
        harness: harness,
      );

      expect(find.text('Cena 5'), findsNothing);
      for (var n = 1; n <= 4; n++) {
        expect(_naLinha(n, _ouvir), findsOneWidget);
      }
      final quinta = _aParte(container, 5).path;
      await _tocar(tester, byLabel('Ouvir o ensaio até aqui'));
      for (var parte = 0; parte < 4; parte++) {
        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(harness.playback.played.last, quinta);
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_discoAceso(tester), isTrue);
      await _tocar(tester, byLabel(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a whole rehearsal the room holds with no number is no scene\'s part',
    (tester) async {
      await _retomarNoEnsaio(
        tester,
        numeros: [1],
        arquivosNoTablet: false,
        naSala: const [
          TakeView(
            takeId: 'gravacao-inteira',
            kind: 'ensaio',
            scope: KeptScope.whole,
          ),
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
        ],
      );

      expect(_naLinha(1, _ouvir), findsOneWidget);
      for (var n = 2; n <= 4; n++) {
        expect(_naLinha(n, _gravar), findsOneWidget);
      }
      expect(_discoAceso(tester), isFalse);
    },
  );

  testWidgets(
    'a Rehearsal reached with the room down already knows the passage\'s '
    'scenes and records more than one part',
    (tester) async {
      _umIpadEmPe(tester);
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passageScenes = _cenasEmPortugues;
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 200));
      harness.network.reachable = false;
      harness.room.reachable = false;
      notifier.goEnsaio();
      await tester.pump(const Duration(milliseconds: 400));

      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
      await _tocar(tester, _naLinha(1, _gravar));
      await _tocar(tester, _naLinha(1, _parar));
      await _tocar(tester, byLabel(_confirmar));
      await _tocar(tester, _naLinha(2, _gravar));
      await _tocar(tester, _naLinha(2, _parar));
      await _tocar(tester, byLabel(_confirmar));

      expect(
        [for (final take in _estado(container).partes) take.scopeId],
        [KeptScope.parte(1), KeptScope.parte(2)],
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the circle records the first scene that has no part', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    await _naCasaDoEnsaio(tester, harness: harness);
    await _gravarNaLinha(tester, 1);
    await _gravarNaLinha(tester, 3);

    await _tocar(tester, _circulo);
    await _tocar(tester, _circulo);
    await _confirmarAParte(tester);

    final enviada = _naFila(harness).last;
    expect((enviada.scope, enviada.chunkIndex), (KeptScope.parte(2), 2));
  });

  testWidgets(
    'a scene list from an earlier passage never draws this passage\'s rows',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(
        tester,
        cenas: _cenasEmPortugues.take(3).toList(),
        harness: harness,
      );
      expect(_linha(3), findsOneWidget);
      final notifier = container.read(salaSessionProvider.notifier);
      notifier.leaveThePassage();
      await tester.pump(const Duration(seconds: 2));

      harness.room.passageScenes = _cenasEmPortugues;
      await notifier.goConversa(book: 'Ruth', pericope: 'P02');
      await tester.pump(const Duration(milliseconds: 200));
      notifier.goEnsaio();
      await tester.pump(const Duration(milliseconds: 400));

      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
    },
  );

  test(
    'a passage left in its translation reopens there with scenes still missing '
    'their part',
    () async {
      final casa = Directory.systemTemp.createTempSync('sala-1406-na-traducao');
      addTearDown(() => casa.deleteSync(recursive: true));
      final harness = SalaHarness()
        ..room.passageScenes = _cenasEmPortugues
        ..room.retroSoFar = const BackTranslationProgress(
          segments: [
            SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-1',
              startsMs: 0,
              endsMs: 4000,
            ),
          ],
        )
        ..playback.measured = const Duration(seconds: 10);
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: _sessao,
        stage: SalaStage.retro,
        takes: [
          for (final n in [1, 2])
            KeptTake(
              scopeId: KeptScope.parte(n),
              path: (File(
                '${casa.path}/p$n.m4a',
              )..writeAsBytesSync([1, 2, 3])).path,
              takeId: 'gravacao-$n',
            ),
        ],
      );
      final container = harness.container();
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      await sala.abrirEscolha();
      await settle();
      unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));

      await waitFor(
        'a equipe voltar à tradução',
        () => container.read(salaSessionProvider).stage == SalaStage.retro,
      );
    },
  );
}
