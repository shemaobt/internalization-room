import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'esperas.dart' show settle, until;
import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;

/// Record one part and wait for the room to have named it.
///
/// A stretch is a slice of a recording the room can name, and the name is adopted only
/// once the take lands. Going on before that makes every cut arrive with nothing to point
/// at, and the room drops it instead of sending it.
Future<void> gravaParte(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  final partesAntes = container.read(salaSessionProvider).partes.length;
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  await until(() {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length > partesAntes && partes.last.takeId != null;
  });
}

void main() {
  test('holding the clip leaves no ceiling behind, and letting it run arms one',
      () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 200))
      ..playback.length = const Duration(milliseconds: 400);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(milliseconds: 380);
    notifier.ouvirGravacao();
    await settle(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'com o clipe parado nenhum relógio corre: era a própria pausa '
            'que armava o teto e terminava a parte por cima da equipe');

    notifier.ouvirGravacao();
    await settle(const Duration(milliseconds: 80));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'e ao voltar a tocar o teto conta o que faltava do clipe');

    await settle(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue,
        reason: 'passado o que restava, a parte termina');
  });

  test('a clip heard straight through still ends the part', () async {
    final harness = SalaHarness()
      ..playback.length = const Duration(milliseconds: 200);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(milliseconds: 200);
    harness.playback.finishPlayback();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue,
        reason: 'um clipe ouvido inteiro é um clipe que acabou');
    expect(state.canFinishBackTranslation, isTrue,
        reason: 'e é o fim do clipe que abre o terminei');
  });

  test('a part that just began is not ended by the length of the one before it',
      () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 600);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    await gravaParte(container, notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(milliseconds: 600);
    harness.playback.finishPlayback();
    await settle();

    expect(container.read(salaSessionProvider).btParteFronteira, isTrue);

    notifier.proximaParte();
    await settle(const Duration(milliseconds: 250));

    final state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isFalse,
        reason: 'a parte que começa agora não tem o tamanho nem a posição da '
            'que acabou; medida por elas, ela nasceria já no fim');
    expect(state.btClipRodando, isTrue);
  });

  test('a clip longer than the generic ceiling is not cut in half', () async {
    final harness = SalaHarness(
      playbackCeiling: const Duration(milliseconds: 100),
      clipGrace: const Duration(milliseconds: 60),
    )..playback.length = const Duration(milliseconds: 900);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    notifier.startRetro();
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'o teto genérico é para um clipe que nunca abriu; assim que o '
            'clipe abre, quem manda é o comprimento dele');

    await settle(const Duration(milliseconds: 900));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue,
        reason: 'e o teto continua existindo: passado o comprimento do clipe '
            'mais a margem, a parte termina mesmo sem aviso de fim');
  });

  test('hearing a stretch again does not cut it short', () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 600)
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(milliseconds: 40);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await until(() => harness.room.chunksSent == 1);
    await settle();

    harness.playback.at = const Duration(milliseconds: 600);
    harness.playback.finishPlayback();
    // finishBackTranslation is a no-op while the clip has not ended, and ouvirVozMaterna
    // is one until the verdict is in: both taps are dropped in silence when they arrive
    // early, so each waits for the door it goes through.
    await until(() => container.read(salaSessionProvider).canFinishBackTranslation);
    await notifier.finishBackTranslation();
    await until(
        () => container.read(salaSessionProvider).btPhase == BtPhase.findings);

    notifier.ouvirVozMaterna();
    await until(() => container.read(salaSessionProvider).btTrechoTocando);

    expect(container.read(salaSessionProvider).btTrechoTocando, isTrue);

    harness.playback.at = const Duration(milliseconds: 600);
    notifier.retroTap();
    await settle(const Duration(milliseconds: 250));

    expect(container.read(salaSessionProvider).btTrechoTocando, isTrue,
        reason: 'o trecho pedido de novo toca até o fim: o teto herdado do '
            'anterior devolvia a tela ao repouso com o áudio ainda correndo');

    harness.playback.finishPlayback();
    await until(() => !container.read(salaSessionProvider).btTrechoTocando);

    expect(container.read(salaSessionProvider).btTrechoTocando, isFalse,
        reason: 'e quem cala o trecho é o fim dele');
  });

  test('a clip that opens after the team has already paused it does not end the part',
      () async {
    final harness = SalaHarness(
      clipGrace: const Duration(milliseconds: 40),
      playbackCeiling: const Duration(seconds: 5),
    )..playback.length = const Duration(milliseconds: 80);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(container, notifier);
    harness.playback.holdNextOpening();
    notifier.startRetro();
    await settle();

    expect(container.read(salaSessionProvider).btClipRodando, isTrue,
        reason: 'a sala já se diz tocando enquanto a fonte ainda carrega, e é '
            'por isso que o toque da equipe é aceito aqui');

    notifier.ouvirGravacao();
    await settle();

    expect(container.read(salaSessionProvider).btClipRodando, isFalse);

    harness.playback.finishHeldOpening();
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'a abertura chegou depois da pausa e armou o teto por cima de '
            'um clipe parado: a parte terminava sozinha com a equipe ainda '
            'explicando, que é o defeito que este branch tira pela porta larga');

    notifier.ouvirGravacao();
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).btClipEnded, isTrue,
        reason: 'e a abertura tardia não custa o teto: ao voltar a tocar, a '
            'parte termina no que lhe restava, senão o conserto seria não '
            'medir mais nada');
  });
}
