import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:path/path.dart' as p;

import 'a_parte_da_volta_ganha_nome_test.dart' show gravarSemEsperarNome;
import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'an_empty_telling_keeps_the_pause_and_shows_her_line_test.dart'
    show
        fecharComPalavras,
        fecharSemPalavras,
        linha,
        pausarEAbrir,
        tocarOCirculo;
import 'fakes.dart';
import 'resto_da_historia_test.dart' show aRetomadaNoEnsaio;
import 'scenario_helpers.dart' show byLabel, relaunch, settle, umaParteInteira;
import 'the_back_translation_is_told_by_beads_test.dart'
    show entrarNaTraducao, tocar, terminar;
import 'support/temp.dart';

const _notUnderstood = 'não entendi — traduzam de novo esse pedaço';
const _wentToTheVoice = 'a tradução deste ensaio da cena já foi para a voz';
const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _translate = 'traduzir o ensaio da cena';
const _pausaHint =
    'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para '
    'traduzir';

String _translateAgainBar(int n) =>
    'Ouvir esta frase de novo e traduzir de novo — $n';

final _oneFrase = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: 'sessao-1',
  n: 1,
  frases: const [SceneFrase(fraseId: 'f1', startsMs: 0, endsMs: 3000)],
);

final class _SceneScreen {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _SceneScreen(this.tester, this.harness, this.container);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  Future<void> beat([int ms = 300]) => tester.pump(Duration(milliseconds: ms));

  Future<void> tap(String label) async {
    await tester.tap(byLabel(label));
    await beat();
  }

  bool shows(String words) =>
      byLabel(words).evaluate().isNotEmpty &&
      find.text(words).evaluate().isNotEmpty;

  Future<void> tellsTheFrase() async {
    final posts = room.frasesKept.length;
    await tap(_tell);
    await pumpUntil(
      tester,
      () =>
          state.channel is Microphone &&
          (state.channel as Microphone).owner == MicOwner.frase,
    );
    await tap(_tell);
    await pumpUntil(
      tester,
      () => room.frasesKept.length > posts && !state.scene.waiting,
    );
    await beat(500);
  }
}

/// Frase 1 kept, the take listened to from where it stops, and a pausa marked at 6 s.
Future<_SceneScreen> _aPausaAtTheCut(WidgetTester tester) async {
  const length = Duration(seconds: 10);
  final (harness, container) = await translateOnScreen(
    tester,
    take: aSpokenWav(length: length),
    length: length,
    rehearsal: _oneFrase,
  );
  final screen = _SceneScreen(tester, harness, container);
  await screen.tap(_translate);
  await pumpUntil(tester, () => screen.state.channel is PartPlaying);
  await screen.beat(100);
  harness.playback.at = const Duration(seconds: 6);
  await screen.tap(_tell);
  return screen;
}

int _rowsIn(SalaHarness harness) =>
    (harness.takes as FakeTakeQueue).rows.length;

/// Lets the disk answer what the widget binding would otherwise hold forever.
Future<void> _theDiskAnswers(WidgetTester tester) async {
  for (var time = 0; time < 5; time++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('at the scene frase door', () {
    testWidgets(
      'at the scene frase door, a connection that drops while the frase is sent keeps the pausa at the cut with «não entendi — traduzam de novo esse pedaço»',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);
        final rows = _rowsIn(screen.harness);
        screen.room.sceneAnswersFirst.add(const NetworkFailed('HTTP 502'));

        await screen.tellsTheFrase();

        expect(screen.shows(_notUnderstood), isTrue);
        expect(byLabel('$_pausaHint — 0:06 / 0:10'), findsOneWidget);
        expect(_rowsIn(screen.harness), rows);
      },
    );

    testWidgets(
      'a frase translated again with the connection back is stored and the screen moves on',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);
        screen.room.sceneAnswersFirst.add(const NetworkFailed('HTTP 502'));
        await screen.tellsTheFrase();

        await screen.tellsTheFrase();

        final [first, second] = screen.room.frasesKept;
        expect(
          (second.startsMs, second.endsMs),
          (first.startsMs, first.endsMs),
        );
        expect(byLabel(_translateAgainBar(2)), findsOneWidget);
        expect(byLabel(_notUnderstood), findsNothing);
      },
    );

    testWidgets(
      'at the scene frase door, a wordless translation reads «não entendi — traduzam de novo esse pedaço» and nothing is queued',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);
        final rows = _rowsIn(screen.harness);
        screen.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.wordlessTelling),
        );

        await screen.tellsTheFrase();

        expect(screen.shows(_notUnderstood), isTrue);
        expect(_rowsIn(screen.harness), rows);
      },
    );

    testWidgets(
      'three pieces not stored in a row at the scene frase door never halt the room nor raise the person sign',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);

        for (final lost in [
          const NetworkFailed('HTTP 502'),
          const Refused(RefusalCode.wordlessTelling),
          const NetworkFailed('timeout'),
        ]) {
          screen.room.sceneAnswersFirst.add(lost);
          await screen.tellsTheFrase();
        }

        expect(screen.state.needsPerson, isFalse);
        expect(screen.state.halt, isA<NoHalt>());
        expect(screen.shows(_notUnderstood), isTrue);
      },
    );

    testWidgets(
      'a frase refused because another tablet already sent the scene rehearsal reads «a tradução deste ensaio da cena já foi para a voz»',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);
        screen.room.sceneAnswersFirst.add(
          const Refused(RefusalCode.sceneRehearsalSent),
        );

        await screen.tellsTheFrase();

        expect(screen.shows(_wentToTheVoice), isTrue);
        expect(byLabel(_notUnderstood), findsNothing);
        expect(screen.state.needsPerson, isFalse);
      },
    );

    testWidgets(
      'at the scene frase door, a timeout reads «não entendi — traduzam de novo esse pedaço» and raises no person sign',
      (tester) async {
        final screen = await _aPausaAtTheCut(tester);
        screen.room.sceneAnswersFirst.add(const NetworkFailed('timeout'));

        await screen.tellsTheFrase();

        expect(screen.shows(_notUnderstood), isTrue);
        expect(screen.state.needsPerson, isFalse);
        expect(screen.state.halt, isA<NoHalt>());
      },
    );
  });

  group('in the Back-translation', () {
    testWidgets(
      'in the Back-translation, a connection that drops while a stretch is sent keeps the pausa at the cut with «não entendi — traduzam de novo esse pedaço», and nothing enters the Outbox',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        final rows = _rowsIn(harness);
        await pausarEAbrir(tester, harness);
        harness.room.chunkAnswersFirst.add(const NetworkFailed('HTTP 502'));

        await tocar(tester, terminar);
        await tester.pump(const Duration(milliseconds: 300));
        await _theDiskAnswers(tester);

        expect(byLabel(linha), findsWidgets);
        expect(harness.playback.sounding, isFalse);
        expect(_rowsIn(harness), rows);
        await tocarOCirculo(tester);
        await fecharComPalavras(tester, harness);
        expect(harness.room.chunkSpans, ['0-4000']);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'in the Back-translation, a wordless translation reads «não entendi — traduzam de novo esse pedaço» and nothing enters the Outbox',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        final rows = _rowsIn(harness);
        await pausarEAbrir(tester, harness);

        await fecharSemPalavras(tester, harness);
        await _theDiskAnswers(tester);

        expect(byLabel(linha), findsWidgets);
        expect(_rowsIn(harness), rows);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'three pieces not stored in a row in the Back-translation never halt the room nor raise the person sign',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        await pausarEAbrir(tester, harness);
        harness.room.chunkAnswersFirst.addAll(const [
          NetworkFailed('HTTP 502'),
          NetworkFailed('timeout'),
          Refused(RefusalCode.wordlessTelling),
        ]);

        for (var time = 0; time < 3; time++) {
          if (time > 0) await tocarOCirculo(tester);
          await tocar(tester, terminar);
          await tester.pump(const Duration(milliseconds: 300));
        }

        final state = container.read(salaSessionProvider);
        expect(state.needsPerson, isFalse);
        expect(state.halt, isA<NoHalt>());
        expect(byLabel(linha), findsWidgets);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'after the connection returns, no earlier failed translation reaches the room by itself',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        final received = harness.room.takesReceived.length;
        await pausarEAbrir(tester, harness);
        harness.room.chunkAnswersFirst.add(const NetworkFailed('HTTP 502'));
        await tocar(tester, terminar);
        await tester.pump(const Duration(milliseconds: 300));

        await _theDiskAnswers(tester);
        await tester.runAsync(harness.takes.flush);
        await _theDiskAnswers(tester);

        expect(harness.room.takesReceived, hasLength(received));
        expect(harness.room.chunksSent, 0);
        closeTheRoom(container);
      },
    );

    testWidgets(
      'in the Back-translation, a stretch whose recording cannot be read reads «não entendi — traduzam de novo esse pedaço» and nothing enters the Outbox',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true);
        final container = await entrarNaTraducao(tester, harness, partes: 1);
        final rows = _rowsIn(harness);
        await pausarEAbrir(tester, harness);
        harness.room.chunkThrows = const FileSystemException('o disco falhou');

        await tocar(tester, terminar);
        await tester.pump(const Duration(milliseconds: 300));
        await _theDiskAnswers(tester);

        expect(byLabel(linha), findsWidgets);
        expect(harness.playback.sounding, isFalse);
        expect(_rowsIn(harness), rows);
        closeTheRoom(container);
      },
    );
  });

  test(
    'in the Back-translation, a stretch over a part the room has not named yet reads «não entendi — traduzam de novo esse pedaço» and nothing enters the Outbox',
    () async {
      final antes = SalaHarness();
      final primeira = await aRetomadaNoEnsaio(antes, traduzidasAte: [30000]);
      antes.room.unreachableTake = 'ensaio/${KeptScope.parte(2)}';
      await gravarSemEsperarNome(primeira, 2);
      await settle();
      final (harness, container) = await relaunch(antes, primeira);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.openTheRoom();
      await waitFor(
        'a sala pousar na conversa',
        () =>
            container.read(salaSessionProvider).station is Canvas &&
            !container.read(salaSessionProvider).awaitingTheGuide,
      );
      notifier.goEnsaio();
      await waitFor(
        'a volta ao ensaio com as duas partes',
        () =>
            container.read(salaSessionProvider).stage == SalaStage.ensaio &&
            container.read(salaSessionProvider).keptTakes.length == 2,
      );
      harness.room.unreachableTake = null;
      notifier.enviarACena(2);
      await waitFor(
        'a parte 2 chegar à sala',
        () => container.read(salaSessionProvider).everyPartIsSent,
      );
      final daVolta = container.read(salaSessionProvider).keptTakes[1];
      expect(
        daVolta.takeId,
        isNull,
        reason:
            'o cenário é o da parte que chegou à sala sem o tablet saber o '
            'nome dela',
      );
      harness.playback.length = umaParteInteira;
      notifier.startRetro();
      await waitFor(
        'a retro tocar a parte 2',
        () =>
            harness.playback.played.isNotEmpty &&
            harness.playback.played.last == daVolta.path,
      );
      await theClipOpens(harness);
      harness.playback.at = const Duration(seconds: 12);
      notifier.retroTap();
      notifier.retroTap();
      await settle();

      await confirmarATraducao(container);

      expect(container.read(salaSessionProvider).wordlessTelling, isTrue);
      expect(harness.room.chunksSent, 0);
      expect([
        for (final row in await harness.takes.entries())
          if (row.kind != 'ensaio') row,
      ], isEmpty);
    },
  );

  group('a Back-translation row an older build left in the Outbox', () {
    late Directory home;

    setUp(() {
      home = aTempDir('fila-de-um-app-antigo');
    });

    test(
      'a Back-translation row an older build left in the Outbox is removed by the first send and never reaches the room',
      () async {
        final dir = Directory(p.join(home.path, 'guardadas'))
          ..createSync(recursive: true);
        for (final name in ['retro_1.m4a', 'ensaio_1.m4a']) {
          File(p.join(dir.path, name)).writeAsStringSync('a equipe contou');
        }
        File(p.join(dir.path, 'fila.json')).writeAsStringSync(
          '[{"id":"antiga-retro","path":"${dir.path}/retro_1.m4a",'
          '"session_id":"sessao-1","kind":"retro","scope":"inteira",'
          '"stored":false,"attempts":0},'
          '{"id":"antiga-parte","path":"${dir.path}/ensaio_1.m4a",'
          '"session_id":"sessao-1","kind":"ensaio","scope":"inteira",'
          '"stored":false,"attempts":0}]',
        );
        final room = FakeRoom();
        final queue = TakeUploadQueue(
          room: room,
          home: () async => home,
          recordings: FakeRecorder.new,
        )..tapped('antiga-parte');

        await queue.flush();

        expect(room.takesKept, ['ensaio/inteira']);
        expect(await queue.entries(), isEmpty);
        expect(File(p.join(dir.path, 'retro_1.m4a')).existsSync(), isFalse);
      },
    );

    test(
      'a Back-translation row whose copy the tablet cannot delete still leaves the Outbox, and the part behind it still goes up',
      () async {
        final dir = Directory(p.join(home.path, 'guardadas'))
          ..createSync(recursive: true);
        Directory(p.join(dir.path, 'retro_1.m4a')).createSync();
        File(
          p.join(dir.path, 'retro_1.m4a', 'dentro'),
        ).writeAsStringSync('o disco não deixa apagar');
        File(
          p.join(dir.path, 'ensaio_1.m4a'),
        ).writeAsStringSync('a equipe contou');
        File(p.join(dir.path, 'fila.json')).writeAsStringSync(
          '[{"id":"antiga-retro","path":"${dir.path}/retro_1.m4a",'
          '"session_id":"sessao-1","kind":"retro","scope":"inteira",'
          '"stored":false,"attempts":0},'
          '{"id":"antiga-parte","path":"${dir.path}/ensaio_1.m4a",'
          '"session_id":"sessao-1","kind":"ensaio","scope":"inteira",'
          '"stored":false,"attempts":0}]',
        );
        final room = FakeRoom();
        final queue = TakeUploadQueue(
          room: room,
          home: () async => home,
          recordings: FakeRecorder.new,
        )..tapped('antiga-parte');

        await queue.flush();

        expect(room.takesKept, ['ensaio/inteira']);
        expect(await queue.entries(), isEmpty);
      },
    );
  });
}
