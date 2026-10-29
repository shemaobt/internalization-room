import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/device_link_notifier.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, relaunch, settle;

const _aindaNoComputador =
    'Uma gravação ainda está neste computador e não foi enviada.';
const _enviarAgora = 'enviar agora';
const _falhou = 'falhou — toque para tentar de novo';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

class _Casa {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Casa(this.tester, this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  int get envios => room.calls.where((call) => call == 'sendTake').length;

  List<File> get copias {
    final guardadas = Directory('${harness.takesHome.path}/guardadas');
    if (!guardadas.existsSync()) return const [];
    return [
      for (final entry in guardadas.listSync())
        if (entry is File && !entry.path.contains('fila.json')) entry,
    ];
  }

  Finder naLinha(int n, Finder alvo) => find.descendant(
    of: byLabel('Cena $n — ${_cenas[n - 1].title}'),
    matching: alvo,
  );

  Future<void> emTempoReal(Future<void> Function() corpo) async {
    await tester.runAsync(corpo);
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> tocar(Finder alvo) => emTempoReal(() async {
    await tester.ensureVisible(alvo);
    await tester.tap(alvo);
    await settle(const Duration(milliseconds: 400));
  });

  Future<void> guardar(int n) async {
    await emTempoReal(() async {
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
      final antes = envios;
      sala.takeKeep();
      await waitFor('a cena $n subir', () => envios > antes);
      await settle(const Duration(milliseconds: 300));
    });
  }

  /// The team records part [n] and keeps it, and waits for nothing past its copy on the
  /// disk.
  Future<void> guardarNoDisco(int n) => emTempoReal(() async {
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
    sala.takeKeep();
    await waitFor('a tomada entrar na fila', () => copias.isNotEmpty);
    await settle(const Duration(milliseconds: 300));
  });

  Future<void> quinzeMinutos() async {
    for (var minuto = 0; minuto < 15; minuto++) {
      await tester.pump(const Duration(minutes: 1));
      await emTempoReal(() => settle(const Duration(milliseconds: 100)));
    }
  }

  Future<void> entrarDeNovoNaPassagem(String deAntes) => emTempoReal(() async {
    await waitFor(
      'a sala levar a equipe para a Escolha',
      () => estado.stage == SalaStage.escolha,
    );
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a passagem abrir numa sessão nova',
      () =>
          estado.sessionId != null &&
          estado.sessionId != deAntes &&
          !estado.awaitingTheGuide,
    );
    await settle();
    sala.goEnsaio();
    await waitFor(
      'as cenas chegarem',
      () => estado.sceneRows.length == _cenas.length,
    );
    await settle();
  });
}

Widget _aCasa(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: EnsaioView()),
  ),
);

Future<_Casa> _relancada(_Casa casa) async {
  await casa.tester.pumpWidget(const SizedBox());
  final (harness, container) = (await casa.tester.runAsync(
    () => relaunch(casa.harness, casa.container),
  ))!;
  return _naCasa(casa.tester, harness: harness, relaunched: container);
}

Future<_Casa> _naCasa(
  WidgetTester tester, {
  SalaHarness? harness,
  ProviderContainer? relaunched,
}) async {
  tester.view
    ..physicalSize = const Size(820, 1180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sala = harness ?? SalaHarness();
  if (relaunched == null) {
    addTearDown(() => sala.takesHome.deleteSync(recursive: true));
  }
  sala.room.passageScenes = _cenas;
  final container = (await tester.runAsync(
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
    await waitFor(
      'a sessão abrir',
      () => casa.estado.sessionId != null && !casa.estado.awaitingTheGuide,
    );
    await settle();
    if (relaunched != null) {
      casa.sala.openTheEnsaioFinal();
    } else if (casa.estado.stage != SalaStage.ensaio) {
      casa.sala.goEnsaio();
    }
    await waitFor(
      'as cenas chegarem',
      () => casa.estado.sceneRows.length == _cenas.length,
    );
    await settle();
  });
  return casa;
}

/// The app is closed between the keep and its send: nothing this Outbox is asked to send
/// leaves.
class _ADiskThatFailsOnce extends TakeUploadQueue {
  _ADiskThatFailsOnce({
    required super.room,
    super.home,
    required super.recordings,
  });

  bool _failed = false;

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
    if (!_failed) {
      _failed = true;
      throw const FileSystemException('o disco recusou');
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

class _AnAppClosedBeforeTheSend extends TakeUploadQueue {
  _AnAppClosedBeforeTheSend({
    required super.room,
    super.home,
    required super.recordings,
  });

  @override
  Future<int> flush() async => 0;
}

void main() {
  testWidgets(
    'a take recorded then the app closed before any send is offered on the '
    'next visit with enviar agora, and nothing was sent meanwhile',
    (tester) async {
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) => _AnAppClosedBeforeTheSend(
            room: room,
            home: () async => home,
            recordings: recordings,
          ),
        ),
      );
      await casa.guardarNoDisco(2);

      final depois = await _relancada(casa);
      await depois.emTempoReal(() => settle(const Duration(seconds: 1)));

      expect(depois.envios, 0);
      expect(find.text(_aindaNoComputador), findsOneWidget);
      final aOferta = depois.naLinha(2, find.textContaining(_enviarAgora));
      expect(aOferta, findsOneWidget);

      await depois.tocar(aOferta);

      expect(depois.room.takesKept, ['ensaio/parte-2']);
    },
  );

  test('a failed take left fifteen minutes with the network back is still '
      'unsent, and no request leaves the tablet', () {
    fakeAsync((async) {
      final harness = SalaHarness(filaEmMemoria: true);
      harness.room.failSceneWith = const NetworkFailed('sem rede');
      late SceneRoom room;
      unawaited(atRest(harness).then((opened) => room = opened));
      async.elapse(const Duration(seconds: 2));
      room.sala.openTheSceneRehearsal();
      async.elapse(const Duration(seconds: 1));
      room.sala.sceneTap();
      async.elapse(const Duration(seconds: 1));
      room.sala.sceneTap();
      async.elapse(const Duration(seconds: 2));
      expect(room.state.scene.keep, isA<NotKept>());
      expect(room.asked('keepSceneRehearsal'), 1);
      harness.room.failSceneWith = null;

      async.elapse(const Duration(minutes: 15));

      expect(room.asked('keepSceneRehearsal'), 1);
      expect(harness.room.scenesKept, isEmpty);
      expect(
        (harness.takes as FakeTakeQueue).rows.where((row) => !row.stored),
        hasLength(1),
      );
      room.container.dispose();
    });
  });

  testWidgets(
    'a waiting take whose session is gone stays on disk, the next visit to '
    "the passage offers it, and the tap sends it into the passage's current "
    'session',
    (tester) async {
      final casa = await _naCasa(tester);
      final perdida = casa.estado.sessionId!;
      casa.room.forgetTheSession(perdida);
      await casa.guardarNoDisco(2);

      await casa.entrarDeNovoNaPassagem(perdida);

      expect(casa.copias, hasLength(1));
      expect(find.text(_aindaNoComputador), findsOneWidget);
      final atual = casa.estado.sessionId!;
      await casa.tocar(casa.naLinha(2, find.textContaining(_enviarAgora)));

      expect(casa.room.takeSessions.last, atual);
      expect(casa.room.takesKept, ['ensaio/parte-2']);
      expect(casa.copias, isEmpty);
    },
  );

  testWidgets(
    'a tap to record a part again over a failed take removes the old copy at '
    'the tap, before the microphone opens',
    (tester) async {
      final casa = await _naCasa(tester);
      casa.room.unreachableTake = 'ensaio/parte-2';
      await casa.guardar(2);
      expect(casa.naLinha(2, find.text(_falhou)), findsOneWidget);
      expect(casa.copias, hasLength(1));
      casa.harness.recorder.holdNextStart();

      await casa.emTempoReal(() async {
        casa.sala.gravarACena(2);
        await settle();
      });

      expect(casa.copias, isEmpty);
      expect((await tester.runAsync(casa.harness.takes.entries))!, isEmpty);
      await casa.emTempoReal(() async {
        casa.harness.recorder.finishStart();
        await settle();
      });
    },
  );
  testWidgets(
    'a take the Outbox could not take stays on the tablet when its session '
    'goes, and nothing of it is deleted',
    (tester) async {
      final casa = await _naCasa(
        tester,
        harness: SalaHarness(
          takesOverride: (room, home, recordings) => _ADiskThatFailsOnce(
            room: room,
            home: () async => home,
            recordings: recordings,
          ),
        ),
      );
      final perdida = casa.estado.sessionId!;
      late String fora;
      await casa.emTempoReal(() async {
        casa.sala.gravarACena(2);
        await waitFor(
          'a cena 2 gravar',
          () => casa.estado.ensaio == EnsaioStatus.recording,
        );
        casa.sala.gravarACena(2);
        await waitFor(
          'a gravação da cena 2 esperar o visto',
          () => casa.estado.ensaio == EnsaioStatus.recorded,
        );
        fora = casa.harness.recorder.lastPath!;
        casa.sala.takeKeep();
        await settle(const Duration(milliseconds: 500));
      });
      expect(casa.copias, isEmpty);
      casa.room.forgetTheSession(perdida);

      await casa.guardarNoDisco(1);
      await casa.entrarDeNovoNaPassagem(perdida);

      expect(casa.harness.recorder.deleted, isNot(contains(fora)));
      expect(File(fora).existsSync(), isTrue);
    },
  );

  testWidgets(
    'a take whose session the room forgets after the team left its passage is '
    "listed in the passage's next session, and its tap sends it there",
    (tester) async {
      final casa = await _naCasa(tester);
      final perdida = casa.estado.sessionId!;
      await casa.emTempoReal(() async {
        casa.room.holdNextTake('parte-2');
        casa.sala.gravarACena(2);
        await waitFor(
          'a cena 2 gravar',
          () => casa.estado.ensaio == EnsaioStatus.recording,
        );
        casa.sala.gravarACena(2);
        await waitFor(
          'a gravação da cena 2 esperar o visto',
          () => casa.estado.ensaio == EnsaioStatus.recorded,
        );
        casa.sala.takeKeep();
        await casa.room.untilTakeHeld();
        casa.sala.leaveThePassage();
        await waitFor(
          'a equipe chegar à Escolha',
          () => casa.estado.stage == SalaStage.escolha,
        );
        casa.room
          ..takeAnswersFirst.add(const SessionGone())
          ..forgetTheSession(perdida)
          ..finishHeldTake();
        await settle(const Duration(milliseconds: 500));
      });

      await casa.entrarDeNovoNaPassagem(perdida);

      expect(find.text(_aindaNoComputador), findsOneWidget);
      final atual = casa.estado.sessionId!;
      await casa.tocar(casa.naLinha(2, find.textContaining(_enviarAgora)));

      expect(casa.room.takeSessions.last, atual);
      expect(casa.room.takesKept, ['ensaio/parte-2']);
    },
  );

  testWidgets(
    'a take still waiting for its check when its session goes is kept with no '
    "session under its passage, listed in the passage's next session, and its "
    'tap sends it there',
    (tester) async {
      final casa = await _naCasa(tester);
      final perdida = casa.estado.sessionId!;
      late String esperando;
      await casa.emTempoReal(() async {
        casa.sala.gravarACena(2);
        await waitFor(
          'a cena 2 gravar',
          () => casa.estado.ensaio == EnsaioStatus.recording,
        );
        casa.sala.gravarACena(2);
        await waitFor(
          'a gravação da cena 2 esperar o visto',
          () => casa.estado.ensaio == EnsaioStatus.recorded,
        );
        esperando = casa.harness.recorder.lastPath!;
        await casa.harness.takes.enqueue(
          casa.harness.recorder.aFile('parte-que-acusa'),
          sessionId: perdida,
          kind: 'ensaio',
          scope: 'parte-1',
          passNumber: 1,
          chunkIndex: 1,
        );
        casa.room.forgetTheSession(perdida);
        await casa.harness.takes.flush();
        await waitFor(
          'a sala levar a equipe para a Escolha',
          () => casa.estado.stage == SalaStage.escolha,
        );
        await settle(const Duration(milliseconds: 500));
      });

      expect(casa.harness.recorder.deleted, isNot(contains(esperando)));
      await casa.entrarDeNovoNaPassagem(perdida);

      final atual = casa.estado.sessionId!;
      await casa.tocar(casa.naLinha(2, find.textContaining(_enviarAgora)));

      expect(casa.room.takeSessions.last, atual);
      expect(casa.room.takesKept, contains('ensaio/parte-2'));
    },
  );

  testWidgets('a session start sends nothing of a take waiting for it', (
    tester,
  ) async {
    final casa = await _naCasa(tester);
    final sessao = casa.estado.sessionId!;
    await casa.emTempoReal(() async {
      casa.sala.leaveThePassage();
      await waitFor(
        'a equipe chegar à Escolha',
        () => casa.estado.stage == SalaStage.escolha,
      );
      await casa.harness.takes.enqueue(
        casa.harness.recorder.aFile('parte-que-espera'),
        sessionId: sessao,
        kind: 'ensaio',
        scope: 'parte-2',
        passNumber: 1,
        chunkIndex: 2,
      );
    });
    final antes = casa.envios;

    await casa.entrarDeNovoNaPassagem('');
    await casa.emTempoReal(() => settle(const Duration(seconds: 1)));

    expect(casa.envios, antes);
  });
}
