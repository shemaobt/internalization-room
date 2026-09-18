import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

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

/// The one moment a stretch the team already told plays back: the room leading them to
/// the stretch a finding named.
Future<void> _ouvindoOTrechoApontado(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  ProviderContainer container,
) async {
  harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
  harness.playback.finishPlayback();
  // finishBackTranslation is a no-op while the clip has not ended, and ouvirVozMaterna is
  // one until the verdict is in: both taps are dropped in silence when they arrive early,
  // so each waits for the door it goes through.
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
  );
  // The room no longer plays the pointed stretch at the team: which voice must speak
  // again is theirs to say, so hearing either one is a tap they choose to make.
  notifier.ouvirVozMaterna();
  await waitFor(
    'o trecho apontado estar tocando',
    () => container.read(salaSessionProvider).btTrechoTocando,
  );
}

Future<ProviderContainer> _umTrechoTraduzidoETocando(
  SalaHarness harness, {
  int partes = 1,
  Duration ate = const Duration(seconds: 20),
}) async {
  final container = await _inRetro(harness, partes: partes);
  final notifier = container.read(salaSessionProvider.notifier);
  await _traduzTrecho(harness, notifier, em: ate);
  await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
  await _ouvindoOTrechoApontado(harness, notifier, container);
  return container;
}

void main() {
  test('a divided stretch becomes two, and the team sees both', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _umTrechoTraduzidoETocando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final antes = container.read(salaSessionProvider).btTrechos;

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    final depois = container.read(salaSessionProvider).btTrechos;
    expect(antes.length, 1);
    expect(depois.length, 2,
        reason: 'a equipe ouviu duas ideias onde tinha contado uma, e agora '
            'tem de ver as duas');
    expect(depois.first.from, antes.first.from);
    expect(depois.last.to, antes.first.to,
        reason: 'os dois pedaços cobrem o mesmo áudio que o trecho cobria — '
            'nada de gravação se perde na divisão');
    expect(depois.first.to, depois.last.from,
        reason: 'e nada aparece duas vezes: a borda é uma só');
    expect(depois.map((trecho) => trecho.segmentId).toSet().length, 2,
        reason: 'dois pedaços, dois nomes');
  });

  test('the cut falls where the team was listening, on the file scale',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness, partes: 2);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 30);
    harness.playback.finishPlayback();
    await settle();
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 30));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);

    notifier.proximaParte();
    await settle();
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);
    await _ouvindoOTrechoApontado(harness, notifier, container);
    final naSegundaGravacao = harness.room.segments.last.segmentId;

    harness.playback.at = const Duration(seconds: 4);
    await notifier.dividirTrecho();
    await settle();

    expect(harness.room.dividesAsked, ['$naSegundaGravacao@4000'],
        reason: 'o trecho saiu da SEGUNDA gravação e o ponto conta do começo '
            'DAQUELE arquivo. Somar a duração da parte anterior daria 34000 e '
            'seria o tempo global com outro nome — o defeito que o trecho '
            'existe para remover');
  });

  test('a refusal from the room is neither a jam nor a silence', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    harness.room.failDivideWith = const RoomRefused();
    final container = await _umTrechoTraduzidoETocando(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue,
        reason: 'a recusa cai no caminho de falha que já existe: a sala pede '
            'uma pessoa em vez de deixar a equipe apertando sem resposta');
    expect(state.btTrechos.length, 1,
        reason: 'e nada foi dividido, então o que a equipe tinha continua lá');
  });

  test('dividing does not throw away what the team already told', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _umTrechoTraduzidoETocando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    final contadoAntes = harness.room.chunksSent;

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    expect(harness.room.chunksSent, contadoAntes,
        reason: 'dividir não traduz nada de novo: a explicação que a equipe deu fica '
            'onde está e o app não a manda de novo');
    expect(harness.room.dividesAsked.length, 1,
        reason: 'e pede a divisão uma vez só');
  });

  test('the two cuts never answer for one another', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    expect(harness.room.dividesAsked, isEmpty,
        reason: 'sem trecho tocando não há o que dividir: dividir corta o que '
            'está no ar, e no meio do ensaio quem corta é a outra tesoura');

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    await _ouvindoOTrechoApontado(harness, notifier, container);
    final contadosAntes = harness.room.chunksSent;

    await notifier.dividirTrecho();
    await settle();

    expect(harness.room.dividesAsked.length, 1,
        reason: 'o controle positivo: com o trecho no ar a divisão acontece, '
            'senão o silêncio de cima passaria por um gesto que nunca age');

    notifier.cortarTrecho();
    await settle();

    expect(harness.room.chunksSent, contadosAntes,
        reason: 'e a tesoura do ensaio já se recusa a agir enquanto um trecho '
            'toca, então a proteção que existe hoje não foi afrouxada');
  });

  test('dividing ends the finding instead of leaving it pointing at nothing',
      () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _umTrechoTraduzidoETocando(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).btFindingTrecho, isNotNull);

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btPhase, BtPhase.playing,
        reason: 'os dois pedaços nascem sem explicação e a análise não corre '
            'enquanto faltar contar, então o que vem depois de dividir é '
            'contar — não continuar numa tela de veredito que já não vale');
    expect(state.btFindingSegmentId, isNull,
        reason: 'o achado não fica nomeando um trecho que deixou de ser '
            'unidade: ele terminou, e o próximo nasce apontando a metade certa '
            'porque o analista vai ler de novo');
    expect(state.btFindings, isEmpty);
    expect(state.btTrechoTocando, isFalse,
        reason: 'e o áudio do trecho que acabou de deixar de existir para');
  });

  test('the passes stay as long as the stretches they belong to', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = await _umTrechoTraduzidoETocando(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    await notifier.dividirTrecho();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btChunkPasses.length, state.btTrechos.length,
        reason: 'as duas listas andam juntas em todo lugar que as escreve, e '
            'o índice do próximo pedaço lê ora uma ora outra — deixá-las de '
            'tamanhos diferentes faz um retro retomado reconstruir uma lista '
            'que não bate com a que está no ar');
    expect(state.btChunkPasses, [1, 1],
        reason: 'e os dois pedaços herdam a passada do trecho de onde saíram');
  });

  test('the rest of the back translation goes on working', () async {
    final harness = SalaHarness();
    final container = await _inRetro(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 10));
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    await _traduzTrecho(harness, notifier, em: const Duration(seconds: 20));
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.chunkSpans, ['0-10000', '10000-20000'],
        reason: 'ouvir, contar e cortar um trecho novo continuam como hoje');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
  });
}
