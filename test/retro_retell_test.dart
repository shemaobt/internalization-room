import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

Future<void> until(
  bool Function() condition, {
  Duration limit = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _gravaParte(SalaSessionNotifier notifier) async {
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  await settle();
}

Future<ProviderContainer> _inRetro(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await settle();
  notifier.goEnsaio();
  await _gravaParte(notifier);
  notifier.startRetro();
  await settle();
  return container;
}

Future<void> _contaTrecho(
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

/// Tell one stretch again: the room listens, the team speaks, the team stops it.
Future<void> _contaDeNovo(
  SalaSessionNotifier notifier,
  Trecho trecho,
) async {
  await notifier.contarDeNovo(trecho);
  await settle();
  notifier.retroTap();
  await settle();
}

/// A session whose one stretch was divided, so both halves are waiting to be told.
Future<ProviderContainer> _comDuasMetadesEsperando(SalaHarness harness) async {
  final container = await _inRetro(harness);
  final notifier = container.read(salaSessionProvider.notifier);
  await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
  await until(() => harness.room.chunksSent == 1);
  harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await until(() => container.read(salaSessionProvider).btTrechoTocando);
  harness.playback.at = const Duration(seconds: 8);
  await notifier.dividirTrecho();
  await settle();
  return container;
}

void main() {
  test('a stretch that was waiting stops waiting, and no stretch is added',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _comDuasMetadesEsperando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final esperando = container.read(salaSessionProvider).btTrechos;

    expect(esperando.length, 2);
    expect(esperando.every((trecho) => !trecho.contado), isTrue,
        reason: 'as duas metades nascem sem explicação — é isso que faz o '
            'portão da primeira rodada segurar a análise');

    await _contaDeNovo(notifier, esperando.first);

    final depois = container.read(salaSessionProvider).btTrechos;
    expect(depois.length, 2,
        reason: 'contar de novo preenche o trecho que estava esperando; não '
            'acrescenta um terceiro ao lado dele');
    expect(depois.first.contado, isTrue);
    expect(depois.last.contado, isFalse,
        reason: 'e a outra metade continua esperando a vez dela');
  });

  test('both halves of a division can be told', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _comDuasMetadesEsperando(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _contaDeNovo(
        notifier, container.read(salaSessionProvider).btTrechos.first);
    await _contaDeNovo(
        notifier, container.read(salaSessionProvider).btTrechos.last);

    final depois = container.read(salaSessionProvider).btTrechos;
    expect(depois.length, 2);
    expect(depois.every((trecho) => trecho.contado), isTrue,
        reason: 'este é o buraco que a fatia fecha: sem isto, dividir deixava '
            'duas unidades que ninguém podia preencher e a passagem travava '
            'no portão da primeira rodada');
  });

  test('the slice does not move when a stretch is told again', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _comDuasMetadesEsperando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final alvo = container.read(salaSessionProvider).btTrechos.last;

    await _contaDeNovo(notifier, alvo);

    expect(harness.room.replacesAsked, [
      '${alvo.segmentId}@${alvo.takeId}:'
          '${alvo.from.inMilliseconds}-${alvo.to.inMilliseconds}',
    ], reason: 'contar de novo não é regravar: o recorte enviado é o mesmo, e '
        'um recorte diferente com explicação junto é o que o servidor recusa');
  });

  test('a refusal from the room is neither a jam nor a silence', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _comDuasMetadesEsperando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.failReplaceWith = const RoomRefused();

    await _contaDeNovo(
        notifier, container.read(salaSessionProvider).btTrechos.first);

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue,
        reason: 'a recusa cai no caminho de falha que já existe em vez de '
            'deixar a equipe falando para uma sala que não responde');
    expect(state.btTrechos.every((trecho) => !trecho.contado), isTrue,
        reason: 'e nada foi dado por contado');
  });

  test('telling a new stretch still creates a new stretch', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _contaTrecho(harness, notifier, em: const Duration(seconds: 10));
    await until(() => harness.room.chunksSent == 1);
    await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
    await until(() => harness.room.chunksSent == 2);

    expect(harness.room.chunkSpans, ['0-10000', '10000-20000'],
        reason: 'o caminho de sempre não vira substituição por engano');
    expect(harness.room.replacesAsked, isEmpty);
    expect(container.read(salaSessionProvider).btTrechos.length, 2);
  });
}
