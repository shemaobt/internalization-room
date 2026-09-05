import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
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
  await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
  harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  // The room no longer plays the pointed stretch at the team: which voice must
  // speak again is theirs to say, so hearing it is a tap they choose to make.
  notifier.ouvirVozMaterna();
  await waitFor(
    'o trecho apontado estar tocando',
    () => container.read(salaSessionProvider).btTrechoTocando,
  );
  harness.playback.at = const Duration(seconds: 8);
  await notifier.dividirTrecho();
  await settle();
  return container;
}

void main() {
  test('a retelling that came back empty does not follow the next stretch',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    await _contaTrecho(harness, notifier, em: const Duration(seconds: 40));
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);
    harness.room.verdictFindingSegmentId = harness.room.segments.first.segmentId;
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    notifier.retellChunk();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    harness.recorder.returnsEmpty = true;
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o trecho recontado voltou vazio, então a sala para para uma pessoa');

    harness.room.theDeskAttended();
    notifier.resolveWithPerson();
    await waitFor('a sala sair da parada',
        () => !container.read(salaSessionProvider).needsPerson);
    harness.recorder.returnsEmpty = false;
    harness.playback.at = const Duration(seconds: 60);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor('o terceiro trecho chegar à sala', () => harness.room.chunksSent == 3);

    expect(harness.room.chunksSent, 3,
        reason: 'o corte seguinte precisa mesmo chegar à sala, senão nada aqui é olhado');
    expect(harness.room.retells, 0,
        reason: 'a marca de recontar só é apagada por um trecho que chega, e sair por '
            'cima dela deixava o corte seguinte subir como correção de um trecho que '
            'ninguém estava contando');
    expect(harness.room.chunkSpans, ['0-20000', '20000-40000', '40000-60000'],
        reason: 'e o cursor do corte também foi movido pelo recontar, então o trecho '
            'seguinte subia desde o começo do que ia ser recontado — os vinte primeiros '
            'segundos contados duas vezes');
  });

  test('a mother-tongue take that came back empty does not replace the audio',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    final guardadas = harness.room.takesKept.length;
    notifier.regravarAVozMaterna();
    await settle();
    harness.recorder.returnsEmpty = true;
    notifier.retroTap();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.takesKept, hasLength(guardadas),
        reason: 'a voz nova sem um byte dentro era copiada para guardadas/ e entrava '
            'no manifesto antes de qualquer coisa medir a duração dela');
    expect(harness.room.replacesAsked, isEmpty,
        reason: 'e o trecho bom da equipe era aposentado em troca de um arquivo vazio');
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'este ramo voltava calado para a pergunta, e a equipe tocava de novo '
            'sem entender por que a voz não trocava');
  });

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
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);

    expect(harness.room.chunkSpans, ['0-10000', '10000-20000'],
        reason: 'o caminho de sempre não vira substituição por engano');
    expect(harness.room.replacesAsked, isEmpty);
    expect(container.read(salaSessionProvider).btTrechos.length, 2);
  });
  test('the retelling latch does not survive leaving the passage', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _comDuasMetadesEsperando(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.contarDeNovo(
        container.read(salaSessionProvider).btTrechos.first);
    await settle();
    notifier.leaveThePassage();
    await settle();

    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    await _gravaParte(notifier);
    notifier.startRetro();
    await settle();
    final pedidosAntes = harness.room.replacesAsked.length;
    await _contaTrecho(harness, notifier, em: const Duration(seconds: 10));

    expect(harness.room.replacesAsked.length, pedidosAntes,
        reason: 'a trava é um latch sem casa no estado, como o _recontando que '
            'já mandou o primeiro trecho de uma retrotradução como correção de '
            'um trecho que não existia — aqui iria para o id da passagem '
            'anterior');
    expect(harness.room.chunkSpans.last, '0-10000');
  });

  test('telling a stretch again does not leave the room retelling', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _contaTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    notifier.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => container.read(salaSessionProvider).btTrechoTocando,
    );

    notifier.retellChunk();
    await settle();
    harness.playback.finishPlayback();
    await waitFor(
      'o trecho apontado parar de tocar',
      () => !container.read(salaSessionProvider).btTrechoTocando,
    );
    // Refused on purpose. A correction the room takes now carries the team on to its
    // result, and there is no cut after it to catch the latch with; a refused one leaves
    // them on the recording, which is the path this still has to hold — and the latch is
    // let go before the upload either way, so it is the same latch being watched.
    harness.room.replaceCaptured = false;
    await _contaDeNovo(
        notifier, container.read(salaSessionProvider).btTrechos.first);
    harness.room.replaceCaptured = true;
    final recontagensAntes = harness.room.retells;

    await _contaTrecho(harness, notifier, em: const Duration(seconds: 40));

    expect(harness.room.retells, recontagensAntes,
        reason: 'contar um trecho de novo encerra a recontagem: deixá-la '
            'ligada faz o próximo corte ignorar o tocador, reaproveitar os '
            'limites velhos e subir como recontagem');
    // Only the far end is read here. A refused correction leaves the cursor where the
    // retelling put it — the successful path is the one that walks it back to the
    // furthest stretch told — so the near end is that stale cursor rather than anything
    // this test is about, and asserting it would be asserting a separate defect.
    expect(harness.room.chunkSpans.last, endsWith('-40000'),
        reason: 'e o corte termina onde o tocador está, não onde a recontagem '
            'parou: herdar o fim velho mandaria como trecho novo um pedaço '
            'que a equipe não acabou de contar');
  });
}
