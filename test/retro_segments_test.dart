import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

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

Future<ProviderContainer> _inRetro(
  SalaHarness harness, {
  int partes = 1,
}) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  notifier.goEnsaio();
  for (var parte = 0; parte < partes; parte++) {
    await _gravaParte(container, notifier);
  }
  notifier.startRetro();
  await settle();
  return container;
}

Future<void> _traduzTrecho(
  SalaHarness harness,
  SalaSessionNotifier notifier, {
  required Duration em,
}) async {
  harness.playback.at = em;
  notifier.cortarTrecho();
  await settle();
  notifier.retroTap();
  await settle();
}

void main() {
  test('a stretch names the recording it came from', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);

    expect(harness.room.chunkTakes, [harness.room.takeIds.first],
        reason: 'sem nomear a gravação, o trecho é uma fatia de coisa nenhuma '
            'e o servidor não tem em que apontar');
    expect(harness.room.chunkSpans, ['0-10000']);
  });

  test('a stretch recorded into nothing does not pass as told back', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.recorder.returnsEmpty = true;
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));

    expect(harness.room.chunksSent, 0,
        reason: 'o trecho sem um byte dentro subia, e a cobertura da passagem passava '
            'a contar com uma explicação que ninguém deu');
    expect(container.read(salaSessionProvider).btTrechos, isEmpty,
        reason: 'e o trecho entrava na lista, então a tesoura seguia do fim de uma '
            'fatia que não existe');
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'este ramo voltava calado para o player, que é a sala não dizendo '
            'nada sobre um aparelho que parou de gravar');
  });

  test('the second part of the rehearsal counts from its own beginning',
      () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness, partes: 2);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);

    notifier.ouvirGravacao();
    await settle();
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 5));
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);

    expect(harness.room.chunkSpans, ['0-10000', '0-5000'],
        reason: 'o mesmo instante ouvido em partes diferentes não pode virar o '
            'mesmo par de números somado à duração da anterior — é isso que '
            'fazia regravar um trecho deslocar todos os seguintes');
    expect(harness.room.chunkTakes, harness.room.takeIds.take(2).toList(),
        reason: 'cada trecho sai do arquivo que estava tocando, e são dois '
            'arquivos diferentes');
  });

  test('a finding names a stretch and the room offers that stretch', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    harness.room.verdictFindingSegmentId = harness.room.segmentIds.first;
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btFindingTrecho, isNotNull,
        reason: 'o servidor nomeou o trecho; a sala tem de saber levar a '
            'equipe até ele em vez de recomeçar a passagem');
    expect(state.btFindingTrecho!.segmentId, harness.room.segmentIds.first);
  });

  test('a finding that names no stretch degrades to the whole recording',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    harness.room.verdictFindingSegmentId = null;
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(container.read(salaSessionProvider).btFindingTrecho, isNull,
        reason: 'sem trecho nomeado a oferta degrada para a gravação inteira, '
            'como já degradava');
  });

  test('a finding naming a stretch the room never told resolves to none',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    harness.room.verdictFindingSegmentId = 'trecho-que-nao-existe';
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(container.read(salaSessionProvider).btFindingTrecho, isNull,
        reason: 'um nome que não corresponde a trecho nenhum não pode ser '
            'resolvido como se fosse outro — a equipe traduziria de novo o trecho '
            'errado');
  });

  test('what was heard of each part is measured against that part', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 10);
    final container = await _inRetro(harness, partes: 2);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).canFinishBackTranslation, isFalse,
        reason: 'a sala não deixa terminar antes de o clipe acabar');

    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 5));
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(
        [
          for (final parte in harness.room.playedByTakeSent.last)
            parte['clip_duration_ms']
        ],
        [10000, 10000],
        reason: 'a régua da escuta é cada parte contra ela mesma, e o endereço '
            'do trecho é local ao arquivo: as duas coisas no mesmo relógio');
    expect(harness.room.playedByTakeSent.last.first['played_ranges'], [
      [0, 10000]
    ]);
    expect(harness.room.playedByTakeSent.last.last['played_ranges'], [
      [0, 10000]
    ], reason: 'o que a segunda parte tem de ouvido conta do próprio zero dela, '
        'não de dez segundos: o endereço do trecho já era local, e agora a '
        'escuta também é');
  });
}
