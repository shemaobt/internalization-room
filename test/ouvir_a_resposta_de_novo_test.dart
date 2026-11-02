import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'onde_mora_o_erro_test.dart'
    show harnessDaVez, notifier, pumpToPergunta, terminei, traduzirDeNovo;
import 'scenario_helpers.dart' show settle;
import 'tocar_vira_pausar_test.dart' show pumpAoApontado, harnessApontando;

const _oVereditoDeSeguranca =
    '/api/internalization-room/voice/veredito-de-seguranca';

void main() {
  group('ouvir a resposta de novo', () {
    test('repete a fala do veredito, não o trecho', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      final linha = container.read(salaSessionProvider).lastSpoken;
      expect(linha, isNotNull, reason: 'o veredito falou e foi lembrado');

      final tocadosAntes = harness.voice.played.length;

      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'a resposta tocar de novo',
        () => harness.voice.played.length > tocadosAntes,
      );
      await settle();

      expect(
        harness.voice.played.last,
        linha!.url,
        reason: 'o mesmo clipe do veredito, tocado de novo',
      );
      expect(
        harness.playback.ranges,
        isEmpty,
        reason: 'o botão toca a resposta, não o trecho',
      );
    });

    test('mostra o narrador falando enquanto repete', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.voice.holdNextLine();
      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'a sala mostrar o narrador falando',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      harness.voice.finishHeldLine();
      await waitFor(
        'a sala voltar a convidar',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );
    });

    test('sem fala guardada, o botão não toca nada', () async {
      final harness = harnessApontando()..room.verdictUsedFailSafe = true;
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      expect(
        container.read(salaSessionProvider).lastSpoken,
        isNull,
        reason:
            'a abertura fica para trás a caminho da Retro, e o veredito de '
            'fail-safe não é lembrado',
      );

      final tocadosAntes = harness.voice.played.length;
      final assetsAntes = harness.voice.assets.length;
      final fixasAntes = harness.voice.fixedLines.length;

      notifier.ouvirARespostaDeNovo();
      await settle();

      expect(harness.voice.played.length, tocadosAntes);
      expect(harness.voice.assets.length, assetsAntes);
      expect(harness.voice.fixedLines.length, fixasAntes);
      expect(harness.playback.ranges, isEmpty);
    });

    testWidgets('depois de um veredito de fail-safe, o botão repete o veredito '
        'de antes dele, não o de fail-safe', (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      expect(harness.voice.played.last, falaDoVeredito);
      harness.room
        ..verdictUsedFailSafe = true
        ..verdictAudioUrl = _oVereditoDeSeguranca;
      await traduzirDeNovo(tester, container);
      await terminei(tester, container);
      expect(harness.voice.played.last, _oVereditoDeSeguranca);
      final tocadosAntes = harness.voice.played.length;

      notifier(container).ouvirARespostaDeNovo();
      await tester.pump(const Duration(milliseconds: 600));

      expect(harness.voice.played.skip(tocadosAntes), [falaDoVeredito]);
    });

    testWidgets('um veredito de fail-safe que não carrega não cobre a retro e '
        'deixa o botão com o veredito de antes dele', (tester) async {
      final container = await pumpToPergunta(tester);
      final harness = harnessDaVez!;
      SalaSessionState read() => container.read(salaSessionProvider);
      harness.room
        ..verdictUsedFailSafe = true
        ..verdictAudioUrl = _oVereditoDeSeguranca;
      harness.voice.refuses.add(_oVereditoDeSeguranca);
      await traduzirDeNovo(tester, container);
      unawaited(notifier(container).finishBackTranslation());
      await waitFor(
        'o veredito falhar',
        () => harness.voice.played.contains(_oVereditoDeSeguranca),
        step: () => tester.pump(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        harness.voice.played.where((url) => url == _oVereditoDeSeguranca),
        hasLength(1),
        reason:
            'o veredito era carregado de novo 1,5 s depois; o dela toca uma vez',
      );
      expect(
        read().needsPerson,
        isFalse,
        reason: 'o sinal cobria a retro, e o Drafting dela nunca o mostra',
      );
      final tocadosAntes = harness.voice.played.length;
      notifier(container).ouvirARespostaDeNovo();
      await tester.pump(const Duration(milliseconds: 600));

      expect(harness.voice.played.skip(tocadosAntes), [falaDoVeredito]);
    });
  });
}
