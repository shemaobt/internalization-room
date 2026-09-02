import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/app_theme.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;
import 'session_notifier_test.dart' show settle;

void main() {
  test('a device that speaks none of the room\'s languages is answered in English', () {
    expect(languageFor(['ja']), floorLanguage);
    expect(languageFor(['ko', 'th']), floorLanguage);
    expect(languageFor(const <String>[]), floorLanguage);
  });

  test('a device that speaks a room language second is answered in it, not in the floor', () {
    expect(languageFor(['ca', 'pt', 'en']), 'pt',
        reason: 'ler só a primeira preferência jogava para o piso uma equipe cujo idioma '
            'estava logo ali na lista do aparelho');
  });

  test('the region on a locale never decides which room a team gets', () {
    expect(languageFor(['pt']), 'pt');
    expect(languageFor(['PT']), 'pt');
  });

  testWidgets('a Brazilian tablet is a Portuguese room, not a language of its own',
      (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(roomLanguageProvider), 'pt');
  });

  testWidgets('a tablet in a language the room does not speak opens in English',
      (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(roomLanguageProvider), floorLanguage);
  });

  testWidgets('the room does not change language under a team already in a passage',
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

    expect(harness.room.languagesSent, everyElement('pt'),
        reason: 'a língua trocando no meio de uma passagem é pior do que qualquer uma das '
            'duas — a equipe ouve metade do trecho numa e metade noutra');
    expect(harness.room.languagesAsked, everyElement('pt'));
  });

  test('a room asks the wheel and the session for the language it is speaking', () async {
    final harness = SalaHarness(lingua: 'en');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conviteTap();
    await waitFor('a sala receber o idioma', () => harness.room.languagesSent.isNotEmpty);
    await notifier.abrirEscolha();
    await settle();

    expect(harness.room.languagesSent, everyElement('en'),
        reason: 'nada do que a sala fala é feito no tablet — um pedido que não diz a '
            'língua volta no idioma padrão do servidor e a equipe ouve outra');
    expect(harness.room.languagesAsked, everyElement('en'));
  });

  test('every line the room can name is in the bundle, in every language it speaks',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final named = RegExp(r'^[A-Z]\d+$');
    for (final language in languages) {
      final manifest = await rootBundle.loadString('assets/audio/$language/manifest.json');
      final rendered = (jsonDecode(manifest) as Map<String, dynamic>).keys
          .where(named.hasMatch)
          .toSet();
      final spoken = {
        ...rendered,
        ...instantAckLines,
        ...inaudibleLines,
        ...handoffLines,
        needsPersonLine,
      };

      expect(spoken.length, greaterThan(instantAckLines.length),
          reason: 'metade das falas fixas chega do servidor pelo nome e não é citada em '
              'nenhuma const do app — sem o manifesto, este teste só olharia as que já '
              'estavam listadas aqui');
      for (final line in spoken) {
        await rootBundle.load(fixedLineAsset(line, language));
      }
      for (final asset in [
        offlineNoticeAsset,
        inviteToStartAsset,
        micBlockedAsset,
        strandedTakeAsset,
      ]) {
        await rootBundle.load(asset(language));
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the languages carry the same lines, so a turn in one is a turn in all', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final named = RegExp(r'^[A-Z]\d+$');
    final shipped = <String, String>{};
    for (final language in languages) {
      final manifest = await rootBundle.loadString('assets/audio/$language/manifest.json');
      final recorded = (jsonDecode(manifest) as Map<String, dynamic>).keys;
      shipped[language] = (recorded.where(named.hasMatch).toList()..sort()).join(',');
    }

    expect(shipped.values.toSet(), hasLength(1),
        reason: 'o servidor manda o nome da fala no meio de um turno e o app resolve o '
            'nome dentro do pacote do idioma — uma renderização que pulou uma fala em um '
            'idioma vira silêncio, que a equipe não distingue de um tablet morto');
    expect(shipped[floorLanguage], isNotEmpty);
  });

  test('the dev knob walks the languages the room claims and comes back round', () {
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
    expect(standing, languages.first,
        reason: 'o botão precisa voltar ao começo, senão dá para ficar preso num idioma');
  });

  test('the dev knob is refused a language the room does not speak', () {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
    );
    addTearDown(() => dotenv.testLoad(fileInput: ''));
    final container = SalaHarness(lingua: null).container();
    addTearDown(container.dispose);

    container.read(devLanguageProvider.notifier).choose('ja');

    expect(container.read(devLanguageProvider), isNull,
        reason: 'a sala pediria ao servidor um idioma que ele recusa, e a passagem não abre');
  });

  testWidgets('changing the language in dev opens a new room rather than moving this one',
      (tester) async {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://x\nINTERNALIZATION_ROOM_KEY=k\nDEV_PULAR_FASES=1',
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
    expect(harness.room.languagesSent.take(antes.length), everyElement('pt'),
        reason: 'a sessão que já existia não pode passar a responder noutra língua — '
            'trocar o idioma abre uma sala nova, nunca move a que está aberta');
    expect(container.read(salaSessionProvider).sessionId, isNull,
        reason: 'trocar o idioma sem largar a sessão deixaria a equipe ouvindo metade '
            'da passagem numa língua e metade noutra');
  });

  testWidgets('the one screen a person reads is in the language they set the tablet to',
      (tester) async {
    const showing = ClaimCode(deviceId: 'aparelho-1', code: 'QHF-3M7K');
    const expected = {
      'pt': 'Mostre este código ao facilitador',
      'es': 'Muestre este código al facilitador',
      'en': 'Show this code to the facilitator',
    };

    for (final language in languages) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodigoView(code: showing, language: language)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(bySemanticsLabelWidget(expected[language]!), findsOneWidget,
          reason: 'o facilitador lê esta tela uma vez, na instalação — num aparelho que ele '
              'configurou, numa língua que ele não escolheu, não dá para saber se ainda '
              'está esperando ou se já pode digitar');
      expect(find.byType(Text), findsOneWidget,
          reason: 'o código é a única palavra escrita que a sala mostra');
    }
  });
}
