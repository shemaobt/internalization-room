import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;
import 'session_notifier_test.dart' show settle;

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
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await pumpSala(tester, harness);

      container.read(salaSessionProvider.notifier).conviteTap();
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
      final harness = SalaHarness(lingua: 'en');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.conviteTap();
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
    'every line the room can name is in the bundle, in every language it speaks',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final named = RegExp(r'^[A-Z]\d+$');
      for (final language in languages) {
        final manifest = await rootBundle.loadString(
          'assets/audio/$language/manifest.json',
        );
        final rendered = (jsonDecode(manifest) as Map<String, dynamic>).keys
            .where(named.hasMatch)
            .toSet();
        final spoken = {...rendered, ...instantAckLines, 'E0', approvedLine};

        expect(
          spoken.length,
          greaterThan(instantAckLines.length),
          reason:
              'metade das falas fixas chega do servidor pelo nome e não é citada em '
              'nenhuma const do app — sem o manifesto, este teste só olharia as que já '
              'estavam listadas aqui',
        );
        for (final line in spoken) {
          await rootBundle.load(fixedLineAsset(line, language));
        }
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
    'the languages carry the same lines, so a turn in one is a turn in all',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final named = RegExp(r'^[A-Z]\d+$');
      final shipped = <String, String>{};
      for (final language in languages) {
        final manifest = await rootBundle.loadString(
          'assets/audio/$language/manifest.json',
        );
        final recorded = (jsonDecode(manifest) as Map<String, dynamic>).keys;
        shipped[language] = (recorded.where(named.hasMatch).toList()..sort())
            .join(',');
      }

      expect(
        shipped.values.toSet(),
        hasLength(1),
        reason:
            'o servidor manda o nome da fala no meio de um turno e o app resolve o '
            'nome dentro do pacote do idioma — uma renderização que pulou uma fala em um '
            'idioma vira silêncio, que a equipe não distingue de um tablet morto',
      );
      expect(shipped[floorLanguage], isNotEmpty);
    },
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
    dotenv.testLoad(
      fileInput:
          'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
    );
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
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      tester.platformDispatcher.localesTestValue = const [Locale('pt')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(filaEmMemoria: true, lingua: null);
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.conviteTap();
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
    'the dev language button recreates an already-open panorama instead of falling to the wheel',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      expect(
        container.read(salaSessionProvider).conviteStep,
        ConviteStep.entrada,
        reason:
            'o panorama precisa estar de fato aberto e dito para este teste valer a '
            'pena — o #178 só cobria o instante logo após o toque no círculo, antes de a '
            'abertura terminar',
      );
      expect(container.read(salaSessionProvider).voice, VoiceState.invite);

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.convite,
        reason:
            'o botão de idioma é para o DEV ouvir o panorama noutra língua — jogar '
            'para a roda abandona exatamente a sessão que ele estava tentando testar',
      );
      expect(
        harness.room.sessionIds,
        hasLength(2),
        reason:
            'a sessão antiga ficou presa na língua velha; testar a nova pede uma '
            'sessão nova, sem esperar um segundo toque no círculo',
      );
    },
  );

  test(
    'the dev language button on an open panorama does not enter the passage the room answers with instead',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      harness.room.panoramaAnsweredWith = 'P01';

      final sessionsAntes = [...harness.room.sessionsSpokenTo];

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).conviteStep,
        ConviteStep.boasVindas,
        reason:
            'a sala já tinha dado o panorama uma vez; pedi-lo de novo é um pedido, '
            'não uma instrução, e a sala pode responder com uma passagem de verdade — '
            'entrar nela e dizê-la como se fosse o panorama é o que o teste manual do '
            'João viu em 21/09: uma passagem falada e ouvida como se fosse a visão geral',
      );
      expect(
        harness.room.sessionsSpokenTo,
        sessionsAntes,
        reason:
            'a sessão que a sala devolveu no lugar do panorama nunca chega a ser '
            'aberta nem dita',
      );
      expect(
        container.read(salaSessionProvider).sessionId,
        isNull,
        reason: 'nenhuma passagem foi de fato aberta a partir do botão de DEV',
      );
    },
  );

  test(
    'the dev language button keeps the panorama when the room answers the ask for OV with OV-Ruth',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      expect(harness.room.languagesSent, ['pt']);
      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.convite,
        reason:
            'a sala respondeu "OV-Ruth" ao pedido "OV" — é o id real do panorama, '
            'não uma passagem; o simulador do João em 21/09 caiu em conversa aqui',
      );
      expect(
        container.read(salaSessionProvider).conviteStep,
        ConviteStep.entrada,
      );
      expect(container.read(salaSessionProvider).voice, VoiceState.invite);

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.convite,
        reason:
            'no aparelho do João o panorama tinha sido aberto como conversa e o '
            'botão de idioma, sem panorama anotado, recomeçou da roda',
      );
      expect(
        harness.room.sessionIds,
        hasLength(2),
        reason: 'a língua nova pede uma sessão nova do panorama',
      );
      expect(harness.room.languagesSent, ['pt', 'en']);
      expect(
        harness.emAberto.rows.keys,
        isNot(contains('Ruth/OV-Ruth')),
        reason:
            'o panorama não é uma passagem em curso — o em_curso.json do simulador '
            'guardou {"Ruth/OV-Ruth": {"stage": "conversa"}} e foi daí que a roda veio',
      );
    },
  );

  test(
    'the dev language button on the wheel restarts the room, even after the panorama was said',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      await notifier.abrirEscolha();
      await settle();
      expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
      expect(harness.room.languagesAsked, ['pt']);

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).voice,
        isNot(VoiceState.thinking),
        reason:
            'o panorama já dito vencia em qualquer etapa e o botão reabria o '
            'convite de dentro da roda; openConvite voltava no próprio guard e a sala '
            'ficava pensando para sempre, com uma sessão nova abandonada no servidor',
      );
      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.escolha,
        reason:
            'a dica do botão promete recomeçar a sala — na roda, é a roda que '
            'volta, na língua nova',
      );
      expect(harness.room.languagesAsked, ['pt', 'en']);
      expect(
        harness.room.sessionIds,
        hasLength(1),
        reason:
            'fora do convite não há panorama para reabrir; a sessão nova é pedida '
            'quando a equipe tocar o convite de novo',
      );
    },
  );

  test(
    'the dev language button survives the room failing to give the panorama again',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      expect(harness.room.sessionIds, hasLength(1));
      harness.room.failCreateOnceWith = const RoomBroke('HTTP 500');

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).needsPerson,
        isTrue,
        reason:
            'a cópia do pedido do panorama não tinha try/catch e rodava solta: um '
            '500 estourava sem ninguém para pegar e a sala ficava pensando; hoje o '
            'try/catch existe e um 500 numa chamada de turno para a sala na hora',
      );

      harness.room.theDeskAttended();
      notifier.resolveWithPerson();
      await waitFor(
        'o círculo voltar ao convite',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );

      notifier.conviteTap();
      await settle();

      expect(
        harness.room.sessionIds,
        hasLength(2),
        reason:
            'a falha deixava o trinco do convite fechado para o resto da sessão — '
            'nem o toque no círculo pedia o panorama de novo',
      );
      expect(
        harness.room.languagesSent,
        ['pt', 'en'],
        reason:
            'o pedido que falhou não conta; o toque pede o panorama na língua nova',
      );
    },
  );

  test(
    'the dev language button with no network goes offline instead of thinking forever',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      final harness = SalaHarness(lingua: null);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      harness.network.radioSeesNothing = true;

      notifier.devTrocarIdioma();
      await settle();

      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.offline,
        reason:
            'openConvite olha o rádio antes de pedir a sala; a cópia não olhava',
      );
      expect(
        harness.room.sessionIds,
        hasLength(1),
        reason: 'sem rede não há pedido a fazer',
      );
    },
  );

  test(
    'the dev language button drops an armed hand along with the panorama it was armed on',
    () async {
      dotenv.testLoad(
        fileInput:
            'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
      );
      addTearDown(() => dotenv.testLoad(fileInput: ''));
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.openConvite();
      notifier.handTap();
      expect(container.read(salaSessionProvider).noteMode, isTrue);

      notifier.devTrocarIdioma();

      expect(
        container.read(salaSessionProvider).noteMode,
        isFalse,
        reason:
            'a mão continuava armada da sessão que a troca de idioma acabou de '
            'largar; o próximo toque no círculo abria o microfone em vez do panorama '
            'novo, e a pergunta gravada não tinha para onde ir — a sessão que ela mirava '
            'já tinha sido zerada pela própria troca',
      );

      notifier.conviteTap();
      await settle();

      expect(
        harness.room.sessionIds,
        hasLength(2),
        reason:
            'o toque depois do botão é o que abre o panorama na língua nova, não '
            'uma pergunta gravada para uma sessão que não existe mais',
      );
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
          bySemanticsLabelWidget(expected[language]!),
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
          bySemanticsLabelWidget(expected[language]!),
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
