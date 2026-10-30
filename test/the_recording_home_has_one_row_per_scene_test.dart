import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart' show tocarNoCirculo;
import 'um_ensaio_de_tres_partes.dart' show Sala;
import 'the_translation_is_recorded_over_until_the_check_test.dart'
    show cabeca, gravarATraducao, parte;

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
const _enviarAGravacao = 'Enviar a gravação';
const _irParaATraducao = 'Traduzir a gravação';
const _gravarAPassagemInteira = 'Gravar a passagem inteira';

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
  await _tocar(tester, offTheRows(_enviarAGravacao));
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

Future<(SalaHarness, ProviderContainer)> _comAParte1NoAr(
  WidgetTester tester,
) async {
  final harness = SalaHarness()..room.holdNextTake(KeptScope.parte(1));
  final container = await _naCasaDoEnsaio(tester, harness: harness);
  await tester.pump(const Duration(seconds: 1));
  var chegou = false;
  unawaited(harness.room.untilTakeHeld().then((_) => chegou = true));
  await _gravarNaLinha(tester, 1);
  await waitFor(
    'a gravação chegar à porta',
    () => chegou,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  return (harness, container);
}

bool _discoAceso(WidgetTester tester) =>
    tester.widget<Semantics>(inTheHome(_irParaATraducao)).properties.enabled ==
        true &&
    tester
            .widget<AnimatedOpacity>(
              find
                  .descendant(
                    of: inTheHome(_irParaATraducao),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity ==
        1.0;

List<PendingTake> _naFila(SalaHarness harness) =>
    (harness.takes as FakeTakeQueue).rows;

const _duasCenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
];

const _oInteiro = TakeView(
  takeId: 'gravacao-inteira',
  kind: 'ensaio',
  scope: KeptScope.whole,
);

/// A passage reopened on a tablet that no longer holds its recordings, the orange dot
/// laying in what the room lists.
Future<void> _naCasaPelaBolinha(Sala it) async {
  await it.sala.openTheRoom();
  await waitFor(
    'a sala pousar na conversa',
    () => it.estado.station is Canvas && !it.estado.awaitingTheGuide,
  );
  it.sala.openTheEnsaioFinal();
  await waitFor(
    'as partes da sala chegarem à casa',
    () => it.estado.station == const Ensaio(),
  );
  await settle();
}

/// A two-scene passage left in its telling-back, reopened on a tablet that no longer holds
/// the recordings the room lists in [naSala], with [contados] told over them, at the
/// recording home the orange dot opens.
Future<Sala> _naCasaSemAsGravacoes({
  required List<TakeView> naSala,
  required List<SegmentView> contados,
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-1406-inteiro');
  addTearDown(() => casa.deleteSync(recursive: true));
  final harness = SalaHarness()
    ..playback.measured = const Duration(seconds: 10);
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: _sessao,
      stage: SalaStage.retro,
      takes: [
        for (final take in naSala)
          KeptTake(
            scopeId: switch (take.ordinal) {
              final n? => KeptScope.parte(n),
              null => KeptScope.whole,
            },
            path: '${casa.path}/${take.takeId}.m4a',
            takeId: take.takeId,
          ),
      ],
    ),
  );
  harness.room
    ..passageScenes = _duasCenas
    ..retroSoFar = BackTranslationProgress(segments: contados)
    ..takes.addAll(naSala);
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await _naCasaPelaBolinha(it);
  return it;
}

/// The same, then into its telling-back.
Future<Sala> _reabrirNaTraducao({
  required List<TakeView> naSala,
  required List<SegmentView> contados,
}) async {
  final it = await _naCasaSemAsGravacoes(naSala: naSala, contados: contados);
  it.sala.startRetro();
  await waitFor(
    'a tradução abrir tocando',
    () => it.estado.station is Retro && it.harness.playback.played.isNotEmpty,
  );
  return it;
}

/// Play the telling-back to its end and let the room answer «terminei» with a finding
/// on [segmento].
Future<void> _umAchadoEm(Sala it, String segmento) async {
  for (var vez = 0; vez < 6 && !it.estado.canFinishBackTranslation; vez++) {
    it.harness.playback.finishPlayback();
    await settle();
    if (it.estado.btParteFronteira) it.sala.ouvirGravacao();
    await settle();
  }
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingSegmentId = segmento;
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala responder',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

Future<void> _gravarACenaEGuardar(Sala it, int cena) async {
  it.sala.gravarACena(cena);
  await waitFor(
    'a cena $cena gravar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.gravarACena(cena);
  await waitFor(
    'a cena $cena ficar pendente',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  it.sala.takeKeep();
  await waitFor(
    'a cena $cena ficar guardada',
    () => it.estado.ensaio == EnsaioStatus.idle,
  );
}

const _achadoNoInteiro = BtFinding(
  kind: BtFindingKind.missing,
  frase: 1,
  segmentId: 'trecho-inteiro',
);

const _contadoNoInteiro = SegmentView(
  segmentId: 'trecho-inteiro',
  takeId: 'gravacao-inteira',
  startsMs: 0,
  endsMs: 10000,
  frase: 1,
);

/// A two-scene passage reopened on the tablet that recorded it, in its Rehearsal, holding
/// the whole rehearsal and, when [comACena1], scene 1's part not yet named by the room.
Future<Sala> _reabrirComOInteiro({
  required bool comACena1,
  List<BtFinding> achados = const [_achadoNoInteiro],
}) async {
  final casa = Directory.systemTemp.createTempSync('sala-1406-achado');
  addTearDown(() => casa.deleteSync(recursive: true));
  final harness = SalaHarness()
    ..playback.measured = const Duration(seconds: 10);
  final row = ResumePoint(
    sessionId: _sessao,
    stage: SalaStage.ensaio,
    takes: [
      KeptTake(
        scopeId: KeptScope.whole,
        path: (File(
          '${casa.path}/inteiro.m4a',
        )..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-inteira',
      ),
      if (comACena1)
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        ),
    ],
  );
  await holdTheSession(harness, row);
  harness.room
    ..passageScenes = _duasCenas
    ..retroSoFar = BackTranslationProgress(
      segments: const [_contadoNoInteiro],
      findings: achados,
    )
    ..takes.add(_oInteiro);
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
  await settle();
  return it;
}

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
  final row = ResumePoint(
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
  await holdTheSession(harness, row);
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  if (arquivosNoTablet) {
    await intoTheRecordingHome(
      notifier,
      () => _estado(container),
      step: () => letTheRehearsalReachTheRoom(tester),
    );
  } else {
    await waitFor(
      'a sala pousar na conversa',
      () =>
          _estado(container).station is Canvas &&
          !_estado(container).awaitingTheGuide,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    notifier.openTheEnsaioFinal();
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(
    _estado(container).station,
    const Ensaio(),
    reason: 'o caso precisa reabrir na casa do Ensaio',
  );
  return container;
}

bool _ouvirTudo() => find.text('Ouvir tudo').evaluate().isNotEmpty;

/// Scenes 1 to 3 kept and named by the room, and scene 4 recorded and kept with its copy
/// onto the tablet held and its upload held at the room's door.
Future<(SalaHarness, ProviderContainer)> _aQuartaGuardadaDevagar(
  WidgetTester tester,
) async {
  final harness = SalaHarness(filaEmMemoria: true);
  final container = await _naCasaDoEnsaio(tester, harness: harness);
  for (final n in [1, 2, 3]) {
    await _gravarNaLinha(tester, n);
  }
  await theRoomNamesTheParts(tester, container, parts: 3);
  (harness.takes as FakeTakeQueue).holdNextKeep();
  harness.room.holdNextTake(KeptScope.parte(4));
  await _gravarNaLinha(tester, 4);
  return (harness, container);
}

Future<void> _aQuartaChegaAPorta(
  WidgetTester tester,
  SalaHarness harness,
) async {
  (harness.takes as FakeTakeQueue).finishHeldKeep();
  await waitFor(
    'a cena 4 chegar à porta da sala',
    () => harness.room.takeHeld,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
}

Future<void> _aQuartaChegaASala(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  harness.room.finishHeldTake();
  await theRoomNamesTheParts(tester, container, parts: 4);
  await letTheRehearsalReachTheRoom(tester);
}

Future<void> _oToqueNoDiscoFicaNaCasa(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _tocar(tester, inTheHome(_irParaATraducao));
  expect(_estado(container).stage, SalaStage.ensaio);
  container.read(salaSessionProvider.notifier).startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  expect(_estado(container).stage, SalaStage.ensaio);
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
      await _tocar(tester, inTheHome(_irParaATraducao));
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
    await _tocar(tester, inTheHome(_irParaATraducao));
    expect(_estado(container).stage, SalaStage.retro);
    closeTheRoom(container);
  });

  testWidgets('«Ouvir tudo» shows her title and ends with «fim da gravação»', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naCasaDoEnsaio(tester, harness: harness);
    expect(find.text('Ouvir tudo'), findsNothing);
    for (var n = 1; n <= 4; n++) {
      await _gravarNaLinha(tester, n);
    }

    await _tocar(tester, find.text('Ouvir tudo'));

    expect(
      find.text('A gravação de vocês inteira, parte por parte.'),
      findsOneWidget,
    );
    expect(find.text('fim da gravação'), findsNothing);
    expect(find.text('Ouvir tudo'), findsNothing);
    for (var n = 0; n < 4; n++) {
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('fim da gravação'), findsOneWidget);
    await tester.tap(find.text('fim da gravação'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_estado(container).ouvirTudo, OuvirTudo.fora);
    expect(find.text('Ouvir tudo'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('a VoiceOver double-tap on «Ouvir a gravação inteira» opens '
      '«Ouvir tudo», as a finger does', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naCasaDoEnsaio(tester, harness: harness);
    for (var n = 1; n <= 4; n++) {
      await _gravarNaLinha(tester, n);
    }

    voiceOverTap(tester, 'Ouvir a gravação inteira');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('A gravação de vocês inteira, parte por parte.'),
      findsOneWidget,
      reason: 'o VoiceOver anunciava o botão e o toque duplo não abria nada',
    );
    closeTheRoom(container);
    semantics.dispose();
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
    await _tocar(tester, inTheHome(_irParaATraducao));
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester, harness);
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

      await _tocar(tester, offTheRows(_ouvir));
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

  testWidgets(
    'a recording waiting for the check sounds at its scene\'s place, with no '
    'row drawn selected while it plays',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      for (final n in [1, 3, 4]) {
        await _gravarNaLinha(tester, n);
      }
      await _tocar(tester, _naLinha(2, _gravar));
      await _tocar(tester, _naLinha(2, _parar));
      final pendente = harness.recorder.lastPath!;
      final antes = harness.playback.played.length;

      await _tocar(tester, offTheRows(_ouvir));
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        tester
            .widget<Semantics>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    (widget.properties.label ?? '').startsWith(_cena(2)),
              ),
            )
            .properties
            .selected,
        isNot(isTrue),
        reason:
            'a gravação da cena 2 soa, e nenhuma linha se acende, como na dela',
      );
      for (var vez = 0; vez < 3; vez++) {
        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(harness.playback.played.sublist(antes), [
        _aParte(container, 1).path,
        pendente,
        _aParte(container, 3).path,
        _aParte(container, 4).path,
      ]);
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
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _retomarNoEnsaio(
        tester,
        numeros: [1],
        harness: harness,
        antes: (harness) =>
            harness.room.failScenesWith = const NetworkFailed('sem rede'),
      );
      final notifier = container.read(salaSessionProvider.notifier);

      expect(_estado(container).partes, hasLength(1));
      expect(_discoAceso(tester), isFalse);
      notifier.startRetro();
      await tester.pump(const Duration(milliseconds: 200));
      expect(_estado(container).stage, SalaStage.ensaio);

      harness.room.failScenesWith = null;
      notifier.goEnsaio();
      await tester.pump(const Duration(seconds: 1));
      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
    },
  );
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
      await _tocar(tester, offTheRows(_ouvir));
      for (var parte = 0; parte < 4; parte++) {
        harness.playback.finishPlayback();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(harness.playback.played.last, quinta);
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 200));

      expect(_discoAceso(tester), isTrue);
      await _tocar(tester, inTheHome(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a whole rehearsal the room holds with no number is no scene\'s part',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      await _retomarNoEnsaio(
        tester,
        harness: harness,
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
      await _tocar(tester, _naLinha(1, _ouvir));
      expect(harness.playback.played.last, contains('gravacao-1'));
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
      harness.room.reachable = false;
      notifier.goEnsaio();
      await tester.pump(const Duration(milliseconds: 400));

      for (var n = 1; n <= 4; n++) {
        expect(_linha(n), findsOneWidget);
      }
      await _tocar(tester, _naLinha(1, _gravar));
      await _tocar(tester, _naLinha(1, _parar));
      await _tocar(tester, offTheRows(_enviarAGravacao));
      await _tocar(tester, _naLinha(2, _gravar));
      await _tocar(tester, _naLinha(2, _parar));
      await _tocar(tester, offTheRows(_enviarAGravacao));

      expect(
        [for (final take in _estado(container).partes) take.scopeId],
        [KeptScope.parte(1), KeptScope.parte(2)],
      );
      closeTheRoom(container);
    },
  );
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
    'a passage left in its translation with scenes still missing their part, '
    'picked on the Choice, lands on its conversation at rest',
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
        'a sala pousar na conversa',
        () =>
            container.read(salaSessionProvider).station is Canvas &&
            !container.read(salaSessionProvider).awaitingTheGuide,
      );
      await settle();

      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    },
  );

  test(
    'a whole rehearsal the room holds with no number, laid in by the orange dot '
    'on a passage left in its telling-back, plays there',
    () async {
      final casa = Directory.systemTemp.createTempSync('sala-1406-inteiro');
      addTearDown(() => casa.deleteSync(recursive: true));
      final harness = SalaHarness()
        ..playback.measured = const Duration(seconds: 10);
      await holdTheSession(
        harness,
        ResumePoint(
          sessionId: _sessao,
          stage: SalaStage.retro,
          takes: [
            KeptTake(
              scopeId: KeptScope.whole,
              path: '${casa.path}/inteiro.m4a',
              takeId: 'gravacao-inteira',
            ),
          ],
        ),
      );
      harness.room
        ..passageScenes = _cenasEmPortugues
        ..retroSoFar = const BackTranslationProgress(
          segments: [
            SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-inteira',
              startsMs: 0,
              endsMs: 4000,
            ),
          ],
        )
        ..takes.add(
          const TakeView(
            takeId: 'gravacao-inteira',
            kind: 'ensaio',
            scope: KeptScope.whole,
          ),
        );
      final container = harness.container();
      addTearDown(container.dispose);
      await _naCasaPelaBolinha(Sala(harness, container));

      container.read(salaSessionProvider.notifier).startRetro();
      await waitFor(
        'o ensaio inteiro tocar na tradução',
        () => harness.playback.played.isNotEmpty,
      );
      final estado = container.read(salaSessionProvider);
      expect(estado.stage, SalaStage.retro);
      expect(estado.needsPerson, isFalse);
    },
  );

  test(
    'a scene list answered when the passage opened outlives a scene rehearsal '
    'whose own ask fails',
    () async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.passageScenes = _cenasEmPortugues;
      final container = harness.container();
      addTearDown(container.dispose);
      SalaSessionState estado() => container.read(salaSessionProvider);
      final sala = container.read(salaSessionProvider.notifier);
      await sala.abrirEscolha();
      await settle();
      unawaited(sala.goConversa(book: 'Ruth'));
      await waitFor('a sala se calar no convite', () {
        final agora = estado();
        return agora.scenes is ScenesHad &&
            agora.station is Canvas &&
            !agora.awaitingTheGuide &&
            agora.machine.inFlight == null;
      });

      harness.room.failScenesWith = const NetworkFailed('sem rede');
      sala.openTheSceneRehearsal();
      await Future<void>.delayed(const Duration(seconds: 3));
      sala.leaveTheSceneRehearsal();
      await settle();
      sala.goEnsaio();
      await settle();

      expect(estado().sceneRows, hasLength(4));
    },
  );

  test(
    'a finding on the whole rehearsal leads to its one row with nothing marked, '
    'and «Gravar cena por cena» to the scene rows, where the circle records '
    'scene 1 and the room holds the whole set aside',
    () async {
      final it = await _reabrirNaTraducao(
        naSala: const [_oInteiro],
        contados: const [
          SegmentView(
            segmentId: 'trecho-inteiro',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 10000,
          ),
        ],
      );
      await _umAchadoEm(it, 'trecho-inteiro');

      it.sala.leaveTheBackTranslation();
      await waitFor(
        'o ensaio abrir',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      expect(it.estado.needsPerson, isFalse);
      await waitFor(
        'a linha guardar o ensaio',
        () =>
            it.harness.emAberto.rows['Ruth/P01/pt']?.stage == SalaStage.ensaio,
      );
      it.sala.recordSceneByScene();
      await waitFor('as cenas', () => it.estado.sceneRows.length == 2);
      expect(it.harness.room.grainSwitches.single.grain, Grain.scene);
      it.sala.gravarACena(1);
      await waitFor(
        'o círculo gravar',
        () => it.estado.ensaio == EnsaioStatus.recording,
      );
      it.sala.gravarACena(1);
      await waitFor(
        'ficar pendente',
        () => it.estado.ensaio == EnsaioStatus.recorded,
      );
      it.sala.takeKeep();
      await waitFor('guardar', () => it.estado.ensaio == EnsaioStatus.idle);

      expect(
        [for (final take in it.partes) take.scopeId],
        [KeptScope.parte(1)],
      );
      expect(
        it.harness.room.takes
            .singleWhere((take) => take.takeId == 'gravacao-inteira')
            .setAside,
        isTrue,
        reason: 'posto de lado, o inteiro fica guardado na sala',
      );
    },
  );

  test(
    'once scene 1 lands, the whole rehearsal leaves the Back-translation',
    () async {
      final it = await _reabrirNaTraducao(
        naSala: const [_oInteiro],
        contados: const [
          SegmentView(
            segmentId: 'trecho-inteiro',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 10000,
          ),
        ],
      );
      await _umAchadoEm(it, 'trecho-inteiro');
      it.sala.leaveTheBackTranslation();
      await waitFor(
        'o ensaio abrir',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      final inteiro = it.estado.keptTakes
          .singleWhere((take) => take.scopeId == KeptScope.whole)
          .path;
      it.sala.recordSceneByScene();
      await waitFor('as cenas', () => it.estado.sceneRows.length == 2);
      await _gravarACenaEGuardar(it, 1);
      await _gravarACenaEGuardar(it, 2);
      await waitFor(
        'a sala nomear as duas cenas',
        () => it.estado.keptTakes.every((take) => take.takeId != null),
      );
      final antes = it.harness.playback.played.length;

      it.sala.startRetro();
      await waitFor(
        'a tradução tocar',
        () => it.harness.playback.played.length > antes,
      );

      expect(it.estado.stage, SalaStage.retro);
      expect(it.estado.btTrechos, isEmpty);
      expect(
        it.harness.playback.played.sublist(antes),
        isNot(contains(inteiro)),
      );
    },
  );

  test(
    'a finding on a whole rehearsal set aside behind its scene parts never loops '
    'back to it',
    () async {
      final it = await _reabrirNaTraducao(
        naSala: const [
          _oInteiro,
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
          TakeView(
            takeId: 'gravacao-2',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        ],
        contados: const [
          SegmentView(
            segmentId: 'trecho-inteiro',
            takeId: 'gravacao-inteira',
            startsMs: 0,
            endsMs: 10000,
          ),
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 10000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 10000,
          ),
        ],
      );
      await _umAchadoEm(it, 'trecho-inteiro');

      it.sala.leaveTheBackTranslation();
      await settle();

      expect(
        [for (final take in it.partes) take.scopeId],
        [KeptScope.parte(1), KeptScope.parte(2)],
      );
      expect(it.estado.needsPerson, isFalse);
      expect(
        it.harness.playback.played.where(
          (path) => path.contains('gravacao-inteira'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'a passage reopened in the Rehearsal brings back no finding on the whole '
    'rehearsal set aside',
    () async {
      final it = await _reabrirComOInteiro(comACena1: true);

      expect(it.estado.btTrechos, isEmpty);
      expect(it.estado.btFindings, isEmpty);
    },
  );

  test(
    'a finding with no address on the whole rehearsal leaves with it when the team '
    'records scene by scene',
    () async {
      final it = await _reabrirComOInteiro(
        comACena1: false,
        achados: const [
          BtFinding(kind: BtFindingKind.missing, frase: null, segmentId: null),
        ],
      );
      expect(it.estado.btFindings, hasLength(1));

      it.sala.recordSceneByScene();
      await waitFor('as cenas', () => it.estado.sceneRows.length == 2);
      await _gravarACenaEGuardar(it, 1);

      expect(it.estado.btFindings, isEmpty);
    },
  );

  test(
    'a resume on another tablet never fetches a whole rehearsal set aside behind '
    'a scene part',
    () async {
      final it = await _naCasaSemAsGravacoes(
        naSala: const [
          _oInteiro,
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
        ],
        contados: const [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 4000,
          ),
        ],
      );

      expect(
        it.harness.room.clipsFetched,
        isNot(
          contains(RoomRepository.takeAudioUrl(_sessao, 'gravacao-inteira')),
        ),
      );
    },
  );

  testWidgets(
    'a finding on a lone whole rehearsal leaves «Gravar cena por cena» on its '
    'home, and its tap leads to the scene rows',
    (tester) async {
      _umIpadEmPe(tester);
      final casa = Directory.systemTemp.createTempSync('sala-1766-achado');
      addTearDown(() => casa.deleteSync(recursive: true));
      final harness = SalaHarness(filaEmMemoria: true)
        ..playback.measured = const Duration(seconds: 10);
      final inteiro = File('${casa.path}/inteiro.m4a')
        ..writeAsBytesSync([1, 2, 3]);
      await holdTheSession(
        harness,
        ResumePoint(
          sessionId: _sessao,
          stage: SalaStage.ensaio,
          takes: [
            KeptTake(
              scopeId: KeptScope.whole,
              path: inteiro.path,
              takeId: 'gravacao-inteira',
            ),
          ],
        ),
      );
      harness.room
        ..passageScenes = _duasCenas
        ..retroSoFar = const BackTranslationProgress(
          segments: [_contadoNoInteiro],
          findings: [_achadoNoInteiro],
        )
        ..takes.add(_oInteiro);
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await intoTheRecordingHome(
        container.read(salaSessionProvider.notifier),
        () => _estado(container),
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_estado(container).stage, SalaStage.ensaio);
      expect(_estado(container).btFindings, hasLength(1));
      expect(find.text('A passagem inteira'), findsOneWidget);

      await _tocar(tester, find.text('Gravar cena por cena'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(harness.room.grainSwitches.single.grain, Grain.scene);
      expect(_linha(1, cenas: _duasCenas), findsOneWidget);
      expect(_linha(2, cenas: _duasCenas), findsOneWidget);
      expect(find.text('A passagem inteira'), findsNothing);
    },
  );

  test(
    'a switch the room does not answer leaves the told stretches as they were',
    () async {
      final it = await _reabrirNaTraducao(
        naSala: const [
          TakeView(
            takeId: 'gravacao-1',
            kind: 'ensaio',
            scope: 'parte-1',
            ordinal: 1,
          ),
          TakeView(
            takeId: 'gravacao-2',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        ],
        contados: const [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 10000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-2',
            startsMs: 0,
            endsMs: 10000,
          ),
        ],
      );
      await _umAchadoEm(it, 'trecho-1');
      it.sala.leaveTheBackTranslation();
      await waitFor(
        'o ensaio abrir',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      final contados = [for (final t in it.estado.btTrechos) t.segmentId];
      expect(contados, isNotEmpty);
      it.harness.room.grainAnswersFirst.add(const NetworkFailed('sem rede'));

      it.sala.recordTheWholePassageInstead();
      await settle(const Duration(milliseconds: 600));

      expect(it.harness.room.grainSwitches, hasLength(1));
      expect(it.estado.sceneRows, hasLength(2));
      expect([for (final t in it.estado.btTrechos) t.segmentId], contados);
    },
  );

  testWidgets(
    'the grain switch stands on a home whose scene list never answered',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.failScenesWith = const NetworkFailed('sem rede');
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      await tester.pump(const Duration(seconds: 12));

      expect(
        find.text(_gravarAPassagemInteira),
        findsOneWidget,
        reason: 'sem a lista das cenas a casa escondia a troca do grão',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the grain switch rests while a take records', (tester) async {
    final container = await _naCasaDoEnsaio(tester);
    await tester.pump(const Duration(seconds: 1));

    await _tocar(tester, _naLinha(1, _gravar));

    expect(
      tester
          .widget<Semantics>(byLabel(_gravarAPassagemInteira))
          .properties
          .enabled,
      isFalse,
      reason: 'a troca do grão ficava viva com o microfone aberto',
    );
    await _tocar(tester, _naLinha(1, _parar));
    closeTheRoom(container);
  });

  testWidgets('the grain switch rests while a take is on its way to the room', (
    tester,
  ) async {
    final (harness, container) = await _comAParte1NoAr(tester);

    expect(
      tester
          .widget<Semantics>(byLabel(_gravarAPassagemInteira))
          .properties
          .enabled,
      isFalse,
      reason: 'a troca do grão ficava viva com a gravação a caminho da sala',
    );
    harness.room.finishHeldTake();
    await letTheRehearsalReachTheRoom(tester);
    closeTheRoom(container);
  });

  testWidgets(
    'a tap on the grain switch while a take is on its way switches nothing',
    (tester) async {
      final (harness, container) = await _comAParte1NoAr(tester);

      await _tocar(tester, find.text(_gravarAPassagemInteira));
      await letTheRehearsalReachTheRoom(tester);

      expect(
        harness.room.grainSwitches,
        isEmpty,
        reason: 'o toque trocava o grão com a gravação ainda no ar',
      );
      harness.room.finishHeldTake();
      await letTheRehearsalReachTheRoom(tester);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the grain switch rests while a take is being kept on the tablet',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      await tester.pump(const Duration(seconds: 1));
      (harness.takes as FakeTakeQueue).holdNextKeep();

      await _gravarNaLinha(tester, 1);

      expect(
        tester
            .widget<Semantics>(byLabel(_gravarAPassagemInteira))
            .properties
            .enabled,
        isFalse,
        reason:
            'a troca do grão ficava viva com a gravação ainda sendo guardada',
      );
      (harness.takes as FakeTakeQueue).finishHeldKeep();
      await letTheRehearsalReachTheRoom(tester);
      closeTheRoom(container);
    },
  );

  testWidgets('«Ouvir tudo» shows only once the room holds every part', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _naCasaDoEnsaio(tester, harness: harness);
    for (final n in [1, 2, 3]) {
      await _gravarNaLinha(tester, n);
    }
    await theRoomNamesTheParts(tester, container, parts: 3);
    expect(_ouvirTudo(), isFalse, reason: 'a cena 4 ainda não tem parte');

    (harness.takes as FakeTakeQueue).holdNextKeep();
    harness.room.holdNextTake(KeptScope.parte(4));
    await _gravarNaLinha(tester, 4);
    expect(_ouvirTudo(), isFalse, reason: 'a cena 4 ainda está sendo guardada');

    await _aQuartaChegaAPorta(tester, harness);
    expect(_ouvirTudo(), isFalse, reason: 'a cena 4 ainda está subindo');

    await _aQuartaChegaASala(tester, harness, container);
    expect(_ouvirTudo(), isTrue);
    closeTheRoom(container);
  });

  testWidgets(
    'from the keep tap until the room holds the part the advance disc stays '
    'dark and its tap stays on the recording home',
    (tester) async {
      final (harness, container) = await _aQuartaGuardadaDevagar(tester);

      expect(_discoAceso(tester), isFalse, reason: 'guardando a cena 4');
      await _oToqueNoDiscoFicaNaCasa(tester, container);

      await _aQuartaChegaAPorta(tester, harness);
      expect(_discoAceso(tester), isFalse, reason: 'a cena 4 subindo');
      await _oToqueNoDiscoFicaNaCasa(tester, container);

      await _aQuartaChegaASala(tester, harness, container);
      expect(_discoAceso(tester), isTrue);
      await _tocar(tester, inTheHome(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets('a part still going up leaves the home not busy', (tester) async {
    final (harness, container) = await _aQuartaGuardadaDevagar(tester);

    expect(_estado(container).homeBusy, isFalse);

    await _aQuartaChegaAPorta(tester, harness);
    expect(_estado(container).homeBusy, isFalse);
    await _aQuartaChegaASala(tester, harness, container);
    closeTheRoom(container);
  });

  testWidgets(
    'a keep whose count fell on a station change keeps the advance disc dark '
    'on the way back to the home',
    (tester) async {
      final (harness, container) = await _aQuartaGuardadaDevagar(tester);
      final notifier = container.read(salaSessionProvider.notifier);

      final fila = harness.takes as FakeTakeQueue;
      notifier.leaveTheRecording();
      await letTheRehearsalReachTheRoom(tester);
      fila
        ..holdTheNextReading()
        ..finishHeldKeep();
      await waitFor(
        'a contagem da cena 4 olhar a fila',
        () => fila.readingHeld,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      fila.holdTheNextReading();
      notifier.goEnsaio();
      await waitFor(
        'a contagem da chegada à casa olhar a fila',
        () => fila.readingsHeld >= 2,
        step: () => letTheRehearsalReachTheRoom(tester),
      );

      expect(_estado(container).stage, SalaStage.ensaio);
      expect(_discoAceso(tester), isFalse, reason: 'a cena 4 ainda conta');
      await _oToqueNoDiscoFicaNaCasa(tester, container);

      fila.releaseTheOldestReading();
      await letTheRehearsalReachTheRoom(tester);
      expect(
        _discoAceso(tester),
        isFalse,
        reason: 'a conta da cena 4 caiu com a troca de estação',
      );
      await _oToqueNoDiscoFicaNaCasa(tester, container);

      fila.releaseTheHeldReading();
      await waitFor(
        'a cena 4 chegar à porta da sala',
        () => harness.room.takeHeld,
        step: () => letTheRehearsalReachTheRoom(tester),
      );

      expect(_estado(container).stage, SalaStage.ensaio);
      expect(_discoAceso(tester), isFalse, reason: 'a cena 4 ainda sobe');
      await _oToqueNoDiscoFicaNaCasa(tester, container);

      await _aQuartaChegaASala(tester, harness, container);
      await waitFor(
        'o disco acender com a cena 4 na sala',
        () => _discoAceso(tester),
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      await _tocar(tester, inTheHome(_irParaATraducao));
      expect(_estado(container).stage, SalaStage.retro);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a keep whose session goes while it is being kept leaves no part being kept',
    (tester) async {
      final (harness, container) = await _aQuartaGuardadaDevagar(tester);
      final sessao = _estado(container).sessionId!;
      harness.room.forgetTheSession(sessao);

      container.read(salaSessionProvider.notifier).goEnsaio();
      await waitFor(
        'a sala largar a sessão',
        () => _estado(container).sessionId != sessao,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      (harness.takes as FakeTakeQueue).finishHeldKeep();
      await letTheRehearsalReachTheRoom(tester);

      expect(_estado(container).machine.keeping, isEmpty);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a keep whose count fails lights the advance disc again and leaves no part '
    'being kept',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _naCasaDoEnsaio(tester, harness: harness);
      for (final n in [1, 2, 3]) {
        await _gravarNaLinha(tester, n);
      }
      await theRoomNamesTheParts(tester, container, parts: 3);
      final notifier = container.read(salaSessionProvider.notifier);
      final fila = harness.takes as FakeTakeQueue;
      final falhas = <Object>[];
      notifier
        ..gravarACena(4)
        ..gravarACena(4);
      await waitFor(
        'a cena 4 esperar o visto',
        () => _estado(container).ensaio == EnsaioStatus.recorded,
        step: () => letTheRehearsalReachTheRoom(tester),
      );

      fila.failsTheNextReading = true;
      runZonedGuarded(notifier.takeKeep, (falha, _) => falhas.add(falha));
      await waitFor(
        'a contagem da cena 4 falhar',
        () => falhas.isNotEmpty,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      await letTheRehearsalReachTheRoom(tester);

      expect(falhas.single, isA<FileSystemException>());
      expect(_estado(container).machine.keeping, isEmpty);
      expect(_discoAceso(tester), isTrue);
      closeTheRoom(container);
    },
  );
}
