import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/listen_glyph.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_question.dart';
import 'package:internalization_room/main.dart';
import 'package:path/path.dart' as p;

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, relaunch, voiceOverFocusLeaves;

const _homeLine = 'Gravem, ouçam, e gravem de novo quantas vezes precisarem.';
const _homeLineEn =
    'Record, listen back, and record again as many times as you need.';
const _planLine = 'Estes são os ensaios das cenas que vocês me enviaram.';
const _planLineEn = 'These are the scene rehearsals you sent me.';
const _join = 'juntar as cenas e ouvir';
const _joinEn = 'join the scenes and listen';
const _sceneByScene = 'Gravar cena por cena';
const _back = 'Voltar para a gravação';
const _swap = 'trocar o ensaio desta cena';
const _swapEn = 'use another rehearsal for this scene';
const _useScene = 'usar o ensaio desta cena';
const _useSceneEn = "use this scene's rehearsal";
const _useThis = 'usar este';
const _useThisEn = 'use this one';
const _inUse = '✓ em uso';
const _hearNew = 'ouçam a cena nova antes de conferir';
const _hearNewEn = 'listen to the new scene before the check';
const _listenAndCheck = 'ouvir e conferir o Ensaio Final';
const _cannotEnter = 'este ensaio não pode entrar — ensaiem esta cena de novo';
const _retry = 'não deu para juntar esta cena — toquem para tentar de novo';
const _reopenArmed = 'toquem de novo: isto abre de novo o rascunho aprovado';
const _tick = '✓';
const _recordAgain = 'gravar esta cena de novo';
const _question = 'Qual cena vocês vão ensaiar?';
const _houseBack = 'Voltar para a passagem atual';
const _bringBack = 'trazer de volta as traduções do ensaio desta cena';
const _wholeAtOnce = 'gravar a passagem inteira de uma vez';
const _bringBackArmed =
    'toquem de novo: as traduções do ensaio voltam; as que vocês fizeram aqui '
    'para esta cena ficam guardadas';
const _sceneCircle = [
  'Gravar o ensaio da cena',
  'gravem o ensaio da cena na língua materna; toquem para parar',
  'guardando o ensaio da cena…',
];

const _threeScenes = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

const _threeScenesEn = [
  Scene(sceneId: 'S1', title: 'Famine in Bethlehem'),
  Scene(sceneId: 'S2', title: 'Naomi decides to return'),
  Scene(sceneId: 'S3', title: 'Ruth clings to Naomi'),
];

const _midConversation = Moment(
  at: MomentAt.internalization,
  part: 2,
  parts: 3,
);

const _thePassage = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

final _dot = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      const {
        'Gravar o ensaio de vocês',
        'Abrir o Ensaio Final',
        'Record your rehearsal',
        'Open the Final Rehearsal',
      }.contains(widget.properties.label),
);

final _recordedAt = DateTime.utc(2026, 10, 22, 13, 7);

/// The rehearsals of the passage, by their number: S1a, S2a (scene 2's Default, sent
/// last), S3a, S2b, and the later S2c and S3b.
const _sceneOf = {1: 'S1', 2: 'S2', 3: 'S3', 4: 'S2', 5: 'S2', 6: 'S3'};
const _sentAt = {1: '10:01', 2: '10:05', 3: '10:03', 4: '10:02', 5: '10:00'};
const s1a = 1, s2a = 2, s3a = 3, s2b = 4, s2c = 5, s3b = 6;

Uint8List _bytesOf(int n) =>
    aWavTake(samples: [for (var i = 0; i < 40; i++) n * 100 + i]);

String _fingerprintOf(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

String _clock(DateTime at) {
  final local = at.toLocal();
  return '${'${local.hour}'.padLeft(2, '0')}:'
      '${'${local.minute}'.padLeft(2, '0')}';
}

String _line(int n, {String language = 'pt'}) => language == 'pt'
    ? 'ensaio $n · ${_clock(_recordedAt)} · 0:06 · 2 frases · enviado'
    : 'rehearsal $n · ${_clock(_recordedAt)} · 0:06 · 2 sentences · sent';

String _unsentLine(int n) =>
    'ensaio $n · ${_clock(_recordedAt)} · 0:06 · 2 frases · não enviado';

class _Room {
  final WidgetTester tester;
  SalaHarness harness;
  ProviderContainer container;
  final List<Scene> scenes;

  _Room(this.tester, this.harness, this.container, this.scenes);

  FakeRoom get room => harness.room;

  String get sessionId => container.read(salaSessionProvider).sessionId!;

  String idOf(int n) => '$sessionId-ensaio-$n';

  bool get english => identical(scenes, _threeScenesEn);

  SceneRehearsalRecord rehearsal(
    int n, {
    bool sent = true,
    String contentType = 'audio/wav',
  }) => SceneRehearsalRecord(
    rehearsalId: idOf(n),
    sessionId: sessionId,
    n: n,
    scene: _sceneOf[n],
    recordedAt: _recordedAt,
    sentAt: sent ? '2026-10-22T${_sentAt[n] ?? '10:09'}:00+00:00' : null,
    durationMs: 6000,
    frases: const [
      SceneFrase(fraseId: 'frase-a', startsMs: 0, endsMs: 3000),
      SceneFrase(fraseId: 'frase-b', startsMs: 3000, endsMs: 6000),
    ],
    contentType: contentType,
    verified: true,
    sha256: _fingerprintOf(_bytesOf(n)),
  );

  Future<void> beat([Duration ahead = Duration.zero]) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(ahead);
  }

  Future<void> until(String what, bool Function() done) async {
    final waited = Stopwatch()..start();
    for (
      var vez = 0;
      !done() && (vez < 200 || waited.elapsed < const Duration(seconds: 30));
      vez++
    ) {
      await beat(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue, reason: what);
  }

  Future<void> within(Duration span, String what, bool Function() done) async {
    final waited = Stopwatch()..start();
    for (var passed = Duration.zero; passed < span && !done();) {
      await beat(const Duration(milliseconds: 100));
      passed += const Duration(milliseconds: 100);
    }
    while (!done() && waited.elapsed < const Duration(seconds: 30)) {
      await beat();
    }
    expect(done(), isTrue, reason: what);
  }

  Future<void> wait(Duration span) async {
    for (var passed = Duration.zero; passed < span;) {
      final step = span - passed < const Duration(milliseconds: 100)
          ? span - passed
          : const Duration(milliseconds: 100);
      await beat(step);
      passed += step;
    }
  }

  Future<void> settle() async {
    for (var vez = 0; vez < 15; vez++) {
      await beat(const Duration(milliseconds: 100));
    }
  }

  void list(
    Iterable<int> ns, {
    bool sent = true,
    String contentType = 'audio/wav',
  }) {
    for (final n in ns) {
      room.sceneRehearsals.add(
        rehearsal(n, sent: sent, contentType: contentType),
      );
      room.sceneAudioOf[idOf(n)] = _bytesOf(n);
    }
  }

  Future<void> held(Iterable<int> ns) async {
    for (final n in ns) {
      await tester.runAsync(
        () => harness.recorder.keepBytes(
          Uint8List.fromList(_bytesOf(n)),
          'cena-${idOf(n)}',
        ),
      );
    }
  }

  Future<void> openThePlan() async {
    await tester.tap(_dot);
    await until(
      'o plano ou a casa abrir',
      () => [
        _planLine,
        _homeLine,
        _planLineEn,
        _homeLineEn,
      ].any((line) => find.text(line).evaluate().isNotEmpty),
    );
    await settle();
  }

  bool _arrived = false;

  void holdTheTake(String scope) {
    _arrived = false;
    room.holdNextTake(scope);
    unawaited(room.untilTakeHeld().then((_) => _arrived = true));
  }

  Future<void> theHeldTakeArrives() =>
      until('a troca chegar à porta', () => _arrived);

  Future<void> theOutboxLetsGoOf(int n) async {
    for (var vez = 0; vez < 200; vez++) {
      final rows = await tester.runAsync(harness.takes.pending);
      if (!rows!.any((row) => row.origin == idOf(n))) return;
      await beat(const Duration(milliseconds: 20));
    }
    fail('o Outbox ainda guarda a troca');
  }

  bool showsTheHome() =>
      find.text(english ? _homeLineEn : _homeLine).evaluate().isNotEmpty &&
      byLabel(english ? 'Back to recording' : _back).evaluate().isEmpty;

  bool showsTheSheet() =>
      byLabel(english ? 'Back to recording' : _back).evaluate().isNotEmpty;

  /// Rehearsals S1a, S2a, S2b and S3a listed and held, the plan's join ended, and the
  /// team back on the recording home from the Back-translation it opens.
  Future<void> joined({
    Iterable<int> listed = const [s1a, s2a, s3a, s2b],
    Iterable<int>? onTheTablet,
  }) async {
    list(listed);
    await held(onTheTablet ?? listed);
    await openThePlan();
    final join = byLabel(english ? _joinEn : _join);
    await tester.ensureVisible(join);
    await tester.pump();
    await tester.tap(join);
    await beat();
    await joinEnds();
  }

  /// The join's end, and the team back on the recording home from the Back-translation
  /// it opens when every scene has its part.
  Future<void> joinEnds() async {
    await until('a junta terminar', () {
      final estado = container.read(salaSessionProvider);
      return estado.joining == null &&
          (estado.stage == SalaStage.retro || showsTheHome());
    });
    if (container.read(salaSessionProvider).stage == SalaStage.retro) {
      container.read(salaSessionProvider.notifier).goEnsaio();
    }
    await until('a casa voltar', showsTheHome);
    await settle();
  }

  Finder row(int n) =>
      byLabel('${english ? 'Scene' : 'Cena'} $n — ${scenes[n - 1].title}');

  Finder onRow(int n, Finder target) =>
      find.descendant(of: row(n), matching: target);

  bool ticked(int n) => onRow(n, find.text(_tick)).evaluate().isNotEmpty;

  Finder door(int n, String label) =>
      byLabel('$label — ${english ? 'Scene' : 'Cena'} $n');

  Future<void> tapThe(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await beat();
  }

  Future<void> openTheSheet(int n, String label) async {
    await tapThe(door(n, label));
    await until('a folha da cena $n abrir', showsTheSheet);
  }

  Finder line(int n) => byLabel(_line(n, language: english ? 'en' : 'pt'));

  Finder toldFrase(int n) => byLabel('ouvir a minha tradução da frase $n');

  Finder onLine(int n, Finder target) =>
      find.descendant(of: line(n), matching: target);

  Finder use(int n, [String label = _useThis]) =>
      byLabel('$label — ${_line(n, language: english ? 'en' : 'pt')}');

  Finder useUnsent(int n) => byLabel('$_useThis — ${_unsentLine(n)}');

  Finder listen(int n) => byLabel(
    '${english ? 'Listen' : 'Ouvir'} — ${_line(n, language: english ? 'en' : 'pt')}',
  );

  Finder paintedOn(Finder control) => find.descendant(
    of: control,
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ListenGlyphPainter,
    ),
  );

  ListenGlyph glyphOn(Finder control) =>
      (tester.widget<CustomPaint>(paintedOn(control)).painter!
              as ListenGlyphPainter)
          .glyph;

  Tristate pressed(Finder control) => tester
      .getSemantics(control)
      .getSemanticsData()
      .flagsCollection
      .isSelected;

  bool enabled(Finder target) =>
      tester
          .getSemantics(target)
          .getSemanticsData()
          .flagsCollection
          .isEnabled !=
      Tristate.isFalse;

  /// «usar este» on rehearsal [n] twice, the second once the armed control woke.
  Future<void> swapIn(int n) async {
    await tapThe(use(n));
    await wait(const Duration(milliseconds: 700));
    await tapThe(use(n));
  }

  Future<void> swapLands() async {
    await until('a troca voltar para a casa', showsTheHome);
    await settle();
  }

  List<
    ({
      int? chunkIndex,
      String? origin,
      bool reopens,
      String? sha256,
      Uint8List bytes,
      String? overTake,
    })
  >
  received(int n) => [
    for (final take in room.takesReceivedWhole)
      if (take.kind == 'ensaio' && take.scope == 'parte-$n')
        (
          chunkIndex: take.chunkIndex,
          origin: take.origin,
          reopens: take.reopens,
          sha256: take.sha256,
          bytes: take.bytes,
          overTake: take.overTake,
        ),
  ];

  String? partPath(int n) => container
      .read(salaSessionProvider)
      .partes
      .where((take) => take.scopeId == 'parte-$n')
      .singleOrNull
      ?.path;

  List<TakeView> takesOf(int n) => [
    for (final take in room.takes)
      if (take.kind == 'ensaio' && take.ordinal == n) take,
  ];

  Future<void> relaunchOnTheHome() async {
    await relaunchOnTheConversation();
    container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
    await until('a casa voltar depois do relançamento', showsTheHome);
    await settle();
  }

  Future<void> relaunchOnTheConversation() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    var stopped = false;
    unawaited(harness.takes.writingEnds().then((_) => stopped = true));
    await until('a vida antiga parar de escrever', () => stopped);
    late SalaHarness again;
    late ProviderContainer next;
    await tester.runAsync(() async {
      (again, next) = await relaunch(harness, container);
      next.read(salaSessionProvider);
    });
    harness = again;
    container = next;
    await tester.pumpWidget(
      UncontrolledProviderScope(container: next, child: const SalaApp()),
    );
    await until('a conversa voltar depois do relançamento', () {
      final state = container.read(salaSessionProvider);
      return state.station is Canvas && !state.awaitingTheGuide;
    });
    await settle();
  }

  Future<void> recordAgainAndKeep(int n) async {
    await tapThe(
      onRow(n, byLabel(english ? 'Record again' : 'Gravar de novo')),
    );
    await until(
      'a cena $n gravar',
      () => onRow(n, byLabel(english ? 'Stop' : 'Parar')).evaluate().isNotEmpty,
    );
    await wait(const Duration(seconds: 2));
    await tapThe(onRow(n, byLabel(english ? 'Stop' : 'Parar')));
    await until(
      'a gravação ficar à espera do check',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    await tapThe(byLabel(english ? 'Send the recording' : 'Enviar a gravação'));
    await settle();
  }
}

Future<void> _toTheConversation(_Room it) async {
  final notifier = it.container.read(salaSessionProvider.notifier);
  await it.settle();
  unawaited(notifier.abrirEscolha());
  await it.settle();
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await it.until(
    'a conversa abrir',
    () =>
        it.container.read(salaSessionProvider).voice == VoiceState.invite &&
        !it.container.read(salaSessionProvider).awaitingTheGuide,
  );
  await it.wait(const Duration(milliseconds: 1500));
}

Future<_Room> _atRest(
  WidgetTester tester, {
  String lingua = 'pt',
  List<Scene> scenes = _threeScenes,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final home = aTempHome('sala-1407-troca');
  final harness = SalaHarness(lingua: lingua, takesHome: home)
    ..room.passages = const [_thePassage]
    ..room.nextMoment = _midConversation
    ..room.passageScenes = scenes;
  final container = (await tester.runAsync(
    () async => harness.container()..read(salaSessionProvider),
  ))!;
  final it = _Room(tester, harness, container, scenes);
  addTearDown(() => it.container.dispose());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await _toTheConversation(it);
  return it;
}

void main() {
  testWidgets(
    'after joining three scenes every row shows its tick, and the disc reads '
    '«ouvir e conferir o Ensaio Final»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      for (final n in [1, 2, 3]) {
        expect(it.ticked(n), isTrue, reason: 'a cena $n tem a sua parte');
        expect(tester.getSemantics(it.row(n)).value, _tick);
        expect(
          it.onRow(n, find.textContaining(RegExp(r'ensaio \d'))),
          findsNothing,
        );
      }
      expect(byLabel(_listenAndCheck), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a joined row with another rehearsal offers «trocar o ensaio desta cena», '
    'and only that row',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      expect(it.door(2, _swap), findsOneWidget);
      for (final n in [1, 3]) {
        expect(it.door(n, _swap), findsNothing, reason: 'cena $n');
        expect(it.door(n, _useScene), findsNothing, reason: 'cena $n');
      }
      semantics.dispose();
    },
  );

  testWidgets(
    '«usar este» on rehearsal S2b swaps scene 2, asks for a new listen, and '
    'keeps the old take',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final before = it.received(2).length;

      await it.openTheSheet(2, _swap);
      expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);
      expect(it.use(s2b), findsOneWidget);

      await it.tapThe(it.use(s2b));
      expect(
        it.use(s2b),
        findsOneWidget,
        reason: 'armada, a linha ainda diz «usar este»',
      );
      expect(it.enabled(it.use(s2b)), isFalse, reason: 'armada e esmaecida');
      await it.wait(const Duration(seconds: 1));
      expect(it.received(2), hasLength(before), reason: 'um toque só arma');
      expect(it.enabled(it.use(s2b)), isTrue, reason: 'acordada, sem troca');

      await it.tapThe(it.use(s2b));
      await it.swapLands();

      final sent = it.received(2).skip(before).single;
      expect(sent.chunkIndex, 2);
      expect(sent.origin, it.idOf(s2b));
      expect(sent.bytes, _bytesOf(s2b));
      expect(sent.sha256, _fingerprintOf(_bytesOf(s2b)));
      expect(
        [for (final take in it.takesOf(2)) (take.origin, take.pass)],
        [(it.idOf(s2a), 1), (it.idOf(s2b), 2)],
        reason: 'a gravação que a troca substitui fica na sala',
      );
      expect(it.ticked(2), isTrue);
      expect(find.text(_hearNew), findsOneWidget);

      await it.openTheSheet(2, _swap);
      expect(it.onLine(s2b, find.text(_inUse)), findsOneWidget);
      expect(it.use(s2a), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'an armed «usar este» is announced as pressed, and at rest as not '
    'pressed, as her aria-pressed',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);

      expect(
        tester.getSemantics(it.use(s2b)),
        isSemantics(hasToggledState: true, isToggled: false),
        reason: '«usar este» em repouso não carregava o estado de pressionado',
      );
      await it.tapThe(it.use(s2b));
      expect(
        tester.getSemantics(it.use(s2b)),
        isSemantics(hasToggledState: true, isToggled: true),
        reason:
            'armado, «usar este» só mudava de cor: o VoiceOver não ouvia o '
            'primeiro toque armar',
      );
      expect(
        it.enabled(it.use(s2b)),
        isFalse,
        reason: 'acordando, desabilitado',
      );
      await it.wait(const Duration(seconds: 1));
      expect(
        tester.getSemantics(it.use(s2b)),
        isSemantics(hasToggledState: true, isToggled: true),
        reason: 'acordado, segue pressionado até o segundo toque',
      );
      await it.wait(const Duration(seconds: 7));
      expect(
        tester.getSemantics(it.use(s2b)),
        isSemantics(hasToggledState: true, isToggled: false),
        reason: 'caducado, volta a não pressionado',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a joined row whose only other rehearsal is unsent offers «trocar», and '
    '«usar este» swaps it in',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s2b], sent: false);
      await it.joined(
        listed: const [s1a, s2a, s3a],
        onTheTablet: const [s1a, s2a, s3a, s2b],
      );
      final before = it.received(2).length;

      expect(
        it.door(2, _swap),
        findsOneWidget,
        reason: 'a casa não oferecia trocar pelo ensaio não enviado',
      );
      await it.openTheSheet(2, _swap);
      expect(it.useUnsent(s2b), findsOneWidget);
      await it.tapThe(it.useUnsent(s2b));
      await it.wait(const Duration(milliseconds: 700));
      await it.tapThe(it.useUnsent(s2b));
      await it.swapLands();

      final sent = it.received(2).skip(before).single;
      expect(sent.origin, it.idOf(s2b));
      expect(sent.bytes, _bytesOf(s2b));
      semantics.dispose();
    },
  );

  testWidgets(
    'a joined row whose only other rehearsal is no WAV still offers «trocar», '
    'and its sheet says that one cannot enter',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s2b], contentType: 'audio/mp4');
      await it.joined(listed: const [s1a, s2a, s3a]);

      expect(
        it.door(2, _swap),
        findsOneWidget,
        reason: 'a dela oferece trocar sempre que a cena tem outro ensaio',
      );
      await it.openTheSheet(2, _swap);
      expect(it.line(s2b), findsOneWidget);
      expect(it.onLine(s2b, find.text(_cannotEnter)), findsOneWidget);
      expect(it.use(s2b), findsNothing);
      expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'an unsent rehearsal that is no WAV is listed as one that cannot enter, '
    'not as a silent line',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s2b], sent: false, contentType: 'audio/mp4');
      await it.joined(listed: const [s1a, s2a, s3a]);

      await it.openTheSheet(2, _swap);
      final unsent = byLabel(_unsentLine(s2b));
      expect(unsent, findsOneWidget);
      expect(
        find.descendant(of: unsent, matching: find.text(_cannotEnter)),
        findsOneWidget,
        reason: 'a linha não enviada que não é WAV não dizia nada',
      );
      expect(it.useUnsent(s2b), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'swapping scene 2 back to its first rehearsal leaves three takes for it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.swapLands();
      await it.openTheSheet(2, _swap);
      await it.swapIn(s2a);
      await it.swapLands();

      final takes = it.takesOf(2);
      expect(
        [for (final take in takes) (take.origin, take.pass)],
        [(it.idOf(s2a), 1), (it.idOf(s2b), 2), (it.idOf(s2a), 3)],
      );
      expect({for (final take in takes) take.takeId}, hasLength(3));
      await it.openTheSheet(2, _swap);
      expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'after a swap the old frase of scene 2 leaves the check while scenes 1 and 3 '
    'keep theirs, on the tablet\'s own telling',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final told = [
        for (final n in [1, 2, 3])
          SegmentView(
            segmentId: 'trecho-$n',
            takeId: it.takesOf(n).single.takeId,
            startsMs: 0,
            endsMs: 6000,
            frase: n,
          ),
      ];
      it.room.retroSoFar = BackTranslationProgress(segments: told);
      await it.tapThe(byLabel(_listenAndCheck));
      await it.settle();
      await it.relaunchOnTheHome();
      await it.tapThe(byLabel(_listenAndCheck));
      await it.until(
        'a retrotradução voltar',
        () => it.container.read(salaSessionProvider).station is Retro,
      );
      await it.settle();
      for (final n in [1, 2, 3]) {
        expect(it.toldFrase(n), findsOneWidget, reason: 'a frase $n contada');
      }
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until('a casa voltar', it.showsTheHome);
      await it.settle();

      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.swapLands();
      it.room.reachable = false;
      await it.tapThe(byLabel(_listenAndCheck));
      await it.settle();

      expect(it.toldFrase(1), findsOneWidget);
      expect(
        [
          for (final trecho in it.container.read(salaSessionProvider).btTrechos)
            trecho.segmentId,
        ],
        isNot(contains('trecho-2')),
        reason: 'a frase da gravação trocada',
      );
      expect(
        find.text('regravada — traduzam de novo'),
        findsOneWidget,
        reason:
            'a frase da gravação trocada fica na lista marcada como regravada, '
            'como na dela',
      );
      expect(it.toldFrase(3), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'after a swap the scene counts as unheard, even when the rehearsal it brings '
    'was heard before',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final firstPart = it.harness.emAberto.rows.values.last.takes
          .where((take) => take.scopeId == 'parte-2')
          .single
          .path;

      final heardTake = it.takesOf(2).single.takeId;
      await it.tapThe(byLabel(_listenAndCheck));
      await it.settle();
      for (var vez = 0; vez < 3; vez++) {
        it.harness.playback
          ..length = const Duration(seconds: 6)
          ..at = const Duration(seconds: 6)
          ..finishPlayback();
        await it.settle();
      }
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until('a casa voltar', it.showsTheHome);
      await it.settle();
      expect(
        _heard(it, 0, heardTake),
        isNotEmpty,
        reason: 'a escuta da primeira S2a foi relatada',
      );

      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.swapLands();
      await it.openTheSheet(2, _swap);
      await it.swapIn(s2a);
      await it.swapLands();

      final part = it.harness.emAberto.rows.values.last.takes
          .where((take) => take.scopeId == 'parte-2')
          .single;
      expect(part.path, isNot(firstPart), reason: 'um arquivo novo da parte');
      expect(part.takeId, isNotNull, reason: 'a parte nova tem o nome da sala');
      final reportsBefore = it.room.listeningReports.length;
      it.container.read(salaSessionProvider.notifier).theAppWentAway();
      await it.settle();
      expect(
        _heard(it, reportsBefore, part.takeId),
        isEmpty,
        reason: 'a escuta da primeira S2a não conta para a parte nova',
      );
      semantics.dispose();
    },
  );

  group('over an approved draft', () {
    testWidgets(
      'a swap refused as DRAFT_APPROVED says to try again, changes nothing, and '
      'its next tap arms',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await _atRest(tester);
        await it.joined();
        it.room
          ..approvedDraft = const ApprovedDraft(version: 1)
          ..takeAnswersFirst.add(const Refused('DRAFT_APPROVED'));
        final before = it.received(2).length;

        await it.openTheSheet(2, _swap);
        await it.swapIn(s2b);
        await it.until(
          'a linha dizer para tentar de novo',
          () => it.onLine(s2b, find.text(_retry)).evaluate().isNotEmpty,
        );
        await it.settle();
        expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);
        expect(it.received(2), hasLength(before));

        await it.tapThe(it.use(s2b));
        expect(it.use(s2b, _reopenArmed), findsOneWidget);
        await it.wait(const Duration(seconds: 7));
        expect(it.received(2), hasLength(before));
        expect(it.use(s2b), findsOneWidget, reason: 'o toque armado caducou');
        semantics.dispose();
      },
    );

    testWidgets(
      'VoiceOver focus leaving the armed «usar este» disarms it, and the next '
      'tap only arms',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await _atRest(tester);
        await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
        it.room.approvedDraft = const ApprovedDraft(version: 1);
        await it.relaunchOnTheHome();
        final before = it.received(2).length;
        await it.openTheSheet(2, _swap);
        await it.tapThe(it.use(s2b));
        await it.wait(const Duration(seconds: 1));
        expect(it.use(s2b, _reopenArmed), findsOneWidget);

        voiceOverFocusLeaves(tester, it.use(s2b, _reopenArmed));
        await it.wait(const Duration(milliseconds: 100));

        expect(
          it.use(s2b),
          findsOneWidget,
          reason: 'o usar este seguia armado depois que o foco saiu dele',
        );
        expect(it.use(s2b, _reopenArmed), findsNothing);

        await it.tapThe(it.use(s2b));
        await it.wait(const Duration(seconds: 1));

        expect(it.use(s2b, _reopenArmed), findsOneWidget);
        expect(
          it.received(2),
          hasLength(before),
          reason: 'o toque seguinte trocava o ensaio em vez de só armar',
        );
        await it.wait(const Duration(seconds: 7));
        semantics.dispose();
      },
    );

    testWidgets(
      '«usar este» takes the armed tap with her words, one line armed at a '
      'time, and its row carries the reopening',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final it = await _atRest(tester);
        await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
        it.room.approvedDraft = const ApprovedDraft(version: 1);
        await it.relaunchOnTheHome();
        final before = it.received(2).length;

        await it.openTheSheet(2, _swap);
        await it.tapThe(it.use(s2b));
        expect(it.use(s2b, _reopenArmed), findsOneWidget);
        await it.wait(const Duration(seconds: 1));
        expect(it.received(2), hasLength(before), reason: 'o toque só arma');

        await it.tapThe(it.use(s2c));
        expect(
          it.use(s2c, _reopenArmed),
          findsOneWidget,
          reason: 'armar outra linha arma só aquela',
        );
        expect(it.use(s2b), findsOneWidget);

        await it.wait(const Duration(milliseconds: 300));
        await it.tapThe(it.use(s2c, _reopenArmed));
        expect(it.received(2), hasLength(before), reason: 'aos 0,3 s nada');

        await it.wait(const Duration(milliseconds: 400));
        await it.tapThe(it.use(s2c, _reopenArmed));
        await it.swapLands();

        final sent = it.received(2).skip(before).single;
        expect(sent.origin, it.idOf(s2c));
        expect(sent.reopens, isTrue);
        semantics.dispose();
      },
    );
  });

  testWidgets(
    '«usar o ensaio desta cena» on a row with no part takes one tap',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.room.rehearsalsGone.add(it.idOf(s3a));
      await it.joined(onTheTablet: const [s1a, s2a, s2b]);
      it.room.sceneAudioOf.remove(it.idOf(s3a));
      expect(it.partPath(3), isNull, reason: 'a cena 3 não entrou na junta');

      it.list(const [s3b]);
      await it.held(const [s3b]);
      await it.relaunchOnTheConversation();
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until('a casa voltar', it.showsTheHome);
      await it.settle();

      expect(it.door(3, _useScene), findsOneWidget);
      await it.openTheSheet(3, _useScene);
      expect(find.text(_useScene), findsOneWidget, reason: 'o subtítulo');
      await it.tapThe(it.use(s3b));
      await it.swapLands();

      final sent = it.received(3).single;
      expect(sent.origin, it.idOf(s3b));
      expect(it.takesOf(3).single.pass, 1);
      expect(it.ticked(3), isTrue);
      semantics.dispose();
    },
  );

  testWidgets(
    'a row with no part whose only rehearsal is unsent offers «usar o ensaio '
    'desta cena», and «usar este» sends it as the part',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s3a], sent: false);
      await it.joined(
        listed: const [s1a, s2a, s2b],
        onTheTablet: const [s1a, s2a, s2b, s3a],
      );
      expect(it.partPath(3), isNull, reason: 'a cena 3 não entrou na junta');

      expect(
        it.door(3, _useScene),
        findsOneWidget,
        reason: 'a casa não oferecia o ensaio não enviado da cena',
      );
      await it.openTheSheet(3, _useScene);
      expect(it.useUnsent(s3a), findsOneWidget);
      await it.tapThe(it.useUnsent(s3a));
      await it.swapLands();

      final sent = it.received(3).single;
      expect(sent.origin, it.idOf(s3a));
      expect(sent.bytes, _bytesOf(s3a));
      expect(it.ticked(3), isTrue);
      semantics.dispose();
    },
  );

  testWidgets(
    'recording a joined scene again records a plain part, and the row offers '
    '«usar o ensaio desta cena»',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final before = it.received(2).length;

      await it.recordAgainAndKeep(2);
      await it.until(
        'a gravação chegar à sala',
        () => it.received(2).length > before,
      );

      expect(it.received(2).last.origin, isNull);
      await it.within(
        const Duration(seconds: 20),
        'a cena 2 oferecer «usar o ensaio desta cena»',
        () => it.door(2, _useScene).evaluate().isNotEmpty,
      );
      expect(it.door(2, _swap), findsNothing);
      expect(it.ticked(2), isTrue, reason: 'a cena ainda tem a sua parte');
      semantics.dispose();
    },
  );

  testWidgets(
    'a hand-recorded part with a rehearsal takes two taps to be replaced, and '
    'the hand take is kept',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s1a]);
      await it.held(const [s1a]);
      await it.openThePlan();
      await it.tapThe(find.text(_sceneByScene));
      await it.until('a casa abrir', it.showsTheHome);
      await it.settle();
      await it.tapThe(it.onRow(1, byLabel('Gravar')));
      await it.wait(const Duration(seconds: 2));
      await it.tapThe(it.onRow(1, byLabel('Parar')));
      await it.until(
        'a gravação ficar à espera do check',
        () =>
            it.container.read(salaSessionProvider).ensaio ==
            EnsaioStatus.recorded,
      );
      await it.tapThe(byLabel('Enviar a gravação'));
      await it.until('a parte 1 chegar à sala', () => it.takesOf(1).isNotEmpty);
      await it.within(
        const Duration(seconds: 20),
        'a cena 1 oferecer «usar o ensaio desta cena»',
        () => it.door(1, _useScene).evaluate().isNotEmpty,
      );
      await it.openTheSheet(1, _useScene);
      await it.tapThe(it.use(s1a));
      expect(it.use(s1a), findsOneWidget, reason: 'armada, o próprio rótulo');
      expect(it.enabled(it.use(s1a)), isFalse);
      await it.wait(const Duration(seconds: 1));
      expect(it.received(1).where((take) => take.origin != null), isEmpty);
      expect(it.enabled(it.use(s1a)), isTrue, reason: 'acordada, sem troca');
      await it.tapThe(it.use(s1a));
      await it.swapLands();

      expect(
        [for (final take in it.takesOf(1)) take.origin],
        [null, it.idOf(s1a)],
      );
      semantics.dispose();
    },
  );

  testWidgets('a row whose take is still unsent offers no sheet door', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    await it.joined();
    expect(it.door(2, _swap), findsOneWidget);
    it.room.unreachableTake = 'ensaio/parte-2';

    await it.recordAgainAndKeep(2);
    await it.until(
      'a gravação da cena 2 ficar por enviar',
      () => it.container.read(salaSessionProvider).unsentParts[2] != null,
    );
    await it.settle();

    expect(it.door(2, _swap), findsNothing);
    expect(it.door(2, _useScene), findsNothing);
    semantics.dispose();
  });

  testWidgets('the whole passage\'s home offers no scene\'s rehearsal', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    it.list(const [s1a, s2a, s3a]);
    await it.held(const [s1a, s2a, s3a]);
    await it.openThePlan();
    await it.tapThe(find.text('gravar a passagem inteira de uma vez'));
    await it.until('a casa da passagem inteira abrir', it.showsTheHome);
    await it.settle();

    expect(find.text('A passagem inteira'), findsOneWidget);
    expect(find.text(_useScene), findsNothing);
    expect(find.text(_swap), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'a swap whose rehearsal cannot enter says so and changes nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s1a, s2a, s3a]);
      await it.held(const [s1a, s2a, s3a]);
      it.room.sceneRehearsals.add(it.rehearsal(s2b));
      it.room.rehearsalsGone.add(it.idOf(s2b));
      await it.openThePlan();
      await it.tapThe(byLabel(_join));
      await it.joinEnds();
      final before = it.received(2).length;

      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.until(
        'a linha dizer que não pode entrar',
        () => it.onLine(s2b, find.text(_cannotEnter)).evaluate().isNotEmpty,
      );
      await it.settle();

      expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);
      expect(it.received(2), hasLength(before));
      await it.tapThe(byLabel(_back));
      expect(find.text(_hearNew), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the answer to the last try is said after «usar este», on the actions '
    'line, not under the facts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));

      final said = it.onLine(s2b, find.text(_retry));
      expect(said, findsOneWidget);
      final answer = tester.getRect(said);
      final pill = tester.getRect(it.use(s2b));
      expect(
        answer.top,
        greaterThanOrEqualTo(tester.getRect(it.listen(s2b)).bottom),
        reason: 'a resposta da troca vinha sob os fatos, longe do botão',
      );
      expect(
        answer.top >= pill.bottom || answer.left >= pill.right,
        isTrue,
        reason: 'a resposta vinha antes de «usar este»',
      );
      expect(
        tester
            .getSemantics(said)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      it.room.finishHeldTake();
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap with no answer for 70 s says to try again, changes nothing, and '
    'leaves nothing to land later',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 69));
      expect(it.onLine(s2b, find.text(_retry)), findsNothing);
      await it.wait(const Duration(seconds: 2));
      expect(it.onLine(s2b, find.text(_retry)), findsOneWidget);
      expect(it.onLine(s2a, find.text(_inUse)), findsOneWidget);

      await it.tapThe(byLabel(_back));
      it.room
        ..takeAnswersFirst.add(const NetworkFailed('sem rede'))
        ..finishHeldTake();
      await it.settle();
      await it.theOutboxLetsGoOf(s2b);
      await it.relaunchOnTheHome();
      await it.wait(const Duration(seconds: 5));
      expect(
        it.received(2).where((take) => take.origin == it.idOf(s2b)),
        isEmpty,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap given up at 70 s leaves the Outbox while its request is still in '
    'the air, and a relaunch then sends nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));
      expect(it.onLine(s2b, find.text(_retry)), findsOneWidget);
      final asked = it.room.takesAsked.length;

      await it.theOutboxLetsGoOf(s2b);
      await it.tapThe(byLabel(_back));
      await it.relaunchOnTheHome();
      await it.wait(const Duration(seconds: 5));

      expect(it.room.takesAsked.skip(asked), isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap given up while its request is in the air leaves no copy without '
    'a row after a relaunch',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));
      await it.theOutboxLetsGoOf(s2b);
      await it.relaunchOnTheHome();
      await it.wait(const Duration(seconds: 5));

      final named = {
        for (final row in (await tester.runAsync(it.harness.takes.entries))!)
          p.basename(row.path),
      };
      expect([
        for (final file in Directory(
          '${it.harness.takesHome.path}/guardadas',
        ).listSync())
          if (p
                  .basename(file.path)
                  .startsWith(RegExp('(ensaio|cena|frase)-')) &&
              !named.contains(p.basename(file.path)))
            p.basename(file.path),
      ], isEmpty);
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap the room takes after its 70 s give-up becomes the part the room '
    'holds',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));
      expect(it.onLine(s2b, find.text(_retry)), findsOneWidget);
      await tester.runAsync(() async {
        await it.harness.takes.pending();
        await it.harness.takes.pending();
      });
      await it.settle();

      it.room.finishHeldTake();
      await it.swapLands();
      expect(find.text(_hearNew), findsOneWidget);

      expect(
        [for (final take in it.takesOf(2)) take.origin],
        [it.idOf(s2a), it.idOf(s2b)],
      );
      await it.openTheSheet(2, _swap);
      expect(it.onLine(s2b, find.text(_inUse)), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap over a part another tablet replaced is turned away, the scene '
    'takes the room\'s part, and the next «usar este» names it and lands',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final joined = it.takesOf(2).single.takeId;
      it.room.takes.add(
        const TakeView(
          takeId: 'gravacao-outro-tablet',
          kind: 'ensaio',
          scope: 'parte-2',
          ordinal: 2,
          pass: 2,
        ),
      );
      it.room.takeAudio['gravacao-outro-tablet'] = _bytesOf(9);

      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.until(
        'a linha dizer para tentar de novo',
        () => it.onLine(s2b, find.text(_retry)).evaluate().isNotEmpty,
      );
      await it.settle();

      expect(it.received(2).last.overTake, joined);
      expect(
        [for (final take in it.takesOf(2)) take.takeId],
        [joined, 'gravacao-outro-tablet'],
        reason: 'a sala não guardou a troca',
      );
      expect(
        it.partPath(2),
        contains('gravacao-outro-tablet'),
        reason: 'a cena mostra a parte que a sala tem',
      );
      expect(it.onLine(s2a, find.text(_inUse)), findsNothing);

      await it.swapIn(s2b);
      await it.swapLands();
      expect(it.received(2).last.overTake, 'gravacao-outro-tablet');
      expect(it.takesOf(2).last.origin, it.idOf(s2b));
      semantics.dispose();
    },
  );

  testWidgets(
    'a part another tablet laid in waits while the team records that scene',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final joined = it.partPath(2);
      it.room.takes.add(
        const TakeView(
          takeId: 'gravacao-outro-tablet',
          kind: 'ensaio',
          scope: 'parte-2',
          ordinal: 2,
          pass: 2,
        ),
      );
      it.room
        ..takeAudio['gravacao-outro-tablet'] = _bytesOf(9)
        ..holdNextClip();
      await it.relaunchOnTheHome();
      await it.until(
        'a casa buscar a parte da sala',
        () => it.room.clipsFetched.any(
          (url) => url.contains('gravacao-outro-tablet'),
        ),
      );

      await it.tapThe(it.onRow(2, byLabel('Gravar de novo')));
      await it.until(
        'a cena 2 gravar',
        () => it.onRow(2, byLabel('Parar')).evaluate().isNotEmpty,
      );
      it.room.finishHeldClip();
      await it.settle();

      expect(it.partPath(2), joined, reason: 'nada troca a parte em gravação');
      expect(it.onRow(2, byLabel('Parar')), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap answered while the team records that scene leaves the recording '
    'running, and the part changes only once it ends',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      final joined = it.partPath(2);

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));
      expect(it.onLine(s2b, find.text(_retry)), findsOneWidget);
      await it.tapThe(byLabel(_back));
      await it.until('a casa voltar', it.showsTheHome);

      await it.tapThe(it.onRow(2, byLabel('Gravar de novo')));
      await it.until(
        'a cena 2 gravar',
        () => it.onRow(2, byLabel('Parar')).evaluate().isNotEmpty,
      );
      it.room.finishHeldTake();
      await it.wait(const Duration(seconds: 3));

      expect(it.partPath(2), joined, reason: 'nada troca a parte em gravação');
      expect(
        it.container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recording,
      );
      expect(it.onRow(2, byLabel('Parar')), findsOneWidget);

      await it.tapThe(it.onRow(2, byLabel('Parar')));
      await it.until(
        'a gravação ficar à espera do check',
        () =>
            it.container.read(salaSessionProvider).ensaio ==
            EnsaioStatus.recorded,
      );
      expect(it.partPath(2), joined);
      await it.tapThe(byLabel('Enviar a gravação'));
      await it.settle();

      expect(
        it.partPath(2),
        allOf(isNot(joined), isNot(contains(it.idOf(s2b)))),
        reason: 'a parte é a gravação que a equipe acabou de guardar',
      );
      expect(find.text(_hearNew), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'a swap answered after the team recorded the scene by hand leaves the hand '
    'take the part',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();
      await it.wait(const Duration(seconds: 71));
      expect(it.onLine(s2b, find.text(_retry)), findsOneWidget);
      await it.tapThe(byLabel(_back));
      await it.until('a casa voltar', it.showsTheHome);

      final before = it.received(2).length;
      await it.recordAgainAndKeep(2);
      final hand = it.partPath(2);
      it.room.finishHeldTake();
      await it.within(
        const Duration(seconds: 20),
        'a gravação à mão chegar à sala',
        () => it.received(2).skip(before).any((take) => take.origin == null),
      );
      await it.settle();

      expect(it.partPath(2), hand, reason: 'a gravação à mão segue a parte');
      expect(it.takesOf(2).last.origin, isNull, reason: 'e é a última na sala');
      expect(find.text(_hearNew), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('a swap the tablet was closed on sends nothing after the '
      "relaunch, and its scene row's enviar agora makes it the part", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    await it.joined();

    await it.openTheSheet(2, _swap);
    it.holdTheTake('parte-2');
    await it.swapIn(s2b);
    await it.theHeldTakeArrives();
    it.room
      ..unreachableTake = 'ensaio/parte-2'
      ..finishHeldTake();
    await it.settle();
    await it.relaunchOnTheConversation();
    it.room.unreachableTake = null;
    await it.wait(const Duration(seconds: 30));
    expect(it.takesOf(2), hasLength(1));
    it.container.read(salaSessionProvider.notifier).openTheEnsaioFinal();
    await it.until('a casa voltar', it.showsTheHome);
    await it.tapThe(it.onRow(2, find.textContaining('enviar agora')));
    await it.within(
      const Duration(seconds: 30),
      'a troca chegar à sala',
      () => it.takesOf(2).length == 2,
    );
    await it.within(
      const Duration(seconds: 10),
      'a casa pedir a escuta da cena nova',
      () => find.text(_hearNew).evaluate().isNotEmpty,
    );

    await it.openTheSheet(2, _swap);
    expect(it.onLine(s2b, find.text(_inUse)), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'a swap another tablet made becomes the part on the next arrival at the '
    'home, over a part recorded by hand',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s1a]);
      await it.held(const [s1a]);
      await it.openThePlan();
      await it.tapThe(find.text(_sceneByScene));
      await it.until('a casa abrir', it.showsTheHome);
      await it.tapThe(it.onRow(1, byLabel('Gravar')));
      await it.wait(const Duration(seconds: 2));
      await it.tapThe(it.onRow(1, byLabel('Parar')));
      await it.until(
        'a gravação ficar à espera do check',
        () =>
            it.container.read(salaSessionProvider).ensaio ==
            EnsaioStatus.recorded,
      );
      await it.tapThe(byLabel('Enviar a gravação'));
      await it.until('a parte 1 chegar à sala', () => it.takesOf(1).isNotEmpty);
      await it.settle();
      it.room.takes.add(
        TakeView(
          takeId: 'gravacao-outro-tablet',
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
          pass: 2,
          origin: it.idOf(s1a),
        ),
      );
      it.room.takeAudio['gravacao-outro-tablet'] = _bytesOf(s1a);

      await it.relaunchOnTheHome();
      await it.within(
        const Duration(seconds: 10),
        'a casa pedir a escuta da cena nova',
        () => find.text(_hearNew).evaluate().isNotEmpty,
      );

      expect(it.door(1, _swap), findsNothing);
      expect(it.door(1, _useScene), findsNothing);
      expect(it.partPath(1), contains('junta'));
      semantics.dispose();
    },
  );

  testWidgets(
    'in the dark look an armed «usar este» writes the room\'s dark paper on '
    'her dark telha, never white on it',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
      await it.openTheSheet(2, _swap);

      await it.tapThe(it.use(s2b));

      const telha = Color(0xFFD6612A);
      final pill =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: it.use(s2b),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(pill.color, telha);
      final word = tester
          .widget<Text>(
            find.descendant(of: it.use(s2b), matching: find.text(_useThis)),
          )
          .style!
          .color!;
      expect(
        word,
        const Color(0xFF1A150E),
        reason: 'no escuro a palavra armada não seguia o papel escuro da sala',
      );
      expect(
        (telha.computeLuminance() + 0.05) / (word.computeLuminance() + 0.05),
        greaterThanOrEqualTo(4.5),
      );
      await it.wait(const Duration(seconds: 7));
      semantics.dispose();
    },
  );

  testWidgets(
    'an armed «usar este» fills with her telha, waking it shows at .55, and '
    'while a swap runs the others rest at .35',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
      await it.openTheSheet(2, _swap);
      BoxDecoration pillOf(int n) =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: it.use(n),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      double seen(int n) {
        var opacity = 1.0;
        find
            .descendant(of: it.use(n), matching: find.text(_useThis))
            .evaluate()
            .first
            .visitAncestorElements((ancestor) {
              if (ancestor.widget case final Opacity dim) {
                opacity *= dim.opacity;
              }
              return true;
            });
        return opacity;
      }

      const telha = Color(0xFFBE4A01);
      await it.tapThe(it.use(s2b));
      expect(
        pillOf(s2b).color,
        telha,
        reason: 'armada, «usar este» só esmaecia, sem o telha dela',
      );
      expect(pillOf(s2b).border, Border.all(color: telha, width: 1.4));
      expect(
        tester
            .widget<Text>(
              find.descendant(of: it.use(s2b), matching: find.text(_useThis)),
            )
            .style!
            .color,
        const Color(0xFFF6F5EB),
      );
      expect(
        seen(s2b),
        closeTo(0.55, 0.001),
        reason: 'acordando, ela mostra a .55, não a .5',
      );
      expect(pillOf(s2c).color, isNull);

      await it.wait(const Duration(milliseconds: 700));
      expect(pillOf(s2b).color, telha);
      expect(seen(s2b), closeTo(1, 0.001));

      it.holdTheTake('parte-2');
      await it.tapThe(it.use(s2b));
      await it.theHeldTakeArrives();
      expect(
        seen(s2c),
        closeTo(0.35, 0.001),
        reason: 'com a troca no ar, «usar este» seguia aceso',
      );
      it.room.finishHeldTake();
      await it.swapLands();
      semantics.dispose();
    },
  );

  testWidgets('while a swap runs nothing else starts', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester);
    await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
    final before = it.room.takesReceivedWhole.length;

    await it.openTheSheet(2, _swap);
    it.holdTheTake('parte-2');
    await it.swapIn(s2b);
    await it.theHeldTakeArrives();

    expect(it.enabled(it.use(s2c)), isFalse);
    expect(it.enabled(byLabel(_back)), isFalse);
    await it.tapThe(it.use(s2c));
    await it.wait(const Duration(milliseconds: 700));
    await it.tapThe(it.use(s2c));
    expect(it.room.takesReceivedWhole, hasLength(before));
    it.room.finishHeldTake();
    await it.swapLands();
    semantics.dispose();
  });

  testWidgets(
    'while a swap runs «gravar esta cena de novo» is dimmed and its tap opens '
    'nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined(listed: const [s1a, s2a, s3a, s2b, s2c]);
      await it.openTheSheet(2, _swap);
      it.holdTheTake('parte-2');
      await it.swapIn(s2b);
      await it.theHeldTakeArrives();

      final recordAgain = find.ancestor(
        of: find.text(_recordAgain),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(recordAgain).onPressed, isNull);
      await it.tapThe(find.text(_recordAgain));
      await it.wait(const Duration(seconds: 1));
      expect(
        byLabel(_question),
        findsNothing,
        reason: 'a troca no ar ainda deixava sair para gravar a cena',
      );
      expect(it.showsTheSheet(), isTrue);

      it.room.finishHeldTake();
      await it.swapLands();
      semantics.dispose();
    },
  );

  testWidgets(
    'while a bring-back runs, «gravar esta cena de novo» on the home\'s sheet '
    'opens nothing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      it.room.retroSoFar = const BackTranslationProgress(bringBack: [2]);
      final notifier = it.container.read(salaSessionProvider.notifier);
      notifier.goEnsaio();
      await it.until(
        'a casa oferecer a volta das traduções',
        () => it.door(2, _bringBack).evaluate().isNotEmpty,
      );
      it.room.holdBringBack();
      await it.tapThe(it.door(2, _bringBack));
      await it.wait(const Duration(milliseconds: 700));
      await it.tapThe(it.door(2, _bringBackArmed));
      await it.until(
        'a volta das traduções ficar no ar',
        () => it.container.read(salaSessionProvider).bringingBack == 2,
      );

      notifier.openTheHomeSheet(2);
      await it.until('a folha da cena 2 abrir', it.showsTheSheet);
      await it.tapThe(find.text(_recordAgain));
      await it.wait(const Duration(seconds: 1));

      expect(
        byLabel(_question),
        findsNothing,
        reason: 'a volta das traduções no ar ainda deixava sair para gravar',
      );
      expect(it.showsTheSheet(), isTrue);

      it.room.finishHeldBringBack();
      await it.settle();
      semantics.dispose();
    },
  );

  group('«ouçam a cena nova antes de conferir»', () {
    testWidgets('stands until the listen starts', (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.swapLands();
      expect(find.text(_hearNew), findsOneWidget);

      await it.tapThe(byLabel(_listenAndCheck));
      await it.settle();
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until('a casa voltar', it.showsTheHome);
      expect(find.text(_hearNew), findsNothing);
      semantics.dispose();
    });

    testWidgets('is gone after a relaunch', (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);
      await it.swapIn(s2b);
      await it.swapLands();
      expect(find.text(_hearNew), findsOneWidget);

      await it.relaunchOnTheHome();
      expect(find.text(_hearNew), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets(
    'the sheet opened from a joined row offers «gravar esta cena de novo», as '
    'the plan\'s sheet does',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();

      await it.openTheSheet(2, _swap);

      expect(
        find.text(_recordAgain),
        findsOneWidget,
        reason: 'a folha da casa não tinha como gravar a cena de novo',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    '«gravar esta cena de novo» on the home\'s sheet asks which scene with that '
    'scene highlighted, never picked',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);

      await it.tapThe(find.text(_recordAgain));
      await it.until(
        'a pergunta da cena aparecer',
        () => byLabel(_question).evaluate().isNotEmpty,
      );
      await it.settle();

      expect(byLabel(_question), findsOneWidget);
      expect(
        [
          for (final button in tester.widgetList<SceneButton>(
            find.byType(SceneButton),
          ))
            if (button.highlighted) button.label,
        ],
        ['cena 2 Noemi decide voltar'],
        reason: 'a cena da folha vem destacada debaixo da pergunta',
      );
      for (final circle in _sceneCircle) {
        expect(byLabel(circle), findsNothing, reason: 'nada foi escolhido');
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'leaving the scene rehearsal the home\'s sheet opened lands on the '
    'conversation, and the orange dot brings back the home, not the sheet',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);
      await it.tapThe(find.text(_recordAgain));
      await it.until(
        'a pergunta da cena aparecer',
        () => byLabel(_question).evaluate().isNotEmpty,
      );
      await it.settle();

      await it.tapThe(byLabel(_houseBack));
      await it.until(
        'a pergunta sumir',
        () => byLabel(_question).evaluate().isEmpty,
      );
      await it.settle();

      expect(byLabel(_question), findsNothing);
      expect(_dot, findsOneWidget, reason: 'a saída volta para a conversa');

      await it.openThePlan();

      expect(it.showsTheHome(), isTrue);
      expect(
        it.showsTheSheet(),
        isFalse,
        reason: 'a folha velha voltava por cima da casa',
      );
      semantics.dispose();
    },
  );

  testWidgets('an English room swaps in her English', (tester) async {
    final semantics = tester.ensureSemantics();
    final it = await _atRest(tester, lingua: 'en', scenes: _threeScenesEn);
    await it.joined();

    await it.openTheSheet(2, _swapEn);
    expect(it.use(s2b, _useThisEn), findsOneWidget);
    await it.tapThe(it.use(s2b, _useThisEn));
    await it.wait(const Duration(milliseconds: 700));
    await it.tapThe(it.use(s2b, _useThisEn));
    await it.swapLands();
    expect(find.text(_hearNewEn), findsOneWidget);

    await it.recordAgainAndKeep(2);
    await it.within(
      const Duration(seconds: 20),
      'Scene 2 offers «use this scene\'s rehearsal»',
      () => it.door(2, _useSceneEn).evaluate().isNotEmpty,
    );
    semantics.dispose();
  });

  testWidgets(
    'on the home\'s sheet the line that plays shows her pause, and a second '
    'tap gives the play back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);

      await it.tapThe(it.listen(s2b));
      await it.until('o ensaio tocar', () => it.harness.playback.sounding);

      expect(
        it.glyphOn(it.listen(s2b)),
        ListenGlyph.pause,
        reason: 'o ensaio da folha da casa tocava e o botão mostrava tocar',
      );
      expect(it.pressed(it.listen(s2b)), Tristate.isTrue);
      expect(it.glyphOn(it.listen(s2a)), ListenGlyph.play);
      expect(it.pressed(it.listen(s2a)), Tristate.isFalse);

      await it.tapThe(it.listen(s2b));
      await it.settle();

      expect(it.harness.playback.sounding, isFalse);
      expect(it.glyphOn(it.listen(s2b)), ListenGlyph.play);
      expect(it.pressed(it.listen(s2b)), Tristate.isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'the home\'s sheet closed while its rehearsal plays opens again on the '
    'play, and one tap plays it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);
      await it.tapThe(it.listen(s2b));
      await it.until('o ensaio tocar', () => it.harness.playback.sounding);

      await it.tapThe(byLabel(_back));
      await it.until('a casa voltar', it.showsTheHome);
      expect(it.harness.playback.sounding, isFalse);
      await it.openTheSheet(2, _swap);

      expect(
        it.glyphOn(it.listen(s2b)),
        ListenGlyph.play,
        reason: 'a folha fechou o som e reabriu em pausa sobre o silêncio',
      );
      expect(it.pressed(it.listen(s2b)), Tristate.isFalse);

      final played = it.harness.playback.played.length;
      await it.tapThe(it.listen(s2b));
      await it.until('o ensaio tocar', () => it.harness.playback.sounding);

      expect(
        it.harness.playback.played.length,
        played + 1,
        reason: 'o toque depois de fechar a folha só limpava, sem tocar',
      );
      expect(it.glyphOn(it.listen(s2b)), ListenGlyph.pause);
      semantics.dispose();
    },
  );

  testWidgets('on the home\'s sheet a line is offered as her filled triangle '
      'and pauses with her two filled bars, not lucide outlines', (
    tester,
  ) async {
    final it = await _atRest(tester);
    await it.joined();
    await it.openTheSheet(2, _swap);

    expect(
      find.descendant(of: it.listen(s2b), matching: find.byType(Icon)),
      findsNothing,
      reason: 'a folha da casa desenhava o play vazado do Lucide',
    );
    expect(
      it.paintedOn(it.listen(s2b)),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [Offset(10, 12), Offset(9, 7), Offset(9, 17)],
        excludes: const [Offset(7, 12), Offset(16, 8), Offset(16, 16)],
      ),
      reason: 'o play dela é «M8 6l10 6-10 6z» (EnsaioFinalSheet.tsx:19)',
    );

    await it.tapThe(it.listen(s2b));
    await it.until('o ensaio tocar', () => it.harness.playback.sounding);

    expect(
      it.paintedOn(it.listen(s2b)),
      paints..path(
        style: PaintingStyle.fill,
        includes: const [
          Offset(8, 12),
          Offset(16, 12),
          Offset(7, 6),
          Offset(17, 18),
        ],
        excludes: const [
          Offset(12, 12),
          Offset(8, 4),
          Offset(16, 20),
          Offset(6.1, 5.1),
          Offset(17.9, 18.9),
        ],
      ),
      reason:
          'a pausa dela são duas barras cheias com rx 1 '
          '(EnsaioFinalSheet.tsx:20)',
    );
  });

  testWidgets(
    'while a bring-back runs, «gravar a passagem inteira de uma vez» on the '
    'home rests',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      it.room.retroSoFar = const BackTranslationProgress(bringBack: [2]);
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await it.until(
        'a casa oferecer a volta das traduções',
        () => it.door(2, _bringBack).evaluate().isNotEmpty,
      );
      it.room.holdBringBack();
      await it.tapThe(it.door(2, _bringBack));
      await it.wait(const Duration(milliseconds: 700));
      await it.tapThe(it.door(2, _bringBackArmed));
      await it.until(
        'a volta das traduções ficar no ar',
        () => it.container.read(salaSessionProvider).bringingBack == 2,
      );

      expect(
        it.enabled(byLabel(_wholeAtOnce)),
        isFalse,
        reason: 'a troca do grão ficava viva com a volta das traduções no ar',
      );
      it.room.finishHeldBringBack();
      await it.settle();
      semantics.dispose();
    },
  );

  testWidgets(
    'while the join runs, «gravar a passagem inteira de uma vez» on the plan '
    'rests',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      it.list(const [s1a, s2a, s3a]);
      await it.held(const [s1a, s2a, s3a]);
      await it.openThePlan();
      it.room.holdNextTakesList();
      final join = byLabel(_join);
      await tester.ensureVisible(join);
      await tester.pump();
      await tester.tap(join);
      await it.until(
        'a junta perguntar à sala pela cena 1',
        () => it.room.aTakesListIsHeld,
      );
      expect(it.container.read(salaSessionProvider).joining, 1);

      expect(
        it.enabled(byLabel(_wholeAtOnce)),
        isFalse,
        reason: 'a troca do grão ficava viva com a junta no ar',
      );
      it.room.finishHeldTakesList();
      await it.joinEnds();
      semantics.dispose();
    },
  );

  testWidgets(
    'the home\'s sheet whose rehearsal plays when the app goes away falls '
    'silent and opens back on the play',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _atRest(tester);
      await it.joined();
      await it.openTheSheet(2, _swap);
      await it.tapThe(it.listen(s2b));
      await it.until('o ensaio tocar', () => it.harness.playback.sounding);

      for (final away in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(away);
      }
      await it.settle();

      expect(
        it.harness.playback.sounding,
        isFalse,
        reason: 'o app saía e o ensaio da folha da casa seguia tocando',
      );

      for (final back in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(back);
      }
      await it.settle();

      expect(it.harness.playback.sounding, isFalse);
      expect(
        it.pressed(it.listen(s2b)),
        Tristate.isFalse,
        reason: 'e a folha voltava em pausa sobre o silêncio',
      );
      semantics.dispose();
    },
  );
}

List<Object?> _heard(_Room it, int after, String? takeId) => [
  for (final report in it.room.listeningReports.skip(after))
    for (final played in report)
      if (played['take_id'] == takeId &&
          (played['played_ranges'] as List).isNotEmpty)
        played,
];
