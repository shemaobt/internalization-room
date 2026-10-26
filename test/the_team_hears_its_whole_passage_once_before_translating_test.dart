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
import 'package:internalization_room/features/sala/presentation/widgets/stage_heading.dart';
import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, settle;
import 'um_ensaio_de_tres_partes.dart';

const _soOuvir = 'Primeiro, só ouvir: a passagem inteira, do começo ao fim.';
const _soOuvirEn =
    'First, just listen: the whole passage, from beginning to end.';
const _ensaioFinal = 'Ensaio Final';
const _terminei = 'terminei';
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
      partBeingRecordedAgain: value.partBeingRecordedAgain,
      passesToGoAbove: value.passesToGoAbove,
    );
  }
}

Future<void> _reabrir(Sala it) async {
  it.container.dispose();
  it.container = it.harness.container();
  addTearDown(it.container.dispose);
  await it.sala.abrirEscolha();
  await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
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
  for (var vez = 0; vez < 200 && !done(); vez++) {
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
    'during the first listen there is no terminei and the circle and bars do nothing',
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
      await tester.tap(find.byType(FacilitatorCircle).last);
      await _ate(tester, () => settle());
      expect(it.harness.playback.sounding, isTrue);
      expect(_microfones(it), microfones);

      expect(find.bySemanticsLabel('parte 1'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('parte 1').first);
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
        [
          for (final circulo in tester.widgetList<FacilitatorCircle>(
            find.byType(FacilitatorCircle),
          ))
            circulo.halt,
        ],
        everyElement(isA<NoHalt>()),
        reason: 'nenhum sinal de pessoa no círculo',
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
    'a part the room still counts unheard after the listen keeps the listen',
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
      await tester.tap(byLabel(_tocarOuPausar));
      await _ate(
        tester,
        () => waitFor(
          'a segunda tocar de novo',
          () => it.harness.playback.played.length > tocadas,
        ),
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(it.harness.playback.playedFrom.last, Duration.zero);
      expect(
        find.textContaining('ouvindo a gravação de vocês… — parte 2 · '),
        findsOneWidget,
        reason: 'a linha de posição fica sob o aviso',
      );
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
    'on entry, a take the room names that this tablet does not hold starts the listen with P2 and the whole passage',
    () async {
      final it = await _juntadaNaCasa();
      it.harness.room.listeningUnheardTakeIds = const ['de-outro-tablet'];
      final linhas = it.harness.voice.fixedLines.length;
      final tocadas = it.harness.playback.played.length;
      final desde = it.harness.playback.playedFrom.length;
      final microfones = _microfones(it);

      await _oDisco(it);
      expect(it.harness.voice.fixedLines.skip(linhas), [('P2', testLanguage)]);
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
    'an answer that never comes keeps the listen and the play control plays it again',
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

  test(
    'after the room names one part unheard, an answer that never comes plays only that part again',
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
      await _ouvirAte(it, desde: 1, ate: 1);
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

      expect(it.harness.playback.played.last, it.partes[1].path);
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

  test('a recording no join touched keeps today\'s path', () async {
    final it = await umEnsaioDeTresPartesGravado();
    _nadaOuvido(it);
    final linhas = it.harness.voice.fixedLines.length;
    final tocadas = it.harness.playback.played.length;

    await _oDisco(it);

    expect(it.harness.voice.fixedLines.skip(linhas), isEmpty);
    expect(it.harness.playback.played.skip(tocadas), _caminhos(it, [0]));
    expect(it.harness.playback.playedFrom.last, Duration.zero);
    await _abrirOMicrofone(it);
  });

  test(
    'a relaunch on the back translation of a joined recording nobody heard plays the first listen',
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
      it.sala.ouvirAConta(0);
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
      find.bySemanticsLabel('frase 1'),
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
