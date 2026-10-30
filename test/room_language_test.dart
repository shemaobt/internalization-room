import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_language_ledger.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart'
    show byLabel, enterThePanorama, enterThePassage, relaunch, settle;
import 'um_ensaio_de_tres_partes.dart' show Sala, gravarUmaParteDoEnsaio;

const _livroComPanorama = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
];

class _AnEnglishReadHeldOnTheDisk extends FakeWorkInProgress {
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() => _gate?.complete();

  @override
  Future<Set<String>> startedIn(String book, String language) async {
    if (language == 'en') await _gate?.future;
    return super.startedIn(book, language);
  }
}

Sala _aTabletWithNothingChosen({FakeRoomLanguageLedger? chosen}) {
  final harness = SalaHarness(lingua: null, roomLanguage: chosen);
  final container = harness.container();
  addTearDown(container.dispose);
  return Sala(harness, container);
}

Future<void> _inThePassage(Sala it, String pericope) async {
  final played = it.harness.voice.played.length;
  await enterThePassage(it.sala, () => it.estado, pericope);
  await waitFor(
    'the passage to stand open',
    () =>
        it.estado.sessionId != null &&
        it.harness.voice.played.length > played &&
        it.estado.voice == VoiceState.invite,
  );
  await settle();
}

Future<void> _leftForTheChoice(Sala it) async {
  it.sala.leaveThePassage();
  await waitFor(
    'the Choice to offer the way back',
    () => it.estado.theWayBackIsLive,
  );
}

Future<void> _choose(Sala it, String language) async {
  it.sala.chooseTheLanguage(language);
  await waitFor(
    'the Wheel to stand in the language chosen',
    () =>
        it.container.read(roomLanguageProvider) == language &&
        it.estado.naRoda != null &&
        it.estado.voice == VoiceState.invite,
  );
  await settle();
}

void main() {
  for (final locale in const [Locale('en'), Locale('es'), Locale('ja')]) {
    testWidgets(
      'a tablet set to ${locale.languageCode} with nothing chosen opens its session '
      'in Portuguese, voice and screen',
      (tester) async {
        tester.platformDispatcher.localesTestValue = [locale];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final harness = SalaHarness(filaEmMemoria: true, lingua: null);
        final container = await pumpSala(tester, harness);
        await tester.pump(const Duration(milliseconds: 300));

        expect(container.read(roomLanguageProvider), 'pt');
        expect(find.text('Escolha a passagem'), findsOneWidget);

        await tester.tap(find.text('Rute 1:1–5'));
        await tester.pump(const Duration(milliseconds: 300));

        expect(harness.room.languagesAsked, isNotEmpty);
        expect(harness.room.languagesAsked, everyElement('pt'));
        expect(
          harness.room.languagesSent,
          ['pt'],
          reason:
              'a língua do aparelho nunca escolhe a da sessão: sem escolha da '
              'equipe, a sala é em português',
        );
      },
    );
  }

  test(
    'the team\'s «EN» outlives closing the app and the next session opens in English',
    () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final chosen = FakeRoomLanguageLedger();
      final first = _aTabletWithNothingChosen(chosen: chosen);
      await first.sala.abrirEscolha();
      await settle();
      first.sala.chooseTheLanguage('en');
      await settle();

      final (harness, container) = await relaunch(
        first.harness,
        first.container,
      );
      final again = Sala(harness, container);

      expect(container.read(roomLanguageProvider), 'en');

      await _inThePassage(again, 'P01');
      final english = again.estado.sessionId;

      expect(harness.room.languagesSent.last, 'en');

      final (harness3, container3) = await relaunch(harness, container);
      final third = Sala(harness3, container3);
      await third.sala.openTheRoom();
      await waitFor(
        'the relaunch to land on the English session',
        () => third.estado.sessionId == english,
      );

      expect(third.estado.station, isNot(isA<Menu>()));
    },
  );

  test(
    'a Portuguese session left for the Choice keeps speaking Portuguese after «EN» '
    'is chosen',
    () async {
      final it = _aTabletWithNothingChosen();
      await _inThePassage(it, 'P01');
      final portuguese = it.estado.sessionId;
      await _leftForTheChoice(it);

      await _choose(it, 'en');

      expect(
        it.estado.theWayBackIsLive,
        isTrue,
        reason:
            'escolher a língua não recomeça a sala nem apaga o caminho de volta',
      );

      await it.sala.returnToTheLeftEntry();
      await waitFor(
        'the team to be back in the session they left',
        () => it.estado.sessionId == portuguese,
      );
      await settle();

      expect(it.estado.sessionId, portuguese);
      expect(
        it.harness.room.languagesSent,
        isNot(contains('en')),
        reason:
            'a sessão aberta em português continua em português; nenhuma sessão '
            'inglesa nasce na volta',
      );
      expect((await it.harness.currentSession.read())?.language, 'pt');
    },
  );

  test(
    'a relaunch after going back to the Portuguese session with «EN» chosen lands '
    'on it',
    () async {
      final it = _aTabletWithNothingChosen();
      await _inThePassage(it, 'P01');
      final portuguese = it.estado.sessionId;
      await _leftForTheChoice(it);
      await _choose(it, 'en');
      await it.sala.returnToTheLeftEntry();
      await waitFor(
        'the team to be back in the Portuguese session',
        () => it.estado.sessionId == portuguese,
      );
      await settle();

      final (harness, container) = await relaunch(it.harness, it.container);
      final again = Sala(harness, container);
      await again.sala.openTheRoom();
      await waitFor(
        'the relaunch to land on the Portuguese session',
        () => again.estado.sessionId == portuguese,
      );

      expect(harness.room.languagesSent, isNot(contains('en')));
    },
  );

  test(
    'the language a passage opens in is the one chosen when the team tapped it',
    () async {
      final it = _aTabletWithNothingChosen();
      await it.sala.abrirEscolha();
      await waitFor(
        'the Wheel to offer a passage',
        () => it.estado.entriesOpen,
      );
      it.harness.room.holdNextCreate();
      it.sala.openTheEntry(it.estado.naRoda!.first);
      await waitFor(
        'the session to be in the air',
        () => it.harness.room.createHeld,
      );

      it.sala.chooseTheLanguage('en');
      await settle();
      it.harness.room.finishHeldCreate();
      await waitFor(
        'the session to be asked for',
        () => it.harness.room.languagesSent.isNotEmpty,
      );

      expect(it.container.read(roomLanguageProvider), 'en');
      expect(it.harness.room.languagesSent, ['pt']);
    },
  );

  test(
    'a passage with a Portuguese session opened in English starts its own session '
    'and carries none of the Portuguese work',
    () async {
      final it = _aTabletWithNothingChosen();
      await _inThePassage(it, 'P01');
      final portuguese = it.estado.sessionId;
      it.sala.goEnsaio();
      await gravarUmaParteDoEnsaio(it, 1);
      await settle();
      await _leftForTheChoice(it);
      await _choose(it, 'en');

      await _inThePassage(it, 'P01');

      expect(it.harness.room.languagesSent.last, 'en');
      expect(it.estado.sessionId, isNot(portuguese));
      expect(it.estado.keptTakes, isEmpty);
      expect(it.estado.station, isA<Canvas>());
      expect(
        (await it.harness.emAberto.of('Ruth', 'P01', 'pt'))?.sessionId,
        portuguese,
        reason: 'o ponto de retomada português continua guardado',
      );
    },
  );

  test(
    'reopening the passage in Portuguese resumes the Portuguese session where the '
    'team stopped',
    () async {
      final it = _aTabletWithNothingChosen();
      await _inThePassage(it, 'P01');
      final portuguese = it.estado.sessionId;
      it.sala.goEnsaio();
      await gravarUmaParteDoEnsaio(it, 1);
      final takes = [for (final take in it.estado.keptTakes) take.path];
      await settle();
      await _leftForTheChoice(it);
      await _choose(it, 'en');
      await _inThePassage(it, 'P01');
      await _leftForTheChoice(it);
      await _choose(it, 'pt');
      final created = it.harness.room.sessionIds.length;

      await enterThePassage(it.sala, () => it.estado, 'P01');
      await waitFor(
        'the Portuguese session to stand where the team stopped',
        () =>
            it.estado.sessionId == portuguese &&
            it.estado.station is Ensaio &&
            it.estado.keptTakes.isNotEmpty,
      );

      expect(it.harness.room.sessionIds, hasLength(created));
      expect([for (final take in it.estado.keptTakes) take.path], takes);
    },
  );

  test(
    'leaving a halted session and choosing another language ends every watch of '
    'that session',
    () async {
      final it = _aTabletWithNothingChosen();
      await enterThePassage(it.sala, () => it.estado, 'P01');
      await waitFor(
        'the opening to be said',
        () =>
            !it.estado.awaitingTheGuide && it.estado.voice == VoiceState.invite,
      );
      it.harness.room.failTurnsWith = const Refused('BAD_REQUEST');
      it.sala.conversaTap();
      await waitFor(
        'the microphone to open',
        () => it.estado.voice == VoiceState.listening,
      );
      it.sala.conversaTap();
      await waitFor('the halt to stand', () => it.estado.needsPerson);
      it.sala.leaveThePassage();
      await waitFor(
        'the Choice to show its Wheel',
        () => it.estado.station is Menu && it.estado.naRoda != null,
      );
      await _choose(it, 'en');

      final reads = it.harness.room.calls
          .where((c) => c == 'fetchState')
          .length;
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(
        it.harness.room.calls.where((c) => c == 'fetchState'),
        hasLength(reads),
        reason:
            'a vigia da sessão parada continuava lendo-a a cada 30 s depois de a '
            'equipe ter saído',
      );

      await enterThePassage(it.sala, () => it.estado, 'P01');
      await waitFor(
        'a session to be asked for in English',
        () => it.harness.room.languagesSent.length == 2,
      );

      expect(it.harness.room.languagesSent.last, 'en');
    },
  );

  testWidgets(
    'the dev language button chooses the language without starting the room over',
    (tester) async {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final harness = SalaHarness(filaEmMemoria: true, lingua: null)
        ..room.passages = _livroComPanorama;
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await tester.pump(const Duration(milliseconds: 300));
      notifier.openTheEntry(
        read().naRoda!.firstWhere((entry) => entry.pericope == 'P01'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final session = read().sessionId;
      notifier.leaveThePassage();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('idioma → pt'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(roomLanguageProvider), 'en');
      expect(read().station, isA<Menu>());
      expect(
        read().leftEntry?.session,
        session,
        reason:
            'o botão de idioma escolhia a língua recomeçando a sala, e a volta à '
            'passagem deixada se perdia',
      );
      expect(harness.room.sessionIds, hasLength(1));
    },
  );

  test(
    'a language tapped while the Wheel is first read lets that read land and '
    'relabels it, with no second read',
    () async {
      const portuguese = [
        Passagem(pericope: 'P01', audioUrl: '/voice/pt', book: 'Ruth'),
      ];
      final it = _aTabletWithNothingChosen();
      const english = [
        Passagem(pericope: 'P01', audioUrl: '/voice/en', book: 'Ruth'),
      ];
      it.harness.room.passagesIn = {'pt': portuguese, 'en': english};
      it.harness.emAberto.rows['Ruth/P01/en'] = const ResumePoint(
        sessionId: 'sessao-en',
        stage: SalaStage.ensaio,
      );
      final slow = it.harness.room.holdOneWheelRead();
      unawaited(it.sala.abrirEscolha());
      await settle();

      it.sala.chooseTheLanguage('en');
      await settle();
      slow.complete();
      await waitFor('the Wheel to land', () => it.estado.naRoda != null);
      await settle();

      expect(it.estado.naRoda, portuguese);
      expect(it.estado.comecadas, contains('P01'));
      expect(it.harness.room.languagesAsked, ['pt']);
    },
  );

  test(
    'a language tapped while the launch reads the Wheel, then another once the '
    'Wheel lands and its marks are still being read, leave the marks in the '
    'language last chosen',
    () async {
      const book = [
        Passagem(pericope: 'P01', audioUrl: '/voice/p01', book: 'Ruth'),
        Passagem(pericope: 'P02', audioUrl: '/voice/p02', book: 'Ruth'),
      ];
      final disk = _AnEnglishReadHeldOnTheDisk()
        ..rows['Ruth/P01/en'] = const ResumePoint(
          sessionId: 'sessao-en',
          stage: SalaStage.ensaio,
        )
        ..rows['Ruth/P02/pt'] = const ResumePoint(
          sessionId: 'sessao-pt',
          stage: SalaStage.ensaio,
        );
      final harness = SalaHarness(lingua: null, emAbertoNoDisco: disk)
        ..room.passages = book;
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      final slow = harness.room.holdOneWheelRead();
      unawaited(it.sala.openTheRoom());
      await settle();

      it.sala.chooseTheLanguage('en');
      await settle();
      disk.hold();
      slow.complete();
      await waitFor('the Wheel to land', () => it.estado.naRoda != null);
      it.sala.chooseTheLanguage('pt');
      disk.release();
      await settle();

      expect(it.estado.comecadas, {'P02'});
    },
  );

  test('a passage with only an English place is not started on the Portuguese '
      'Wheel', () async {
    final it = _aTabletWithNothingChosen();
    it.harness.emAberto.rows['Ruth/P02/en'] = const ResumePoint(
      sessionId: 'sessao-en',
      stage: SalaStage.ensaio,
    );

    await it.sala.abrirEscolha();
    await waitFor('the Wheel to be read', () => it.estado.naRoda != null);

    expect(it.estado.comecadas, isNot(contains('P02')));
  });

  test('a language the room does not speak is never chosen', () async {
    final it = _aTabletWithNothingChosen();
    await it.sala.abrirEscolha();
    await settle();

    it.sala.chooseTheLanguage('ja');
    await settle();

    expect(it.container.read(roomLanguageProvider), 'pt');
    expect(it.harness.room.languagesAsked, isNot(contains('ja')));

    final (_, container) = await relaunch(it.harness, it.container);

    expect(container.read(roomLanguageProvider), 'pt');
  });

  test(
    'the Panorama left in Portuguese comes back in Portuguese, and a new tap after '
    '«EN» opens an English one',
    () async {
      final harness = SalaHarness(lingua: null)
        ..room.passages = _livroComPanorama;
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await enterThePanorama(it.sala, () => it.estado);
      await waitFor('the Panorama to be said', () => it.estado.panoramaSaid);
      await _leftForTheChoice(it);
      await _choose(it, 'en');

      await enterThePanorama(it.sala, () => it.estado);
      await waitFor(
        'a Panorama session to be asked for',
        () => harness.room.languagesSent.length == 2,
      );

      expect(harness.room.languagesSent, ['pt', 'en']);
    },
  );

  test(
    'the room language chosen on one launch is the one the next launch reads',
    () async {
      final home = Directory.systemTemp.createTempSync('sala-lingua');
      addTearDown(() => home.deleteSync(recursive: true));
      final first = await RoomLanguageLedger.read(home: () async => home);

      expect(first.chosen, isNull);

      await first.choose('en');
      final again = await RoomLanguageLedger.read(home: () async => home);

      expect(again.chosen, 'en');
    },
  );

  test(
    'a room asks the wheel and the session for the language it is speaking',
    () async {
      final harness = SalaHarness(lingua: 'en')
        ..room.passages = _livroComPanorama;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await enterThePanorama(
        notifier,
        () => container.read(salaSessionProvider),
      );
      await waitFor(
        'a sala receber o idioma',
        () => harness.room.languagesSent.isNotEmpty,
      );
      await notifier.abrirEscolha();
      await settle();

      expect(
        harness.room.languagesSent,
        everyElement('en'),
        reason:
            'nada do que a sala fala é feito no tablet — um pedido que não diz a '
            'língua volta no idioma padrão do servidor e a equipe ouve outra',
      );
      expect(harness.room.languagesAsked, everyElement('en'));
    },
  );

  test('the language nobody approved is neither claimed nor bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    expect(
      languages,
      isNot(contains('es')),
      reason:
          'a sala reivindicava espanhol sem que ninguém tivesse aprovado a língua, '
          'e um tablet em espanhol ouvia dezessete falas que o próprio arquivo dizia '
          'serem rascunho',
    );
    await expectLater(
      rootBundle.loadString('assets/audio/es/manifest.json'),
      throwsA(anything),
      reason:
          'os clipes em espanhol continuavam embarcados, então bastava a lista de '
          'idiomas voltar a citá-los para a equipe ouvir rascunho de novo',
    );
  });

  testWidgets('the one screen a person reads is in the room language', (
    tester,
  ) async {
    const showing = ClaimCode(deviceId: 'aparelho-1', code: 'QHF-3M7K');
    const expected = {
      'pt': 'Mostre este código ao facilitador',
      'en': 'Show this code to the facilitator',
    };

    for (final language in languages) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CodigoView(code: showing, language: language),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        byLabel(expected[language]!),
        findsOneWidget,
        reason:
            'o facilitador lê esta tela uma vez, na instalação — num aparelho que ele '
            'configurou, numa língua que ele não escolheu, não dá para saber se ainda '
            'está esperando ou se já pode digitar',
      );
      expect(
        find.byType(Text),
        findsOneWidget,
        reason: 'o código é a única palavra escrita que a sala mostra',
      );
    }
  });

  testWidgets('the screen waiting for a code is in the room language', (
    tester,
  ) async {
    const expected = {
      'pt': 'A sala está preparando o código deste aparelho',
      'en': 'The room is getting a code for this tablet',
    };

    for (final language in languages) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodigoView(language: language)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(
        byLabel(expected[language]!),
        findsOneWidget,
        reason:
            'esta tela falava as duas línguas por um switch próprio, que o guard '
            'de completude não via; este teste é a cobertura que faltava, não '
            'o conserto de uma tela muda',
      );
    }
  });

  test('the código screen names no language of its own, in any spelling', () {
    final source = File(
      'lib/features/sala/presentation/widgets/codigo_view.dart',
    ).readAsStringSync();

    expect(
      RegExp(r"'pt'|'en'|language ==|switch \(language\)").hasMatch(source),
      isFalse,
      reason:
          'um switch, um ternário ou um mapa local com o literal da língua '
          'escondem esta tela do guard que anda por cada tabela — uma terceira '
          'língua aprovada cairia em inglês aqui com o guard verde',
    );
  });
}
