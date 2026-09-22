import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'playback_ceiling_test.dart' show gravaParte;
import 'session_notifier_test.dart' show inConversa, settle;
import 'tocar_vira_pausar_test.dart' show harnessApontando, pumpAoApontado;

/// Two parts recorded and kept, with the rehearsal at rest: the state the button that
/// plays the whole rehearsal back lives in.
///
/// The ceiling is short and the parts are long on purpose. The chain that plays the
/// parts one after the other is the only place in the room that opens a clip over a
/// clip without silencing anything first, and the ceiling firing while the first part
/// is still loading is what puts it there.
Future<
  ({ProviderContainer container, SalaHarness harness, SalaSessionNotifier sala})
>
_ensaioDeDuasPartes() async {
  final harness = SalaHarness(playbackCeiling: const Duration(milliseconds: 60))
    ..playback.length = const Duration(seconds: 30);
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);

  sala.goEnsaio();
  await gravaParte(container, sala);
  await gravaParte(container, sala);

  return (container: container, harness: harness, sala: sala);
}

void main() {
  test('dois sons pedidos em seguida nunca chamam uma pessoa', () async {
    final cena = await _ensaioDeDuasPartes();
    cena.harness.playback.holdNextOpening();

    cena.sala.ghostPlay();
    await waitFor(
      'a segunda parte ser pedida por cima do load da primeira',
      () => cena.harness.playback.played.length >= 2,
    );

    await waitFor('a segunda parte soar', () => cena.harness.playback.sounding);

    final estado = cena.container.read(salaSessionProvider);
    expect(
      estado.voice,
      isNot(VoiceState.needsPerson),
      reason:
          'pino de regressão na sala: quem prova que a abertura '
          'atropelada não vira falha é o teste do repositório, e aqui se '
          'fixa que a sala não chama ninguém por um som que a equipe pediu',
    );
    expect(
      estado.ensaio,
      EnsaioStatus.ghostPlaying,
      reason: 'e o ensaio segue correndo na parte que ficou de pé',
    );
  });

  test(
    'a abertura atropelada não se anuncia nem deixa teto para trás',
    () async {
      final cena = await _ensaioDeDuasPartes();
      final anunciadas = <void>[];
      cena.harness.playback.openings.listen(anunciadas.add);
      cena.harness.playback.holdNextOpening();

      cena.sala.ghostPlay();
      await waitFor(
        'a segunda parte soar por cima do load da primeira',
        () => cena.harness.playback.sounding,
      );

      cena.harness.playback.finishHeldOpening();
      await settle();

      expect(
        anunciadas,
        hasLength(1),
        reason:
            'o que o clipe devia à sala morre com o clipe: a abertura que '
            'a seguinte atropelou não tem medida nem teto a dar a ninguém, e '
            'anunciada armaria o relógio de um clipe que nunca tocou',
      );
      expect(
        cena.harness.playback.sounding,
        isTrue,
        reason:
            'e a parte que está no ar não é interrompida pelo load que '
            'chegou tarde',
      );
      expect(
        cena.container.read(salaSessionProvider).ensaio,
        EnsaioStatus.ghostPlaying,
      );
    },
  );

  test(
    'o terceiro toque dado enquanto o clipe ainda abre põe-no a tocar',
    () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final sala = container.read(salaSessionProvider.notifier);
      harness.playback.holdNextOpening();

      sala.ouvirVozMaterna();
      await waitFor(
        'a sala pedir o trecho',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );
      sala.ouvirVozMaterna();
      await waitFor(
        'a equipe segurar o trecho',
        () => container.read(salaSessionProvider).btTrechoPausada,
      );
      sala.ouvirVozMaterna();
      await waitFor(
        'a equipe soltar o trecho',
        () => container.read(salaSessionProvider).btTrechoTocando,
      );

      expect(
        harness.playback.sounding,
        isFalse,
        reason:
            'a fonte ainda está abrindo: o resume desfaz o hold, não '
            'inventa som de um clipe que o player ainda não tem',
      );

      harness.playback.finishHeldOpening();
      await waitFor(
        'o trecho soar quando a fonte fica pronta',
        () => harness.playback.sounding,
      );
    },
  );

  test(
    'no dublê, um resume depois de um stop também não ressuscita o clipe',
    () async {
      final playback = FakePlayback();
      addTearDown(playback.dispose);
      final falhas = <void>[];
      playback.failures.listen(falhas.add);

      playback.holdNextOpening();
      unawaited(playback.play('/parte-1.m4a'));
      await playback.stop();
      await playback.resume();
      playback.finishHeldOpening();
      await settle();

      expect(
        playback.sounding,
        isFalse,
        reason:
            'o repositório real cala aqui: um dublê que soasse deixaria '
            'verde o roteiro em que a sala chama uma pessoa',
      );
      expect(falhas, isEmpty);
    },
  );

  test(
    'um stop durante o load não deixa o dublê respondendo pela medida',
    () async {
      final playback = FakePlayback();
      addTearDown(playback.dispose);
      final anunciadas = <void>[];
      playback.openings.listen(anunciadas.add);
      playback.length = const Duration(seconds: 30);

      playback.holdNextOpening();
      unawaited(playback.play('/parte-1.m4a'));
      await playback.stop();
      playback.finishHeldOpening();
      await settle();

      expect(
        playback.playingLength,
        isNull,
        reason:
            'o repositório apaga a medida no stop e o load que assenta '
            'atrás dele não a escreve de volta: um dublê que respondesse aqui '
            'daria ao teto do clipe seguinte o comprimento de um clipe que '
            'nunca tocou',
      );
      expect(
        anunciadas,
        hasLength(1),
        reason:
            'anunciar-se, porém, a abertura parada ainda se anuncia: o '
            'teto da escuta e a medida da parte no ar penduram-se nisso',
      );
    },
  );

  test('um resume num clipe que nunca abriu não faz som nenhum', () async {
    final playback = FakePlayback();
    addTearDown(playback.dispose);

    await playback.resume();

    expect(
      playback.sounding,
      isFalse,
      reason:
          'não há clipe nenhum para voltar a soar, e um dublê que '
          'soasse aqui daria por boa uma sala que a equipe ouve calada',
    );
    expect(playback.played, isEmpty);
  });
}
