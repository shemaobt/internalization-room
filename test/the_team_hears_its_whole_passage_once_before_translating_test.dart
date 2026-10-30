import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';
import 'package:internalization_room/features/sala/presentation/widgets/stage_heading.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, intoTheRecordingHome, settle;
import 'um_ensaio_de_tres_partes.dart';

const _soOuvir = 'Primeiro, só ouvir: a passagem inteira, do começo ao fim.';
const _soOuvirEn =
    'First, just listen: the whole passage, from beginning to end.';
const _soOuvirAGravacao =
    'Primeiro, só ouvir: a gravação de vocês inteira, do começo ao fim.';
const _contar =
    'Toquem no círculo para pausar onde a frase acaba; toquem de novo para '
    'traduzir só o que aquela frase diz, e de novo para a gravação seguir.';
const _ensaioFinal = 'Ensaio Final';
const _terminei = 'terminei';
const _naoDeuParaConferir = 'não deu para conferir agora — tentem de novo';
const _tocarOuPausar = 'Tocar ou pausar a gravação';
const _faltaOuvir = 'ainda falta ouvir um trecho da gravação';
const _faltaTraduzir =
    "falta traduzir um trecho — ouçam e traduzam, depois toquem em 'terminei'";

/// The parts of [it] stood as a Joined recording on the tablet: each one is the bytes of
/// its scene's rehearsal, as the join leaves them.
void _juntadas(Sala it) {
  final nomes = {for (final parte in it.partes) parte.path: parte.takeId};
  for (final MapEntry(:key, :value)
      in it.harness.emAberto.rows.entries.toList()) {
    it.harness.emAberto.rows[key] = ResumePoint(
      sessionId: value.sessionId,
      stage: value.stage,
      takes: [
        for (final (onde, take) in value.takes.indexed)
          KeptTake(
            scopeId: take.scopeId,
            path: take.path,
            takeId: nomes[take.path] ?? take.takeId,
            pass: take.pass,
            origin: 'ensaio-da-cena-${onde + 1}',
          ),
      ],
      savedAt: value.savedAt,
      language: value.language,
      passesToGoAbove: value.passesToGoAbove,
    );
  }
}

Future<void> _reabrir(Sala it) async {
  it.container.dispose();
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
}

/// A Joined recording of three parts on the recording home: nothing told back, nothing
/// heard, the advance disc lit.
Future<Sala> _juntadaNaCasa({SalaHarness? numaSala}) async {
  final it = await umEnsaioGravado(partesDoEnsaio, numaSala: numaSala);
  _juntadas(it);
  await _reabrir(it);
  await waitFor(
    'a casa voltar com as três partes juntadas',
    () =>
        it.estado.stage == SalaStage.ensaio &&
        it.partes.length == 3 &&
        it.estado.joined &&
        it.estado.ensaioDone,
  );
  return it;
}

void _nadaOuvido(Sala it) => it.harness.room.listeningUnheardTakeIds = [
  for (final parte in it.partes) parte.takeId!,
];

void _tudoOuvido(Sala it) => it.harness.room.listeningUnheardTakeIds = const [];

List<String> _caminhos(Sala it, List<int> partes) => [
  for (final onde in partes) it.partes[onde].path,
];

/// The advance disc, up to the first part going in the air.
Future<void> _oDisco(Sala it) async {
  final tocadas = it.harness.playback.played.length;
  it.sala.startRetro();
  await waitFor(
    'uma parte entrar no ar',
    () => it.harness.playback.played.length > tocadas,
  );
}

/// Parts [desde] to the last, each heard to its end in turn, with no tap between them.
Future<void> _ouvirAte(Sala it, {int desde = 0, int? ate}) async {
  final ultima = ate ?? partesDoEnsaio.length - 1;
  for (var onde = desde; onde <= ultima; onde++) {
    await waitFor(
      'a parte ${onde + 1} entrar no ar',
      () =>
          it.harness.playback.played.isNotEmpty &&
          it.harness.playback.played.last == it.partes[onde].path &&
          it.harness.playback.sounding,
    );
    await ouvirAteOFim(it, partesDoEnsaio[onde]);
  }
}

Future<void> _ouvirSoAsDuasPrimeiras(
  Sala it, {
  required void Function() antesDoFim,
}) async {
  it.harness.room.listeningUnheardTakeIds = [
    it.partes[0].takeId!,
    it.partes[1].takeId!,
  ];
  await _oDisco(it);
  await _ouvirAte(it, ate: 0);
  antesDoFim();
  final relatos = it.harness.room.listeningReports.length;
  await _ouvirAte(it, desde: 1, ate: 1);
  await waitFor(
    'a sala responder o fim da escuta',
    () => it.harness.room.listeningReports.length > relatos,
  );
  await settle();
}

int _microfones(Sala it) =>
    it.harness.sounds.where((som) => som == 'recorder:start').length;

Future<void> _abrirOMicrofone(Sala it) async {
  final antes = _microfones(it);
  await theClipOpens(it.harness);
  it.harness.playback.at = const Duration(seconds: 6);
  it.sala.retroTap();
  it.sala.retroTap();
  await waitFor('o microfone abrir', () => _microfones(it) > antes);
}

/// Two told stretches on part 1, as the room holds them once frases were carried in.
void _frasesTrazidas(Sala it) {
  final primeira = it.partes[0].takeId!;
  it.harness.room.segments.addAll([
    SegmentView(
      segmentId: 'trazida-1',
      takeId: primeira,
      startsMs: 0,
      endsMs: 4000,
    ),
    SegmentView(
      segmentId: 'trazida-2',
      takeId: primeira,
      startsMs: 4000,
      endsMs: 10000,
    ),
  ]);
}

Future<Sala> _naTela(
  WidgetTester tester,
  Future<Sala> Function() comoFica,
) async {
  tester.view
    ..physicalSize = const Size(820, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late Sala it;
  await tester.runAsync(() async => it = await comoFica());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: it.container, child: const SalaApp()),
  );
  await tester.pump();
  return it;
}

Finder _oCirculo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

Finder _oTitulo(String texto) => find.byWidgetPredicate(
  (widget) =>
      widget is StageHeading &&
      widget.stage == SalaStage.retro &&
      widget.text == texto,
);

Future<void> _ate(WidgetTester tester, Future<void> Function() passo) async {
  await tester.runAsync(passo);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// ---- The join, driven as ENG-1385's own test file drives it. ----

const _joinLabel = 'juntar as cenas e ouvir';
const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {
        'Gravar o ensaio de vocês',
        'Abrir o Ensaio Final',
      }.contains(widget.properties.label),
);

Uint8List _bytesOf(int n) =>
    aWavTake(samples: [for (var i = 0; i < 40; i++) n * 100 + i]);

SceneRehearsalRecord _rehearsal(String sessionId, int n) =>
    SceneRehearsalRecord(
      rehearsalId: '$sessionId-ensaio-$n',
      sessionId: sessionId,
      n: n,
      scene: 'S$n',
      recordedAt: DateTime.utc(2026, 10, 22, 13, 7),
      sentAt: '2026-10-22T10:0$n:00+00:00',
      durationMs: 6000,
      frases: const [
        SceneFrase(fraseId: 'frase-a', startsMs: 0, endsMs: 3000),
        SceneFrase(fraseId: 'frase-b', startsMs: 3000, endsMs: 6000),
      ],
      verified: true,
      sha256: crypto.sha256.convert(_bytesOf(n)).toString(),
    );

Future<void> _beat(
  WidgetTester tester, [
  Duration ahead = Duration.zero,
]) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 15)),
  );
  await tester.pump(ahead);
}

Future<void> _until(
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
    await _beat(tester, const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: what);
}

Future<void> _settle(WidgetTester tester) async {
  for (var vez = 0; vez < 15; vez++) {
    await _beat(tester, const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _naConversaComTresCenas(
  WidgetTester tester,
) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final home = Directory.systemTemp.createTempSync('sala-1408-junta');
  final harness = SalaHarness(takesHome: home)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = const Moment(
      at: MomentAt.internalization,
      part: 2,
      parts: 3,
    )
    ..room.passageScenes = _threeScenes;
  final container = (await tester.runAsync(
    () async => harness.container()..read(salaSessionProvider),
  ))!;
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  final notifier = container.read(salaSessionProvider.notifier);
  await _settle(tester);
  unawaited(notifier.abrirEscolha());
  await _settle(tester);
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _until(
    tester,
    'a conversa abrir',
    () =>
        container.read(salaSessionProvider).voice == VoiceState.invite &&
        !container.read(salaSessionProvider).awaitingTheGuide,
  );
  for (var vez = 0; vez < 15; vez++) {
    await _beat(tester, const Duration(milliseconds: 100));
  }
  return (harness, container);
}

void main() {
  testWidgets('after the last scene is joined the first listen starts with no '
      'tap', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, container) = await _naConversaComTresCenas(tester);
    SalaSessionState estado() => container.read(salaSessionProvider);
    final sessionId = estado().sessionId!;
    for (final n in [1, 2, 3]) {
      harness.room.sceneRehearsals.add(_rehearsal(sessionId, n));
      harness.room.sceneAudioOf['$sessionId-ensaio-$n'] = _bytesOf(n);
    }
    harness.room.listeningUnheardTakeIds = [
      for (final n in [1, 2, 3]) 'gravacao-$n',
    ];
    await tester.tap(_dot);
    await _until(
      tester,
      'o plano abrir',
      () => find.text(_planLine).evaluate().isNotEmpty,
    );
    await _settle(tester);
    final linhas = harness.voice.fixedLines.length;
    final tocadas = harness.playback.played.length;
    final desde = harness.playback.playedFrom.length;

    await tester.ensureVisible(byLabel(_joinLabel));
    await tester.pump();
    await tester.tap(byLabel(_joinLabel));
    await _until(
      tester,
      'a primeira parte entrar no ar sem toque',
      () => harness.playback.played.length > tocadas,
    );
    expect(
      [for (final parte in estado().partes) parte.takeId],
      harness.room.listeningUnheardTakeIds,
      reason: 'o cenário só mede alguma coisa se a sala contar as três',
    );

    await _beat(tester, const Duration(seconds: 1));
    expect(_oTitulo(_ensaioFinal), findsOneWidget);
    expect(find.text(_soOuvir), findsOneWidget);
    expect(harness.voice.fixedLines.skip(linhas), [('N0', 'pt')]);
    final depois = harness.sounds.toList();
    expect(
      depois.lastIndexOf('voice:fixed'),
      lessThan(depois.lastIndexOf('playback:play')),
      reason: 'a fala dela vem antes do som da primeira parte',
    );
    for (var onde = 0; onde < 3; onde++) {
      await _until(
        tester,
        'a parte ${onde + 1} no ar',
        () =>
            harness.playback.played.length == tocadas + onde + 1 &&
            harness.playback.sounding,
      );
      await tester.runAsync(() => theClipOpens(harness));
      harness.playback
        ..length = const Duration(seconds: 6)
        ..at = const Duration(seconds: 6)
        ..finishPlayback();
      await _beat(tester);
    }
    expect(harness.playback.played.skip(tocadas), [
      for (final parte in estado().partes) parte.path,
    ]);
    expect(harness.playback.playedFrom.skip(desde), [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ]);
    semantics.dispose();
    closeTheRoom(container);
  });

  testWidgets(
    'a join that stops on a row does not start the first listen, in a room that '
    'answers any take holding those bytes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final (harness, container) = await _naConversaComTresCenas(tester);
      harness.room.joinsTheLiveTake = false;
      SalaSessionState estado() => container.read(salaSessionProvider);
      final sessionId = estado().sessionId!;
      for (final n in [1, 2, 3]) {
        harness.room.sceneRehearsals.add(_rehearsal(sessionId, n));
        harness.room.sceneAudioOf['$sessionId-ensaio-$n'] = _bytesOf(n);
      }
      harness.room.listeningUnheardTakeIds = const [
        'gravacao-1',
        'gravacao-2',
        'gravacao-a-mao',
      ];
      await tester.tap(_dot);
      await _until(
        tester,
        'o plano abrir',
        () => find.text(_planLine).evaluate().isNotEmpty,
      );
      await _settle(tester);
      harness.room.takes.addAll([
        TakeView(
          takeId: 'gravacao-junta-antiga',
          kind: 'ensaio',
          scope: KeptScope.parte(3),
          ordinal: 3,
          pass: 1,
          origin: '$sessionId-ensaio-3',
        ),
        TakeView(
          takeId: 'gravacao-a-mao',
          kind: 'ensaio',
          scope: KeptScope.parte(3),
          ordinal: 3,
          pass: 2,
        ),
      ]);
      harness.room.takeAudio['gravacao-junta-antiga'] = _bytesOf(3);
      harness.room.takeAudio['gravacao-a-mao'] = _bytesOf(7);
      final linhas = harness.voice.fixedLines.length;
      final tocadas = harness.playback.played.length;

      await tester.ensureVisible(byLabel(_joinLabel));
      await tester.pump();
      await tester.tap(byLabel(_joinLabel));
      await _until(
        tester,
        'a junta parar na casa com as três partes',
        () =>
            estado().joining == null &&
            estado().everySceneHasItsPart &&
            find.text(_homeLine).evaluate().isNotEmpty,
      );
      await _settle(tester);

      expect(find.text(_homeLine), findsOneWidget);
      expect(find.text(_soOuvir), findsNothing);
      expect(harness.voice.fixedLines.skip(linhas), isEmpty);
      expect(harness.playback.played.length, tocadas);
      semantics.dispose();
      closeTheRoom(container);
    },
  );

  test(
    'the disc on a joined recording nobody heard plays N0 and the whole passage with no microphone',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;
      final microfones = _microfones(it);

      await _oDisco(it);
      expect(it.harness.voice.fixedLines.skip(linhas), [('N0', testLanguage)]);
      await _ouvirAte(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      expect(
        _microfones(it),
        microfones,
        reason: 'só ouvir: microfone fechado',
      );
    },
  );

  testWidgets(
    'during the first listen there is no terminei, no circle, and the part strips do nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await theClipOpens(it.harness);
        it.harness.playback.at = const Duration(seconds: 3);
      });
      final tocadas = it.harness.playback.played.length;
      final microfones = _microfones(it);

      expect(find.text(_terminei), findsNothing);
      expect(
        _oCirculo(),
        findsNothing,
        reason:
            'o primeiro ouvir desenhava um círculo grande que não fazia nada',
      );

      final faixasDasPartes = find.descendant(
        of: find.byType(PartStrips),
        matching: find.byType(SceneStrip),
      );
      expect(faixasDasPartes, findsWidgets);
      await tester.tap(faixasDasPartes.first);
      await _ate(tester, () => settle());
      expect(it.harness.playback.played.length, tocadas);
      expect(it.harness.playback.ranges, isEmpty);
      expect(it.harness.playback.position, const Duration(seconds: 3));
      expect(it.harness.playback.sounding, isTrue);
      expect(_microfones(it), microfones);
      semantics.dispose();
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'the circle comes back on the telling, once the listen gives way to P1',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
      });
      expect(_oCirculo(), findsNothing);

      await _ate(tester, () async {
        _tudoOuvido(it);
        final tocadas = it.harness.playback.played.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'a primeira voltar ao ar',
          () => it.harness.playback.played.length > tocadas,
        );
      });

      expect(it.harness.voice.fixedLines.last, ('P1', testLanguage));
      expect(it.container.read(salaSessionProvider).btSoOuvir, isFalse);
      expect(
        _oCirculo(),
        findsOneWidget,
        reason: 'o círculo sumia junto com a escuta e não voltava para contar',
      );
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'while P1 is still said after the listen, the circle and the telling line '
    'already stand, and the circle answers once she is done',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        _tudoOuvido(it);
        it.harness.voice.holdNextLine();
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'a P1 dela começar',
          () => it.harness.voice.fixedLines.last.$1 == 'P1',
        );
      });

      expect(
        _oCirculo(),
        findsOneWidget,
        reason: 'a tela de só ouvir ficava de pé enquanto a P1 era dita',
      );
      expect(find.text(_contar), findsOneWidget);
      expect(find.text(_soOuvir), findsNothing);

      await _ate(tester, () async {
        final tocadas = it.harness.playback.played.length;
        it.harness.voice.finishHeldLine();
        await waitFor(
          'a primeira voltar ao ar',
          () => it.harness.playback.played.length > tocadas,
        );
      });
      await _ate(tester, () => _abrirOMicrofone(it));
      closeTheRoom(it.container);
    },
  );

  test(
    'the play control pauses and a second tap resumes where it stopped',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 0);
      await waitFor(
        'a segunda parte no ar',
        () => it.harness.playback.played.last == it.partes[1].path,
      );
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = partesDoEnsaio[1]
        ..at = const Duration(seconds: 3);
      final tocadas = it.harness.playback.played.length;

      it.sala.ouvirGravacao();
      await waitFor('a parte pausar', () => !it.harness.playback.sounding);
      it.sala.ouvirGravacao();
      await waitFor('a parte seguir', () => it.harness.playback.sounding);

      expect(
        it.harness.playback.played.length,
        tocadas,
        reason: 'segue de onde parou, sem recomeçar a parte',
      );
      expect(it.harness.playback.position, const Duration(seconds: 3));

      await ouvirAteOFim(it, partesDoEnsaio[1]);
      await waitFor(
        'a terceira entrar no ar por si',
        () => it.harness.playback.played.last == it.partes[2].path,
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'leaving before anything was heard and coming back starts the first listen again',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await theClipOpens(it.harness);
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _oDisco(it);

      expect(it.harness.voice.fixedLines.skip(linhas), [('N0', testLanguage)]);
      expect(it.harness.playback.played.skip(tocadas), _caminhos(it, [0]));
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'leaving mid listen and coming back plays P2 and only what the room still counts unheard',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 0);
      await waitFor(
        'a segunda no ar',
        () => it.harness.playback.played.last == it.partes[1].path,
      );
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      it.harness.room.listeningUnheardTakeIds = [
        it.partes[2].takeId!,
        it.partes[1].takeId!,
      ];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;

      await _oDisco(it);
      expect(it.harness.voice.fixedLines.skip(linhas), [('P2', testLanguage)]);
      await _ouvirAte(it, desde: 1);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [1, 2]),
        reason: 'a primeira já foi ouvida e não toca',
      );
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
      ]);
    },
  );

  testWidgets(
    'a line that cannot be loaded is skipped and the recording plays',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        it.harness.voice.refuses.add('N0');
        await _oDisco(it);
      });

      expect(
        it.harness.voice.fixedLines,
        contains(('N0', testLanguage)),
        reason: 'a fala dela foi pedida',
      );
      expect(find.text(_soOuvir), findsOneWidget);
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.sounding, isTrue);
      expect(
        it.container.read(salaSessionProvider).halt,
        isA<NoHalt>(),
        reason: 'nenhum sinal de pessoa na tela',
      );
      closeTheRoom(it.container);
    },
  );

  test(
    'every part unheard again brings N0 and the whole recording again',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a P1 dela depois da escuta',
        () => it.harness.voice.fixedLines.last.$1 == 'P1',
      );
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _oDisco(it);
      expect(it.harness.voice.fixedLines.skip(linhas), [('N0', testLanguage)]);
      await _ouvirAte(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
    },
  );

  test(
    'the listen reports each part as it ends and only what sounded',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      final relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, ate: 0);
      await waitFor(
        'o relato da primeira',
        () => it.harness.room.listeningReports.length > relatos,
      );
      final primeira = it.partes[0].takeId;
      expect(
        it.harness.room.listeningReports.last.where(
          (parte) => parte['take_id'] == primeira,
        ),
        [
          {
            'take_id': primeira,
            'played_ranges': [
              [0, partesDoEnsaio[0].inMilliseconds],
            ],
            'clip_duration_ms': partesDoEnsaio[0].inMilliseconds,
          },
        ],
      );

      await waitFor(
        'a segunda no ar',
        () => it.harness.playback.played.last == it.partes[1].path,
      );
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 3);
      it.sala.ouvirGravacao();
      await waitFor('a pausa', () => !it.harness.playback.sounding);
      it.sala.ouvirGravacao();
      await waitFor('a parte seguir', () => it.harness.playback.sounding);
      await ouvirAteOFim(it, partesDoEnsaio[1]);

      final segunda = it.partes[1].takeId;
      expect(
        it.harness.room.listeningReports.last
            .where((parte) => parte['take_id'] == segunda)
            .map((parte) => parte['played_ranges']),
        [
          [
            [0, partesDoEnsaio[1].inMilliseconds],
          ],
        ],
        reason: 'pausada e retomada, a segunda soou inteira',
      );

      await waitFor(
        'a terceira no ar',
        () => it.harness.playback.played.last == it.partes[2].path,
      );
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 3);
      it.sala.ouvirGravacao();
      await waitFor('a pausa', () => !it.harness.playback.sounding);
      it.sala.theAppWentAway();

      final terceira = it.partes[2].takeId;
      expect(
        it.harness.room.listeningReports.last
            .where((parte) => parte['take_id'] == terceira)
            .map((parte) => parte['played_ranges']),
        [
          [
            [0, 3000],
          ],
        ],
        reason: 'pausada e deixada, a terceira soou só até a pausa',
      );
    },
  );

  testWidgets(
    'heard whole with an untranslated stretch opens the telling there',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      late int linhas;
      late int tocadas;
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        _tudoOuvido(it);
        it.harness.room
          ..listeningFixedLine = 'N2'
          ..listeningUntranslated = [
            UntranslatedPart(
              takeId: it.partes[1].takeId!,
              scene: 2,
              from: const Duration(milliseconds: 4000),
            ),
          ];
        linhas = it.harness.voice.fixedLines.length;
        tocadas = it.harness.playback.played.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'a segunda voltar ao ar',
          () => it.harness.playback.played.length > tocadas,
        );
      });

      expect(it.harness.voice.fixedLines.skip(linhas), [('N2', testLanguage)]);
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(it.harness.playback.playedFrom.last, const Duration(seconds: 4));
      expect(
        find.text(_terminei),
        findsOneWidget,
        reason: 'fora do só ouvir, terminei segue a sua própria regra',
      );
      await _ate(tester, () => _abrirOMicrofone(it));
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'the untranslated stretch the room names after the listen is written '
    'with its scenes, not left to the voice alone',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        _tudoOuvido(it);
        it.harness.room
          ..listeningFixedLine = 'N2'
          ..listeningUntranslated = [
            UntranslatedPart(
              takeId: it.partes[1].takeId!,
              scene: 2,
              from: const Duration(milliseconds: 4000),
            ),
            UntranslatedPart(takeId: it.partes[2].takeId!, scene: 3),
          ];
        final tocadas = it.harness.playback.played.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'a segunda voltar ao ar',
          () => it.harness.playback.played.length > tocadas,
        );
      });

      expect(
        find.text('$_faltaTraduzir · cena 2, cena 3'),
        findsOneWidget,
        reason: 'a tela não dizia que faltava traduzir, nem em que cena',
      );
      closeTheRoom(it.container);
    },
  );

  test(
    'coming back to a joined recording heard whole, a stretch the room names '
    'is said once and played, not skipped for the untold ground',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final tocadas = it.harness.playback.played.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira voltar ao ar com a P1',
        () => it.harness.playback.played.length > tocadas,
      );
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[1].takeId!,
            scene: 2,
            from: const Duration(milliseconds: 3000),
          ),
        ];
      final linhas = it.harness.voice.fixedLines.length;

      await _oDisco(it);
      await settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N2', testLanguage)],
        reason: 'de volta à tradução, o trecho sem tradução passava calado',
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(milliseconds: 3000),
      );
      expect(it.estado.btCenasSemTraducao, [2]);
      await _abrirOMicrofone(it);
    },
  );

  test(
    'coming back to a joined recording the team checked clean, a stretch the '
    'room still names stays quiet, as their own terminei closed it',
    () async {
      final it = await _juntadaNaCasa();
      _frasesTrazidas(it);
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = true
        ..listeningFixedLine = 'N1'
        ..verdictChecked = true;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a conferência limpa',
        () => it.estado.btPhase == BtPhase.conferida,
      );
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      it.harness.room
        ..listeningAutomaticCheck = false
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[1].takeId!,
            scene: 2,
            from: const Duration(milliseconds: 3000),
          ),
        ]
        ..retroSoFar = BackTranslationProgress(
          segments: [...it.harness.room.segments],
          checked: true,
        );
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      it.sala.startRetro();
      await waitFor(
        'a tradução voltar ao seu veredito',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.conferida &&
            !it.estado.awaitingTheGuide,
      );
      await settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        isEmpty,
        reason: 'a N-3 voltava sobre um trecho que a conferência limpa fechou',
      );
      expect(it.estado.btRecusa, isNull);
      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason: 'a gravação voltava a tocar sobre a conferência limpa',
      );
    },
  );

  test('coming back to a joined recording the room checked elsewhere lands on '
      'its verdict, though this tablet never heard the check', () async {
    final it = await _juntadaNaCasa();
    _frasesTrazidas(it);
    _nadaOuvido(it);
    await _oDisco(it);
    await _ouvirAte(it, ate: 1);
    _tudoOuvido(it);
    await _ouvirAte(it, desde: 2);
    it.sala.goEnsaio();
    await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
    expect(it.estado.btChecked, isFalse);
    it.harness.room.retroSoFar = BackTranslationProgress(
      segments: [...it.harness.room.segments],
      checked: true,
    );
    final linhas = it.harness.voice.fixedLines.length;
    final tocadas = it.harness.playback.played.length;

    it.sala.startRetro();
    await waitFor(
      'a tradução voltar',
      () => it.estado.stage == SalaStage.retro && !it.estado.awaitingTheGuide,
    );
    await settle();

    expect(
      it.estado.btPhase,
      BtPhase.conferida,
      reason: 'a conferência que a sala guarda não voltava a este tablet',
    );
    expect(it.harness.voice.fixedLines.skip(linhas), isEmpty);
    expect(it.harness.playback.played.skip(tocadas), isEmpty);
  });

  test('after recomeçar a tradução the next listen the room checks runs the '
      'automatic check again, not a memory of the first', () async {
    final it = await _juntadaNaCasa();
    _frasesTrazidas(it);
    _nadaOuvido(it);
    await _oDisco(it);
    await _ouvirAte(it, ate: 1);
    _tudoOuvido(it);
    it.harness.room
      ..listeningAutomaticCheck = true
      ..listeningFixedLine = 'N1'
      ..verdictChecked = true;
    await _ouvirAte(it, desde: 2);
    await waitFor(
      'a primeira conferência',
      () => it.estado.btPhase == BtPhase.conferida,
    );
    it.sala.recomecarATraducao();
    await settle(const Duration(milliseconds: 700));
    it.sala.recomecarATraducao();
    await waitFor(
      'a tradução recomeçar',
      () =>
          it.harness.room.restartsAsked.isNotEmpty &&
          it.estado.btPhase == BtPhase.playing,
    );
    it.sala.goEnsaio();
    await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
    _nadaOuvido(it);
    await _oDisco(it);
    await _ouvirAte(it, ate: 1);
    _tudoOuvido(it);
    final linhas = it.harness.voice.fixedLines.length;
    final conferidas = it.harness.room.playedByTakeSent.length;

    await _ouvirAte(it, desde: 2);
    await waitFor(
      'a segunda conferência',
      () => it.harness.room.playedByTakeSent.length > conferidas,
    );

    expect(it.harness.voice.fixedLines.skip(linhas), [('N1', testLanguage)]);
    expect(
      it.harness.room.playedByTakeSent.length,
      conferidas + 1,
      reason: 'depois do recomeço, a conferência sozinha não voltava',
    );
  });

  test('an automatic check the room refuses leaves her «não deu para '
      'conferir» on the telling, not a silent screen', () async {
    final it = await _juntadaNaCasa();
    _frasesTrazidas(it);
    _nadaOuvido(it);
    await _oDisco(it);
    await _ouvirAte(it, ate: 1);
    _tudoOuvido(it);
    var conferiu = false;
    it.harness.room
      ..listeningAutomaticCheck = true
      ..listeningFixedLine = 'N1'
      ..failFinishWith = const Refused('BAD_REQUEST')
      ..duranteOVeredito = () => conferiu = true;

    await _ouvirAte(it, desde: 2);
    await waitFor(
      'a conferência sozinha voltar',
      () =>
          conferiu &&
          !it.estado.btConferindo &&
          it.estado.btPhase != BtPhase.thinking,
    );
    await settle();

    expect(
      it.estado.btRecusa,
      CheckRefusal.checkUnavailable,
      reason: 'a conferência sozinha que a sala recusava não deixava linha',
    );
    expect(it.estado.btPhase, BtPhase.playing);
    expect(it.estado.needsPerson, isFalse);
  });

  test('a terminei the room refuses over an untranslated stretch says N2 again '
      'and plays that stretch, never an empty findings screen', () async {
    final it = await _juntadaNaCasa();
    _nadaOuvido(it);
    await _oDisco(it);
    await _ouvirAte(it, ate: 1);
    _tudoOuvido(it);
    it.harness.room
      ..listeningFixedLine = 'N2'
      ..listeningUntranslated = [
        UntranslatedPart(
          takeId: it.partes[1].takeId!,
          scene: 2,
          from: const Duration(milliseconds: 4000),
        ),
      ];
    await _ouvirAte(it, desde: 2);
    await _ouvirAte(it, desde: 1);
    await waitFor('o terminei abrir', () => it.estado.canFinishBackTranslation);
    it.harness.room
      ..verdictRefusal = CheckRefusal.stretchUntranslated
      ..verdictFixedLine = 'N2'
      ..verdictUntranslated = [
        UntranslatedPart(
          takeId: it.partes[1].takeId!,
          scene: 2,
          from: const Duration(milliseconds: 2500),
        ),
      ];
    final linhas = it.harness.voice.fixedLines.length;
    final tocadas = it.harness.playback.played.length;

    await it.sala.finishBackTranslation();
    await waitFor(
      'a segunda voltar ao ar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(
      it.harness.voice.fixedLines.skip(linhas),
      [('N2', testLanguage)],
      reason: 'a recusa do terminei passava sem a N-3 dela',
    );
    expect(it.harness.playback.played.last, it.partes[1].path);
    expect(
      it.harness.playback.playedFrom.last,
      const Duration(milliseconds: 2500),
    );
    expect(
      it.estado.btPhase,
      BtPhase.playing,
      reason: 'a recusa caía na tela de achados, vazia',
    );
    expect(it.estado.awaitingTheGuide, isFalse);
    expect(
      it.estado.btRecusa,
      CheckRefusal.stretchUntranslated,
      reason: 'a recusa do terminei não deixava a dica na tela',
    );
    expect(it.estado.btCenasSemTraducao, [2]);
    await _abrirOMicrofone(it);
  });

  testWidgets(
    'heard whole with everything translated runs one automatic check',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _frasesTrazidas(it);
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        _tudoOuvido(it);
        it.harness.room
          ..listeningAutomaticCheck = true
          ..listeningFixedLine = 'N1'
          ..holdNextVerdict();
      });
      final linhas = it.harness.voice.fixedLines.length;
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;

      await _ate(tester, () async {
        await _ouvirAte(it, desde: 2);
        await waitFor('a conferência ser pedida', () => pedidas > 0);
      });

      expect(it.harness.voice.fixedLines.skip(linhas), [('N1', testLanguage)]);
      expect(find.text('conferindo…'), findsOneWidget);
      await _ate(tester, () async {
        it.harness.room.finishHeldVerdict();
        await settle();
      });
      expect(pedidas, 1, reason: 'uma conferência, sem toque');
      closeTheRoom(it.container);
    },
  );

  testWidgets('a second listen the room does not check stays quiet', (
    tester,
  ) async {
    final it = await _naTela(tester, _juntadaNaCasa);
    late int linhas;
    late int depois;
    late int tocadas;
    await _ate(tester, () async {
      _frasesTrazidas(it);
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = true
        ..listeningFixedLine = 'N1';
      final conferidas = it.harness.room.playedByTakeSent.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a conferência',
        () => it.harness.room.playedByTakeSent.length > conferidas,
      );
      await settle();
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      _nadaOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = false
        ..listeningFixedLine = null;
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      linhas = it.harness.voice.fixedLines.length;
      depois = it.harness.room.playedByTakeSent.length;
      final relatos = it.harness.room.listeningReports.length;

      await _ouvirAte(it, desde: 2);
      await waitFor(
        'o relato da última',
        () => it.harness.room.listeningReports.length > relatos,
      );
      tocadas = it.harness.playback.played.length;
      await settle();
    });

    expect(it.harness.voice.fixedLines.skip(linhas), isEmpty);
    expect(it.harness.room.playedByTakeSent.length, depois);
    expect(it.harness.playback.played.length, tocadas);
    expect(it.harness.playback.sounding, isFalse);
    expect(
      find.text(_terminei),
      findsOneWidget,
      reason: 'fora do só ouvir, terminei segue a sua própria regra',
    );
    closeTheRoom(it.container);
  });

  test(
    'after a second listen that stays quiet, terminei asks the room to check '
    'again',
    () async {
      final it = await _juntadaNaCasa();
      _frasesTrazidas(it);
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = true
        ..listeningFixedLine = 'N1';
      final conferidas = it.harness.room.playedByTakeSent.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a conferência',
        () => it.harness.room.playedByTakeSent.length > conferidas,
      );
      await settle();
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      _nadaOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = false
        ..listeningFixedLine = null;
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'o relato da última',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;

      unawaited(it.sala.finishBackTranslation());
      await waitFor('a conferência ser pedida', () => pedidas > 0);

      expect(
        pedidas,
        1,
        reason: 'a escuta quieta deixava terminei sem conferir de novo',
      );
    },
  );

  test(
    'heard whole with nothing translated starts the telling with P1',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      await _ouvirAte(it, desde: 2);

      await waitFor(
        'a primeira voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.voice.fixedLines.skip(linhas), [('P1', testLanguage)]);
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      await _abrirOMicrofone(it);
    },
  );

  testWidgets(
    'a part that fails to play says so, calls nobody, and the next tap plays it '
    'under the same line',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        it.harness.playback.failPlayback();
        await settle();
      });

      expect(find.text(_naoDeuParaConferir), findsOneWidget);
      expect(it.container.read(salaSessionProvider).needsPerson, isFalse);
      final tocadas = it.harness.playback.played.length;
      await tester.tap(byLabel(_tocarOuPausar));
      await _ate(
        tester,
        () => waitFor(
          'a parte tocar de novo',
          () => it.harness.playback.played.length > tocadas,
        ),
      );

      expect(find.text(_naoDeuParaConferir), findsOneWidget);
      expect(it.harness.playback.played.last, it.partes[0].path);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'a part the room still counts unheard after the listen keeps the listen, '
    'and play replays the recording from its first part, not that part alone',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
        final relatos = it.harness.room.listeningReports.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'o relato da última',
          () => it.harness.room.listeningReports.length > relatos,
        );
        await settle();
      });

      expect(find.text(_faltaOuvir), findsOneWidget);
      expect(find.text(_terminei), findsNothing);
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;
      await _ate(tester, () async {
        await it.sala.finishBackTranslation();
        await settle();
      });
      expect(pedidas, 0, reason: 'ainda só ouvir: nenhuma conferência');
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;
      await tester.tap(byLabel(_tocarOuPausar));
      await _ate(
        tester,
        () => waitFor(
          'a gravação tocar de novo',
          () => it.harness.playback.played.length > tocadas,
        ),
      );
      expect(
        it.harness.playback.played.last,
        it.partes[0].path,
        reason: 'o play tocava só a parte que a sala nomeou, fora do contexto',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      expect(
        find.textContaining('ouvindo a gravação de vocês… — parte 1 · '),
        findsOneWidget,
        reason: 'a linha de posição fica sob o aviso',
      );
      await _ate(tester, () => _ouvirAte(it));
      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      closeTheRoom(it.container);
    },
  );

  test(
    'an untranslated refusal naming no part says N2 and opens the telling on the untold ground',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningStretchUntranslated = true;
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      await _ouvirAte(it, desde: 2);

      await waitFor(
        'uma parte voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.voice.fixedLines.skip(linhas), [('N2', testLanguage)]);
      expect(it.harness.playback.played.last, it.partes[0].path);
      await _abrirOMicrofone(it);
    },
  );

  testWidgets(
    'a take the room names that this tablet does not hold keeps the listen',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      late int linhas;
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        it.harness.room.listeningUnheardTakeIds = const ['de-outro-tablet'];
        linhas = it.harness.voice.fixedLines.length;
        final relatos = it.harness.room.listeningReports.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'o relato da última',
          () => it.harness.room.listeningReports.length > relatos,
        );
        await settle();
      });

      expect(it.harness.voice.fixedLines.skip(linhas), isEmpty);
      expect(find.text(_faltaOuvir), findsOneWidget);
      expect(find.text(_terminei), findsNothing);
      final tocadas = it.harness.playback.played.length;
      await tester.tap(byLabel(_tocarOuPausar));
      await _ate(
        tester,
        () => waitFor(
          'a escuta tocar de novo',
          () => it.harness.playback.played.length > tocadas,
        ),
      );
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      closeTheRoom(it.container);
    },
  );

  test(
    'on entry, a take the room names that this tablet does not hold starts the listen with N0 and the whole passage',
    () async {
      final it = await _juntadaNaCasa();
      it.harness.room.listeningUnheardTakeIds = const ['de-outro-tablet'];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;
      final microfones = _microfones(it);

      await _oDisco(it);
      expect(it.harness.voice.fixedLines.skip(linhas), [('N0', testLanguage)]);
      await _ouvirAte(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      expect(
        _microfones(it),
        microfones,
        reason: 'só ouvir: microfone fechado',
      );
    },
  );

  test(
    'heard whole with a frase awaiting its translation goes back to that frase',
    () async {
      final it = await _juntadaNaCasa();
      _frasesTrazidas(it);
      it.harness.room.awaitingSegmentId = 'trazida-2';
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      await _ouvirAte(it, desde: 2);

      await waitFor(
        'a frase voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.voice.fixedLines.skip(linhas), [('N5', testLanguage)]);
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.ranges.last, '4000-10000');
    },
  );

  testWidgets(
    'an answer that never comes writes that a part is still unheard, says nothing, and the play control plays it again',
    (tester) async {
      final it = await _naTela(tester, _juntadaNaCasa);
      late int linhas;
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        it.harness.room.failListeningWith = const NetworkFailed('sem rede');
        linhas = it.harness.voice.fixedLines.length;
        final relatos = it.harness.room.listeningReports.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'o relato da última',
          () => it.harness.room.listeningReports.length > relatos,
        );
        await settle();
      });

      expect(
        find.text(_faltaOuvir),
        findsOneWidget,
        reason:
            'o relato sem resposta deixava a escuta muda, só com o tocar para seguir',
      );
      expect(it.harness.voice.fixedLines.skip(linhas), isEmpty);
      expect(find.text(_soOuvir), findsOneWidget);
      expect(find.text(_terminei), findsNothing);
      final tocadas = it.harness.playback.played.length;
      await tester.tap(byLabel(_tocarOuPausar));
      await _ate(
        tester,
        () => waitFor(
          'a escuta tocar de novo',
          () => it.harness.playback.played.length > tocadas,
        ),
      );
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'an English session whose answer never comes reads her English gap line',
    (tester) async {
      final it = await _naTela(
        tester,
        () => _juntadaNaCasa(numaSala: SalaHarness(lingua: 'en')),
      );
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await _ouvirAte(it, ate: 1);
        it.harness.room.failListeningWith = const NetworkFailed('sem rede');
        final relatos = it.harness.room.listeningReports.length;
        await _ouvirAte(it, desde: 2);
        await waitFor(
          'o relato da última',
          () => it.harness.room.listeningReports.length > relatos,
        );
        await settle();
      });

      expect(
        find.text('there is still a part of the recording to listen to'),
        findsOneWidget,
        reason: 'a sessão em inglês também ficava sem linha nenhuma',
      );
      closeTheRoom(it.container);
    },
  );

  test(
    'a room that closes the listen without naming what is unheard still says a part is left',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      it.harness.room.listeningUnheardTakeIds = null;
      final relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'o relato da última',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();

      expect(
        it.estado.btRecusa,
        CheckRefusal.partUnheard,
        reason:
            'uma sala que respondia sem nomear nada deixava a escuta sem linha',
      );
      expect(it.estado.btSoOuvir, isTrue);
    },
  );

  test(
    'a room that closes the listen with an empty list counts it heard, not a part left',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a P1 dela depois da escuta',
        () => it.harness.voice.fixedLines.last.$1 == 'P1',
      );
      await settle();

      expect(
        it.estado.btRecusa,
        isNull,
        reason:
            'a lista vazia é a sala contando tudo ouvido, não um trecho que falta',
      );
      expect(it.estado.btSoOuvir, isFalse);
    },
  );

  test(
    'after the room names one part unheard, an answer that never comes replays '
    'the recording from its first part, not that part alone',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      final relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'o relato da última',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();
      it.harness.room.failListeningWith = const NetworkFailed('sem rede');
      it.sala.ouvirGravacao();
      await _ouvirAte(it);
      await waitFor(
        'o relato perdido',
        () => it.harness.room.listeningReports.length > relatos + 1,
      );
      await settle();
      final tocadas = it.harness.playback.played.length;

      it.sala.ouvirGravacao();
      await waitFor(
        'a escuta tocar de novo',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.playback.played.last,
        it.partes[0].path,
        reason:
            'sem resposta, o play repetia só a parte que a sala tinha nomeado '
            'antes',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'after a listen of only the unheard parts the room still counts unheard, play '
    'starts again at the last of them and runs to the end, not at the first part',
    () async {
      final it = await _juntadaNaCasa();
      await _ouvirSoAsDuasPrimeiras(
        it,
        antesDoFim: () =>
            it.harness.room.listeningUnheardTakeIds = [it.partes[0].takeId!],
      );
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;

      it.sala.ouvirGravacao();
      await waitFor(
        'a gravação tocar de novo',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(
        it.harness.playback.played.last,
        it.partes[1].path,
        reason:
            'o dela retoma a última parte que a escuta tocou e segue a corrente '
            'até o fim',
      );
      await _ouvirAte(it, desde: 1);

      expect(it.harness.playback.played.skip(tocadas), _caminhos(it, [1, 2]));
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
      ]);
    },
  );

  test(
    'after a listen of only the unheard parts whose answer never comes, play '
    'starts again at the last of them, as when the room names a part',
    () async {
      final it = await _juntadaNaCasa();
      await _ouvirSoAsDuasPrimeiras(
        it,
        antesDoFim: () =>
            it.harness.room.failListeningWith = const NetworkFailed('sem rede'),
      );
      final tocadas = it.harness.playback.played.length;

      it.sala.ouvirGravacao();
      await waitFor(
        'a gravação tocar de novo',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.playback.played.last,
        it.partes[1].path,
        reason:
            'sem resposta, o play voltava à primeira parte da escuta, e o dela '
            'retoma a última',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'the gap line stays through the replay, while the room is asked, and when it '
    'never answers, not only until the last part ends',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a sala responder o fim da escuta',
        () => it.estado.btRecusa == CheckRefusal.partUnheard,
      );

      it.sala.ouvirGravacao();
      await _ouvirAte(it, ate: 1);
      expect(it.estado.btRecusa, CheckRefusal.partUnheard);
      it.harness.room.holdNextListening();
      var relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a sala ser perguntada',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();
      expect(
        it.estado.btRecusa,
        CheckRefusal.partUnheard,
        reason:
            'o aviso sumia no fim da última parte, antes de a sala responder, e '
            'voltava depois',
      );
      it.harness.room.finishHeldListening();
      await settle();

      it.sala.ouvirGravacao();
      await _ouvirAte(it, ate: 1);
      it.harness.room.failListeningWith = const NetworkFailed('sem rede');
      relatos = it.harness.room.listeningReports.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'o relato perdido',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();
      expect(
        it.estado.btRecusa,
        CheckRefusal.partUnheard,
        reason:
            'sem resposta, o aviso sumia, e a sala nunca tinha contado a parte '
            'ouvida',
      );
    },
  );

  test(
    'once the room counts every part heard after the replay, her next line is '
    'said with the gap line gone, not under it',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      it.harness.room.listeningUnheardTakeIds = [it.partes[1].takeId!];
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a sala responder o fim da escuta',
        () => it.estado.btRecusa == CheckRefusal.partUnheard,
      );
      it.sala.ouvirGravacao();
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      CheckRefusal? naTelaDuranteAFala = CheckRefusal.partUnheard;
      it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;

      await _ouvirAte(it, desde: 2);
      await waitFor('a P1', () => it.harness.voice.fixedLines.length > linhas);

      expect(it.harness.voice.fixedLines.skip(linhas), [('P1', testLanguage)]);
      expect(
        naTelaDuranteAFala,
        isNull,
        reason:
            'a P1 era dita com «ainda falta ouvir» na tela, depois de a sala '
            'contar tudo ouvido',
      );
    },
  );

  test(
    'once that replay ran to the end and the room still counts a part unheard, '
    'play starts the recording over from its first part',
    () async {
      final it = await _juntadaNaCasa();
      await _ouvirSoAsDuasPrimeiras(
        it,
        antesDoFim: () =>
            it.harness.room.listeningUnheardTakeIds = [it.partes[0].takeId!],
      );
      final relatos = it.harness.room.listeningReports.length;
      it.sala.ouvirGravacao();
      await _ouvirAte(it, desde: 1);
      await waitFor(
        'a sala responder o fim da segunda escuta',
        () => it.harness.room.listeningReports.length > relatos,
      );
      await settle();
      final tocadas = it.harness.playback.played.length;

      it.sala.ouvirGravacao();
      await waitFor(
        'a gravação tocar de novo',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.playback.played.last,
        it.partes[0].path,
        reason:
            'a corrente já tinha chegado ao fim, e o play voltava à última parte '
            'em vez de recomeçar',
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'while her line after the listen is said, terminei and the circle answer nothing',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.voice.holdNextLine();
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a P1 dela começar',
        () => it.harness.voice.fixedLines.last.$1 == 'P1',
      );
      final microfones = _microfones(it);

      await it.sala.finishBackTranslation();
      it.sala.retroTap();
      await settle();

      expect(pedidas, 0, reason: 'nenhuma conferência por cima da fala');
      expect(_microfones(it), microfones);
      it.harness.voice.finishHeldLine();
      await waitFor(
        'a primeira voltar ao ar',
        () => it.harness.playback.sounding,
      );
      expect(pedidas, 0);
    },
  );

  test(
    'a team that leaves while P1 is said after the listen stays home, and the '
    'telling never starts behind it',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.voice.holdNextLine();
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a P1 dela começar',
        () => it.harness.voice.fixedLines.last.$1 == 'P1',
      );

      it.sala.leaveTheBackTranslation();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      final tocadas = it.harness.playback.played.length;
      it.harness.voice.finishHeldLine();
      await settle();
      await settle();

      expect(it.estado.stage, SalaStage.ensaio);
      expect(
        it.harness.playback.played.length,
        tocadas,
        reason: 'a fala cortada pela saída ainda punha a primeira parte no ar',
      );
      expect(it.estado.btSoOuvir, isFalse);
      expect(it.estado.btPhase, BtPhase.playing);
    },
  );

  test(
    'while N2 is said after the listen, the telling stands but its circle and '
    'terminei wait for her to finish',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[1].takeId!,
            scene: 2,
            from: const Duration(milliseconds: 4000),
          ),
        ];
      it.harness.voice.holdNextLine();
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a N2 dela começar',
        () => it.harness.voice.fixedLines.last.$1 == 'N2',
      );

      expect(
        it.estado.btSoOuvir,
        isFalse,
        reason: 'a tela de só ouvir ficava de pé enquanto a N2 era dita',
      );
      final microfones = _microfones(it);
      unawaited(it.sala.finishBackTranslation());
      it.sala.retroTap();
      await settle();

      expect(pedidas, 0, reason: 'nenhuma conferência por cima da fala');
      expect(_microfones(it), microfones);
      expect(
        it.estado.voice,
        VoiceState.speaking,
        reason: 'o toque no círculo cortava a fala dela no meio',
      );
      final tocadas = it.harness.playback.played.length;
      it.harness.voice.finishHeldLine();
      await waitFor(
        'a segunda voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
    },
  );

  test(
    'while N5 is said after the listen, the telling stands but its circle and '
    'terminei wait for her to finish',
    () async {
      final it = await _juntadaNaCasa();
      _frasesTrazidas(it);
      it.harness.room.awaitingSegmentId = 'trazida-2';
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.voice.holdNextLine();
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a N5 dela começar',
        () => it.harness.voice.fixedLines.last.$1 == 'N5',
      );

      expect(
        it.estado.btSoOuvir,
        isFalse,
        reason: 'a tela de só ouvir ficava de pé enquanto a N5 era dita',
      );
      final microfones = _microfones(it);
      unawaited(it.sala.finishBackTranslation());
      it.sala.retroTap();
      await settle();

      expect(pedidas, 0, reason: 'nenhuma conferência por cima da fala');
      expect(_microfones(it), microfones);
      expect(
        it.estado.voice,
        VoiceState.speaking,
        reason: 'o toque no círculo cortava a fala dela no meio',
      );
      final tocadas = it.harness.playback.played.length;
      it.harness.voice.finishHeldLine();
      await waitFor(
        'a frase voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.playback.ranges.last, '4000-10000');
    },
  );

  test(
    'while N1 is said after the listen, the telling stands and the check waits '
    'for her to finish, then runs once',
    () async {
      final it = await _juntadaNaCasa();
      _frasesTrazidas(it);
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      it.harness.room
        ..listeningAutomaticCheck = true
        ..listeningFixedLine = 'N1';
      it.harness.voice.holdNextLine();
      var pedidas = 0;
      it.harness.room.duranteOVeredito = () => pedidas++;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a N1 dela começar',
        () => it.harness.voice.fixedLines.last.$1 == 'N1',
      );

      expect(
        it.estado.btSoOuvir,
        isFalse,
        reason: 'a tela de só ouvir ficava de pé enquanto a N1 era dita',
      );
      final microfones = _microfones(it);
      unawaited(it.sala.finishBackTranslation());
      it.sala.retroTap();
      await settle();

      expect(pedidas, 0, reason: 'nenhuma conferência por cima da fala');
      expect(_microfones(it), microfones);
      expect(
        it.estado.voice,
        VoiceState.speaking,
        reason: 'o toque no círculo cortava a fala dela no meio',
      );
      it.harness.voice.finishHeldLine();
      await waitFor('a conferência ser pedida', () => pedidas > 0);
      await settle();
      expect(pedidas, 1, reason: 'uma conferência, depois da fala dela');
    },
  );

  test(
    'a recording no join touched is heard whole after P0, then P1 starts the '
    'telling from its first part, not the telling at once',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;

      await _oDisco(it);
      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('P0', testLanguage)],
        reason: 'a gravação sem junção ia direto para a tradução, sem a P0',
      );
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira parte voltar ao ar',
        () => it.harness.playback.played.length == tocadas + 4,
      );

      expect(it.harness.voice.fixedLines.skip(linhas), [
        ('P0', testLanguage),
        ('P1', testLanguage),
      ]);
      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2, 0]),
      );
      expect(it.harness.playback.playedFrom.skip(desde), [
        Duration.zero,
        Duration.zero,
        Duration.zero,
        Duration.zero,
      ]);
      await _abrirOMicrofone(it);
    },
  );

  test(
    'the room that closed the first listen is still heard on a return it can no '
    'longer answer, so the telling waits quiet instead of playing aloud',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira parte voltar ao ar',
        () => it.harness.playback.sounding,
      );
      it.harness.room.failListeningWith = const NetworkFailed('sem rede');
      await traduzirUmTrecho(it, const Duration(seconds: 4));
      it.harness.room.reachable = false;
      it.sala.goEnsaio();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      final tocadas = it.harness.playback.played.length;

      it.sala.startRetro();
      await waitFor(
        'a tradução voltar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            !it.estado.awaitingTheGuide,
      );
      await settle();

      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason:
            'sem a sala, a volta esquecia o que ela disse ao fim da primeira '
            'escuta e tocava a primeira parte em voz alta',
      );
    },
  );

  test(
    'entering the Back-translation with the room unreachable starts the first '
    'listen from the first part, never the telling',
    () async {
      final it = await _juntadaNaCasa();
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      it.harness.room.failListeningWith = const NetworkFailed('sem rede');

      it.sala.startRetro();
      await _ouvirAte(it);
      await settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N0', testLanguage)],
        reason: 'sem resposta da sala, a entrada dizia como traduzir',
      );
      expect(it.estado.btSoOuvir, isTrue);
      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      closeTheRoom(it.container);
    },
  );

  test(
    'a stretch the room last named untranslated is still said and played on a '
    'return it can no longer answer, not left silent',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      final tocadas = it.harness.playback.played.length;
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira voltar ao ar com a P1',
        () => it.harness.playback.played.length > tocadas,
      );
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[1].takeId!,
            scene: 2,
            from: const Duration(milliseconds: 3000),
          ),
        ];
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      await settle();
      final linhas = it.harness.voice.fixedLines.length;

      it.harness.room.reachable = false;
      it.sala.startRetro();
      await settle();
      await settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N2', testLanguage)],
        reason:
            'sem a sala, a volta esquecia o trecho sem tradução e ficava calada',
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(
        it.harness.playback.playedFrom.last,
        const Duration(milliseconds: 3000),
      );
    },
  );

  test(
    'a stretch left untranslated by the frase the room just kept is said and '
    'played on a return it can no longer answer, not left quiet',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira parte voltar ao ar',
        () => it.harness.playback.sounding,
      );
      final antes = it.estado.btTrechos.length;
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 4);
      it.sala.retroTap();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir no trecho',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[0].takeId!,
            scene: 1,
            from: const Duration(seconds: 4),
          ),
        ];
      await confirmarATraducao(it.container);
      await waitFor(
        'o trecho contado entrar no colar',
        () => it.estado.btTrechos.length == antes + 1,
      );
      await settle();
      it.harness.room.reachable = false;
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      await settle();
      final linhas = it.harness.voice.fixedLines.length;

      it.sala.startRetro();
      await settle();
      await settle();

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('N2', testLanguage)],
        reason:
            'a sala só era lembrada pelo último relato, de antes da frase, e a '
            'volta sem rede ficava calada sobre o trecho que faltava traduzir',
      );
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, const Duration(seconds: 4));
    },
  );

  test(
    'a joined recording whose untranslated stretch the room names says the '
    'hint, never the line of a part still to hear under terminei too',
    () async {
      final it = await _juntadaNaCasa();
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 1);
      _tudoOuvido(it);
      await _ouvirAte(it, desde: 2);
      await waitFor(
        'a primeira parte voltar ao ar',
        () => it.harness.playback.sounding,
      );
      final antes = it.estado.btTrechos.length;
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 4);
      it.sala.retroTap();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir no trecho',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      it.harness.room
        ..listeningFixedLine = 'N2'
        ..listeningUntranslated = [
          UntranslatedPart(
            takeId: it.partes[0].takeId!,
            scene: 1,
            from: const Duration(seconds: 4),
          ),
        ];
      await confirmarATraducao(it.container);
      await waitFor(
        'o trecho contado entrar no colar',
        () => it.estado.btTrechos.length == antes + 1,
      );
      await settle();
      it.harness.room.reachable = false;
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      await settle();

      it.sala.startRetro();
      await waitFor(
        'o trecho sem tradução voltar ao ar',
        () =>
            it.estado.btRecusa == CheckRefusal.stretchUntranslated &&
            it.harness.playback.sounding,
      );

      expect(it.estado.btRecusa, CheckRefusal.stretchUntranslated);
      expect(it.estado.btTrechos.where((trecho) => trecho.contado), isNotEmpty);
      expect(it.estado.voice, VoiceState.invite);
      expect(it.estado.canAdvanceToTheVerdict, isFalse);
      expect(
        it.estado.btAindaFaltaOuvir,
        isFalse,
        reason:
            'com o trecho sem tradução nomeado, a linha da parte não ouvida '
            'aparecia junto com a dica dela',
      );
    },
  );

  testWidgets(
    'during the listen of a recording no join touched there is no terminei and '
    'no circle, and her line names the recording, not the passage',
    (tester) async {
      final it = await _naTela(tester, umEnsaioDeTresPartesGravado);
      await _ate(tester, () async {
        _nadaOuvido(it);
        await _oDisco(it);
        await theClipOpens(it.harness);
        it.harness.playback.at = const Duration(seconds: 3);
      });

      expect(
        _oCirculo(),
        findsNothing,
        reason: 'a escuta da gravação sem junção ainda desenhava o círculo',
      );
      expect(it.harness.playback.sounding, isTrue);
      expect(find.text(_terminei), findsNothing);
      expect(
        find.text(_soOuvirAGravacao),
        findsOneWidget,
        reason: 'a gravação sem junção lia a linha da passagem do Ensaio Final',
      );
      expect(find.text(_soOuvir), findsNothing);
      closeTheRoom(it.container);
    },
  );

  test(
    'recomeçar a tradução on a recording no join touched says P1 and plays its '
    'first part, never a new listen',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      it.sala.recomecarATraducao();
      await settle(const Duration(milliseconds: 700));
      it.sala.recomecarATraducao();
      await waitFor(
        'a tradução recomeçar com uma parte no ar',
        () =>
            it.harness.room.restartsAsked.isNotEmpty &&
            it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('P1', testLanguage)],
        reason: 'recomeçar é a P1 e a tradução do começo, sem a P0 de novo',
      );
      expect(it.harness.playback.played.last, it.partes[0].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
    },
  );

  test(
    'coming back to a recording heard whole with nothing told says P1 and plays '
    'its first part, not the telling in silence',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      await _oDisco(it);
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      _tudoOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _oDisco(it);

      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('P1', testLanguage)],
        reason:
            'voltar com tudo ouvido e nada traduzido não dizia como traduzir',
      );
      expect(it.harness.playback.played.skip(tocadas), _caminhos(it, [0]));
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      await _abrirOMicrofone(it);
    },
  );

  test(
    'a recording no join touched that the room still counts unheard after its '
    'listen keeps the listen, with no P1 and no terminei',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;

      await _oDisco(it);
      await _ouvirAte(it);
      await waitFor(
        'a sala responder o fim da escuta',
        () => it.estado.btRecusa == CheckRefusal.partUnheard,
      );
      await settle();

      expect(it.harness.voice.fixedLines.skip(linhas), [('P0', testLanguage)]);
      expect(it.estado.btRecusa, CheckRefusal.partUnheard);
      expect(
        it.estado.canFinishBackTranslation,
        isFalse,
        reason:
            'a escuta acabava com o terminei aceso sem a sala contar a '
            'gravação ouvida',
      );
    },
  );

  test(
    'the first listen of a recording no join touched says nothing is left to '
    'hear, as nothing was heard yet',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      _nadaOuvido(it);
      CheckRefusal? naTelaDuranteAFala = CheckRefusal.partUnheard;
      it.harness.voice.aoFalar = () => naTelaDuranteAFala = it.estado.btRecusa;

      await _oDisco(it);

      expect(
        naTelaDuranteAFala,
        isNull,
        reason:
            'a primeira escuta dizia «ainda falta ouvir um trecho» de uma '
            'gravação que ninguém ouviu ainda',
      );
      expect(it.estado.btRecusa, isNull);
    },
  );

  test(
    'after a relaunch the back translation of a recording no join touched nobody '
    'heard plays P0 and the whole recording, not the telling',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a tradução abrir',
        () =>
            it.estado.stage == SalaStage.retro && it.harness.playback.sounding,
      );
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _reabrir(it);
      it.sala.startRetro();
      await waitFor(
        'a retomada pôr uma parte no ar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.harness.playback.played.length > tocadas,
      );
      expect(it.estado.joined, isFalse);
      expect(
        it.harness.voice.fixedLines.skip(linhas),
        [('P0', testLanguage)],
        reason: 'a retomada caía na tradução sem a gravação ouvida inteira',
      );
      await _ouvirAte(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
    },
  );

  test(
    'a row emptied while P1 is said leaves nothing to put in the air, not a room '
    'taken down',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      await _oDisco(it);
      it.sala.goEnsaio();
      await waitFor('a casa', () => it.estado.stage == SalaStage.ensaio);
      _tudoOuvido(it);
      it.harness.voice.holdNextLine();
      it.sala.startRetro();
      await waitFor(
        'a P1 ser dita',
        () => it.harness.voice.fixedLines.lastOrNull?.$1 == 'P1',
      );
      final tocadas = it.harness.playback.played.length;

      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      it.sala.state = it.estado.copyWith(keptTakes: const []);
      it.harness.voice.finishHeldLine();
      await settle();

      expect(
        it.estado.halt,
        isA<NoHalt>(),
        reason:
            'pedir a primeira parte de uma fileira vazia derrubava a sala '
            'debaixo da equipe',
      );
      expect(it.harness.playback.played.length, tocadas);
    },
  );

  test(
    'after a relaunch the back translation of a joined recording nobody heard '
    'plays the first listen',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a tradução abrir',
        () =>
            it.estado.stage == SalaStage.retro && it.harness.playback.sounding,
      );
      _juntadas(it);
      _nadaOuvido(it);
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;

      await _reabrir(it);
      it.sala.startRetro();
      await waitFor(
        'a retomada pôr uma parte no ar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.harness.playback.played.length > tocadas,
      );
      expect(it.estado.joined, isTrue);
      expect(it.harness.voice.fixedLines.skip(linhas), [('N0', testLanguage)]);
      await _ouvirAte(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        _caminhos(it, [0, 1, 2]),
      );
    },
  );

  testWidgets('her N0 plays in the room language when the room language '
      'changed after the session was opened', (tester) async {
    final it = await _naTela(tester, _juntadaNaCasa);
    it.container.read(roomLanguageProvider.notifier).choose('en');
    await tester.pump();
    final linhas = it.harness.voice.fixedLines.length;
    await _ate(tester, () async {
      _nadaOuvido(it);
      await _oDisco(it);
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = const Duration(seconds: 10)
        ..at = const Duration(seconds: 2);
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(it.harness.voice.fixedLines.skip(linhas), [('N0', 'en')]);
  });

  testWidgets('an English session hears N0 in English and reads her English', (
    tester,
  ) async {
    final it = await _naTela(
      tester,
      () => _juntadaNaCasa(numaSala: SalaHarness(lingua: 'en')),
    );
    final linhas = it.harness.voice.fixedLines.length;
    await _ate(tester, () async {
      _nadaOuvido(it);
      await _oDisco(it);
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = const Duration(seconds: 10)
        ..at = const Duration(seconds: 2);
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(it.harness.voice.fixedLines.skip(linhas), [('N0', 'en')]);
    expect(_oTitulo('Final Rehearsal'), findsOneWidget);
    expect(find.text(_soOuvirEn), findsOneWidget);
    expect(
      find.text('listening to your recording… — part 1 · 0:02 / 0:10'),
      findsOneWidget,
    );
    closeTheRoom(it.container);
  });

  testWidgets('the position line reads the part and its clock', (tester) async {
    final it = await _naTela(tester, _juntadaNaCasa);
    await _ate(tester, () async {
      _nadaOuvido(it);
      await _oDisco(it);
      await _ouvirAte(it, ate: 0);
      await waitFor(
        'a segunda no ar',
        () => it.harness.playback.played.last == it.partes[1].path,
      );
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = const Duration(seconds: 70)
        ..at = const Duration(milliseconds: 41900);
    });
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('ouvindo a gravação de vocês… — parte 2 · 0:41 / 1:10'),
      findsOneWidget,
    );

    await tester.tap(byLabel(_tocarOuPausar));
    await _ate(
      tester,
      () => waitFor('a pausa', () => !it.harness.playback.sounding),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('parte 2 · 0:41 / 1:10'), findsOneWidget);
    closeTheRoom(it.container);
  });

  test(
    'a verdict standing opens no frase to be told again during the first listen',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a tradução abrir',
        () =>
            it.estado.stage == SalaStage.retro && it.harness.playback.sounding,
      );
      _frasesTrazidas(it);
      it.harness.room.retroSoFar = BackTranslationProgress(
        segments: it.harness.room.segments,
        findings: const [
          BtFinding(
            kind: BtFindingKind.addition,
            frase: 1,
            segmentId: 'trazida-1',
          ),
        ],
      );
      _juntadas(it);
      _nadaOuvido(it);
      final tocadas = it.harness.playback.played.length;
      await _reabrir(it);
      it.sala.startRetro();
      await waitFor(
        'a primeira escuta pôr uma parte no ar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.harness.playback.played.length > tocadas,
      );
      expect(
        it.estado.btFindings,
        isNotEmpty,
        reason: 'o cenário só mede alguma coisa com o achado de pé',
      );
      await theClipOpens(it.harness);
      final noAr = it.harness.playback.played.length;
      final microfones = _microfones(it);

      it.sala.traduzirAFraseDeNovo(0);
      it.sala.ouvirOTrechoContado(0);
      await settle();

      expect(it.harness.playback.played.length, noAr);
      expect(it.harness.playback.ranges, isEmpty);
      expect(_microfones(it), microfones);
      expect(it.harness.playback.sounding, isTrue);
    },
  );

  testWidgets('the carried frases show and cannot be tapped', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _naTela(tester, _juntadaNaCasa);
    await _ate(tester, () async {
      _frasesTrazidas(it);
      _nadaOuvido(it);
      await _oDisco(it);
      await theClipOpens(it.harness);
    });
    await tester.pump(const Duration(milliseconds: 100));
    final tocadas = it.harness.playback.played.length;

    final ouvirAPrimeira = find.bySemanticsLabel(
      'ouvir a minha tradução da frase 1',
    );
    expect(ouvirAPrimeira, findsOneWidget);
    expect(
      find.bySemanticsLabel('ouvir a minha tradução da frase 2'),
      findsOneWidget,
    );
    for (final alvo in [
      ouvirAPrimeira,
      find.bySemanticsLabel(RegExp('frase de novo e traduzir de novo — 1')),
    ]) {
      expect(alvo, findsWidgets);
      await tester.ensureVisible(alvo.first);
      await tester.tap(alvo.first, warnIfMissed: false);
      await _ate(tester, () => settle());
    }

    expect(it.harness.playback.played.length, tocadas);
    expect(it.harness.playback.ranges, isEmpty);
    semantics.dispose();
    closeTheRoom(it.container);
  });
}
