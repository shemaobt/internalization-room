import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

/// Record one part and wait for the room to have named it.
///
/// A stretch is a slice of a recording the room can name, and the name is adopted only
/// once the take lands. Going on before that makes every cut arrive with nothing to point
/// at, and the room drops it instead of sending it.
Future<void> _gravaParte(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  final partesAntes = container.read(salaSessionProvider).partes.length;
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  await waitFor('a sala nomear a parte', () {
    final partes = container.read(salaSessionProvider).partes;
    return partes.length > partesAntes && partes.last.takeId != null;
  });
}

Future<ProviderContainer> _inRetro(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  notifier.goEnsaio();
  await _gravaParte(container, notifier);
  notifier.startRetro();
  await settle();
  return container;
}

Future<void> _traduzTrecho(
  SalaHarness harness,
  ProviderContainer container, {
  required Duration em,
}) async {
  final notifier = container.read(salaSessionProvider.notifier);
  harness.playback.at = em;
  notifier.cortarTrecho();
  notifier.retroTap();
  await settle();
  await confirmarATraducao(container);
  await settle();
}

/// Tell the pointed stretch again: the azul microphone lands on it, the circle records
/// over the old telling, the check sends it.
Future<void> _traduzDeNovo(
  ProviderContainer container,
  SalaSessionNotifier notifier,
) async {
  notifier.traduzirDeNovoEmPortugues();
  notifier.retroTap();
  await waitFor(
    'o microfone abrir no trecho apontado',
    () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
  );
  await fecharACaptura(container);
  await notifier.confirmarTraducao();
  // Every way out of the telling leaves the thinking — the room answered, the room
  // refused, the recorder came back empty — so this is the wait that spans them all.
  await waitFor(
    'a sala sair do pensando',
    () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
  );
}

/// A session standing on a finding, with the cursor moved onto the stretch it names.
///
/// Being led to that stretch is what puts the cursor behind the ground already told back:
/// it holds the finding's own bounds while the team hears it. What the room does with the
/// correction that follows is each test's business.
Future<ProviderContainer> _levadaAoTrechoApontado(SalaHarness harness) async {
  final container = await _inRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await _traduzTrecho(harness, container, em: const Duration(seconds: 20));
  await waitFor(
    'o primeiro trecho chegar à sala',
    () => harness.room.chunksSent == 1,
  );
  harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
  harness.playback.finishPlayback();
  // finishBackTranslation is a no-op while the clip has not ended, and ouvirOTrechoEATraducao is
  // one until the verdict is in: each tap is dropped in silence when it arrives early, so
  // each waits for the door it goes through.
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
  );
  notifier.ouvirOTrechoEATraducao();
  await waitFor(
    'o trecho apontado estar tocando',
    () => container.read(salaSessionProvider).btTrechoTocando,
  );
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução dada entrar depois do trecho',
    () => container.read(salaSessionProvider).btRetroTocando,
  );
  harness.playback.finishPlayback();
  await waitFor(
    'a tradução dada parar de tocar',
    () => !container.read(salaSessionProvider).btRetroTocando,
  );
  return container;
}

void main() {
  test('telling a new stretch still creates a new stretch', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);

    await _traduzTrecho(harness, container, em: const Duration(seconds: 10));
    await waitFor(
      'o primeiro trecho chegar à sala',
      () => harness.room.chunksSent == 1,
    );
    await _traduzTrecho(harness, container, em: const Duration(seconds: 20));
    await waitFor(
      'o segundo trecho chegar à sala',
      () => harness.room.chunksSent == 2,
    );

    expect(
      harness.room.chunkSpans,
      ['0-10000', '10000-20000'],
      reason: 'o caminho de sempre não vira substituição por engano',
    );
    expect(harness.room.replacesAsked, isEmpty);
    expect(container.read(salaSessionProvider).btTrechos.length, 2);
  });
  test('the retelling latch does not survive leaving the passage', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _levadaAoTrechoApontado(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.traduzirDeNovoEmPortugues();
    await settle();
    notifier.leaveThePassage();
    await settle();

    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    await _gravaParte(container, notifier);
    notifier.startRetro();
    await settle();
    final pedidosAntes = harness.room.replacesAsked.length;
    final contadosAntes = harness.room.chunksSent;
    await _traduzTrecho(harness, container, em: const Duration(seconds: 10));
    await waitFor(
      'o corte chegar à sala',
      () => harness.room.chunksSent == contadosAntes + 1,
    );

    expect(
      harness.room.replacesAsked.length,
      pedidosAntes,
      reason:
          'o trecho armado é um latch sem casa no estado, e já mandou o '
          'primeiro trecho de uma tradução como correção de um trecho que '
          'não existia — aqui iria para o id da passagem anterior',
    );
    expect(harness.room.chunkSpans.last, '0-10000');
  });

  test(
    'a short way whose microphone never opened still tells that stretch',
    () async {
      final harness = SalaHarness()..room.verdictChecked = false;
      final container = await _levadaAoTrechoApontado(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      final trecho = container.read(salaSessionProvider).btTrechos.first;

      // O microfone recusa abrir, e a sala volta a tocar com o conserto ainda
      // armado naquele trecho: é onde a equipe toca o círculo de novo.
      harness.recorder.startThrows = true;
      notifier.traduzirDeNovoEmPortugues();
      notifier.retroTap();
      await settle();
      expect(
        container.read(salaSessionProvider).btPhase,
        BtPhase.playing,
        reason: 'o microfone recusou abrir e a sala voltou a tocar',
      );

      harness.recorder.startThrows = false;
      harness.playback.at = const Duration(seconds: 5);
      notifier.retroTap();
      await waitFor(
        'o microfone abrir no trecho',
        () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
      );
      await fecharACaptura(container);
      await notifier.confirmarTraducao();
      await waitFor(
        'a sala sair do pensando',
        () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
      );

      expect(
        harness.room.replacesAsked,
        hasLength(1),
        reason:
            'o conserto continua armado, então o que a equipe conta é a '
            'correção daquele trecho; lida a posição do tocador, o corte volta '
            'em silêncio e o círculo fica morto',
      );
      expect(
        harness.room.replacesAsked.single,
        endsWith(':${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}'),
        reason: 'e no endereço do trecho, não onde o tocador tinha parado',
      );
      expect(
        harness.room.chunkSpans,
        ['0-20000'],
        reason: 'e nada sobe como pedaço novo por cima do conserto armado',
      );
    },
  );

  test('a correction the room takes leaves the next cut on untold ground', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..playback.length = const Duration(seconds: 40);
    final container = await _levadaAoTrechoApontado(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    // The room takes the correction and then does not answer for it in time, so the team
    // is left standing on the recording instead of being carried to a result. That is the
    // one place from which the cursor a correction moved can be read at all: every other
    // way out of a correction the room took ends the telling-back.
    harness.room.failFinishWith = const RoomSlow();
    await _traduzDeNovo(container, notifier);
    harness.room.failFinishWith = null;

    await _traduzTrecho(harness, container, em: const Duration(seconds: 40));

    expect(
      harness.room.chunkSpans.last,
      '20000-40000',
      reason:
          'os dois limites são do tocador a partir do que já foi contado: '
          'começar em zero mandaria a gravação inteira como trecho novo, e o '
          'que a equipe acabou de contar seria contado outra vez',
    );
  });
}
