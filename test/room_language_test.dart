import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, enterThePanorama, settle;

const _livroComPanorama = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
];

void main() {
  test(
    'a device that speaks none of the room\'s languages is answered in English',
    () {
      expect(languageFor(['ja']), floorLanguage);
      expect(languageFor(['ko', 'th']), floorLanguage);
      expect(languageFor(const <String>[]), floorLanguage);
    },
  );

  test(
    'a device that speaks a room language second is answered in it, not in the floor',
    () {
      expect(
        languageFor(['ca', 'pt', 'en']),
        'pt',
        reason:
            'ler só a primeira preferência jogava para o piso uma equipe cujo idioma '
            'estava logo ali na lista do aparelho',
      );
    },
  );

  test('the region on a locale never decides which room a team gets', () {
    expect(languageFor(['pt']), 'pt');
    expect(languageFor(['PT']), 'pt');
  });

  testWidgets(
    'a Brazilian tablet is a Portuguese room, not a language of its own',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(roomLanguageProvider), 'pt');
    },
  );

  testWidgets(
    'a tablet in a language the room does not speak opens in English',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ja')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(roomLanguageProvider), floorLanguage);
    },
  );

  testWidgets(
    'the room does not change language under a team already in a passage',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pt')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(filaEmMemoria: true, lingua: null)
        ..room.passages = _livroComPanorama;
      final container = await pumpSala(tester, harness);

      await tester.pump(const Duration(milliseconds: 300));
      container.read(salaSessionProvider.notifier).entrarNaOferecida();
      await tester.pump(const Duration(milliseconds: 300));
      tester.platformDispatcher.localesTestValue = const [Locale('en')];
      container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        harness.room.languagesSent,
        everyElement('pt'),
        reason:
            'a língua trocando no meio de uma passagem é pior do que qualquer uma das '
            'duas — a equipe ouve metade do trecho numa e metade noutra',
      );
      expect(harness.room.languagesAsked, everyElement('pt'));
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

  test(
    'the bundle carries the notices the room says without a server, and none of her lines',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      const notices = {
        'pt': {'sem_conexao', 'gravacao_presa', 'microfone'},
        'en': {'sem_conexao', 'gravacao_presa', 'microfone'},
      };
      for (final language in languages) {
        final manifest = await rootBundle.loadString(
          'assets/audio/$language/manifest.json',
        );

        expect(
          (jsonDecode(manifest) as Map<String, dynamic>).keys.toSet(),
          notices[language],
          reason:
              'as falas dela iam gravadas no app, e uma gravação antiga podia '
              'tocar depois de ela mudar a letra',
        );
        await expectLater(
          () => rootBundle.load('assets/audio/$language/fixed/F0.mp3'),
          throwsA(anything),
        );
        for (final asset in [
          offlineNoticeAsset,
          micBlockedAsset,
          strandedTakeAsset,
        ]) {
          await rootBundle.load(asset(language));
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the dev knob walks the languages the room claims and comes back round',
    () {
      final container = SalaHarness(lingua: null).container();
      addTearDown(container.dispose);
      final knob = container.read(devLanguageProvider.notifier);

      final walked = <String>[];
      var standing = languages.first;
      for (var step = 0; step < languages.length; step++) {
        standing = knob.next(standing);
        walked.add(standing);
      }

      expect(walked.toSet(), languages.toSet());
      expect(
        standing,
        languages.first,
        reason:
            'o botão precisa voltar ao começo, senão dá para ficar preso num idioma',
      );
    },
  );

  test('the dev knob is refused a language the room does not speak', () {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = SalaHarness(lingua: null).container();
    addTearDown(container.dispose);

    container.read(devLanguageProvider.notifier).choose('ja');

    expect(
      container.read(devLanguageProvider),
      isNull,
      reason:
          'a sala pediria ao servidor um idioma que ele recusa, e a passagem não abre',
    );
  });

  testWidgets(
    'changing the language in dev opens a new room rather than moving this one',
    (tester) async {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      tester.platformDispatcher.localesTestValue = const [Locale('pt')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(filaEmMemoria: true, lingua: null)
        ..room.passages = _livroComPanorama;
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      await tester.pump(const Duration(milliseconds: 300));
      notifier.entrarNaOferecida();
      await tester.pump(const Duration(milliseconds: 300));
      final antes = [...harness.room.languagesSent];
      notifier.devTrocarIdioma();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(roomLanguageProvider), isNot('pt'));
      expect(
        harness.room.languagesSent.take(antes.length),
        everyElement('pt'),
        reason:
            'a sessão que já existia não pode passar a responder noutra língua — '
            'trocar o idioma abre uma sala nova, nunca move a que está aberta',
      );
      expect(
        container.read(salaSessionProvider).sessionId,
        isNull,
        reason:
            'trocar o idioma sem largar a sessão deixaria a equipe ouvindo metade '
            'da passagem numa língua e metade noutra',
      );
    },
  );

  test(
    'the dev language button on the wheel restarts the room, even after the panorama was said',
    () async {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null)
        ..room.passages = _livroComPanorama;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePanorama(notifier, read);
      await waitFor('o panorama ser dito', () => read().panoramaSaid);
      await notifier.abrirEscolha();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      expect(harness.room.languagesAsked, everyElement('pt'));

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).voice,
        isNot(VoiceState.thinking),
        reason:
            'o botão recomeça a sala; ficar pensando para sempre deixaria uma '
            'sessão nova abandonada no servidor',
      );
      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.escolha,
        reason:
            'a dica do botão promete recomeçar a sala — na roda, é a roda que '
            'volta, na língua nova',
      );
      expect(harness.room.languagesAsked.last, 'en');
      expect(
        harness.room.sessionIds,
        hasLength(1),
        reason:
            'na roda não há panorama para reabrir; a sessão nova é pedida '
            'quando a equipe tocar o panorama de novo',
      );
    },
  );

  test(
    'the dev language button on the Panorama restarts the room on the Choice in '
    'the new language',
    () async {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://x\nDEV_PULAR_FASES=1');
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null)
        ..room.passages = _livroComPanorama;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePanorama(notifier, read);
      await waitFor('o panorama ser dito', () => read().panoramaSaid);

      notifier.devTrocarIdioma();
      await waitFor('a roda voltar', () => read().naRoda != null);

      expect(read().station, isA<Menu>());
      expect(harness.room.languagesAsked.last, 'en');
    },
  );

  test(
    'a tablet set to the language nobody approved opens the room in English',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      expect(
        languages,
        isNot(contains('es')),
        reason:
            'a sala reivindicava espanhol sem que ninguém tivesse aprovado a língua, '
            'e um tablet em espanhol ouvia dezessete falas que o próprio arquivo dizia '
            'serem rascunho',
      );
      expect(
        languageFor(['es']),
        floorLanguage,
        reason:
            'um tablet numa língua que a sala não fala tem de abrir, não parar — o '
            'piso existe para isso',
      );
      await expectLater(
        rootBundle.loadString('assets/audio/es/manifest.json'),
        throwsA(anything),
        reason:
            'os clipes em espanhol continuavam embarcados, então bastava a lista de '
            'idiomas voltar a citá-los para a equipe ouvir rascunho de novo',
      );
    },
  );

  testWidgets(
    'the one screen a person reads is in the language they set the tablet to',
    (tester) async {
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
    },
  );

  testWidgets(
    'the screen waiting for a code is in the language they set the tablet to',
    (tester) async {
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
    },
  );

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
