import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' show aRetomadaNoEnsaio, gravarMaisUmaParte;
import 'scenario_helpers.dart' show settle, umaParteInteira;

/// Record one part over the real outbox and keep it, without waiting for the room to
/// name it. Two of these back to back are what a team recording two parts on the way
/// out of the rehearsal actually does: the second `takeKeep` fires while the first
/// one's upload is still in flight.
Future<void> gravarSemEsperarNome(ProviderContainer container) async {
  final notifier = container.read(salaSessionProvider.notifier);
  notifier.ensaioTap();
  await waitFor(
    'a gravação da parte começar',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
  );
  notifier.ensaioTap();
  await waitFor(
    'a gravação da parte terminar',
    () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
  );
  notifier.takeKeep();
}

void main() {
  test('uma parte gravada na volta ao ensaio ganha o nome que o servidor deu '
      '(ENG-721)', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    // Grave as partes 3 e 4, uma logo depois da outra — sem esperar a sala nomear a
    // primeira antes de gravar a segunda. Segura o upload da parte 3 na sala até o
    // guard() da parte 4 já ter encontrado a fila em pleno flush — a janela que uma
    // rede rápida de teste nunca abre sozinha, mas uma rede real, mais lenta num dos
    // dois envios, abre.
    harness.room.holdNextTake(KeptScope.parte(3));
    await gravarSemEsperarNome(container);
    await harness.room.untilTakeHeld();
    await gravarSemEsperarNome(container);
    await settle();
    harness.room.finishHeldTake();

    await waitFor('a sala nomear as duas partes novas', () {
      final partes = container.read(salaSessionProvider).keptTakes;
      return partes.length == 4 &&
          partes[2].takeId != null &&
          partes[3].takeId != null;
    }, limit: const Duration(seconds: 2));

    final partes = container.read(salaSessionProvider).keptTakes;
    final t3 = partes[2].takeId!;
    final t4 = partes[3].takeId!;

    notifier.startRetro();
    await waitFor(
      'a retro tocar a parte 3',
      () =>
          harness.playback.played.isNotEmpty &&
          harness.playback.played.last == partes[2].path,
    );

    // Conta o trecho da parte 3.
    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'o trecho da parte 3 chegar à sala',
      () => harness.room.chunksSent == 1,
      limit: const Duration(seconds: 2),
    );
    expect(
      harness.room.chunkTakes,
      [t3],
      reason:
          'o corte da parte 3 chama a sala com o id que a sala já tinha dado',
    );

    harness.playback.finishPlayback();
    await waitFor(
      'a parte 3 fechar a fronteira',
      () => container.read(salaSessionProvider).btParteFronteira,
    );
    notifier.ouvirGravacao();
    await waitFor(
      'a retro tocar a parte 4',
      () => harness.playback.played.last == partes[3].path,
    );

    // Corta o trecho da parte 4 — a gravação que acabou de ser guardada.
    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'o trecho da parte 4 chegar à sala',
      () => harness.room.chunksSent == 2,
      limit: const Duration(seconds: 2),
    );

    final agora = container.read(salaSessionProvider);
    expect(
      harness.room.chunkTakes,
      [t3, t4],
      reason:
          'o corte da parte 4 chama a sala com o id que ela já tinha dado, '
          'não com a passagem inteira em socorro',
    );
    expect(
      agora.needsPerson,
      isFalse,
      reason: 'a sala não pode parar por uma pessoa quando o id já existe',
    );
    final guardadas = await harness.takes.entries();
    expect(
      guardadas.where((e) => e.scope == KeptScope.whole),
      isEmpty,
      reason: 'nada foi para a fila de emergência',
    );
  });

  test('a parte nova é uma parte: takeId certo no índice certo', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    final t3take = await gravarMaisUmaParte(container);
    final t4take = await gravarMaisUmaParte(container);

    final partes = container.read(salaSessionProvider).keptTakes;
    expect(partes, hasLength(4));
    expect(partes[2].scopeId, KeptScope.parte(3));
    expect(partes[2].takeId, t3take.takeId);
    expect(partes[3].scopeId, KeptScope.parte(4));
    expect(partes[3].takeId, t4take.takeId);

    notifier.startRetro();
    await waitFor(
      'a retro tocar a parte 3',
      () =>
          harness.playback.played.isNotEmpty &&
          harness.playback.played.last == partes[2].path,
    );
    harness.playback.finishPlayback();
    await waitFor(
      'a parte 3 fechar a fronteira',
      () => container.read(salaSessionProvider).btParteFronteira,
    );
    notifier.ouvirGravacao();
    await waitFor(
      'a retro tocar a parte 4',
      () => harness.playback.played.last == partes[3].path,
    );

    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'o trecho da parte 4 chegar à sala',
      () => harness.room.chunksSent == 1,
      limit: const Duration(seconds: 2),
    );

    expect(
      harness.room.chunkTakes,
      [t4take.takeId],
      reason: 'o corte manda o takeId da parte que está tocando, a 4ª',
    );
  });

  test('corte antes do nome não quebra a sala', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000],
    );
    final notifier = container.read(salaSessionProvider.notifier);

    final t3take = await gravarMaisUmaParte(container);

    // Grava a parte 4, mas a sala nunca confirma o upload — o time corta o trecho
    // antes do nome chegar.
    harness.room.holdNextTake(KeptScope.parte(4));
    await gravarSemEsperarNome(container);
    await harness.room.untilTakeHeld();

    notifier.startRetro();
    await waitFor(
      'a retro tocar a parte 3',
      () =>
          harness.playback.played.isNotEmpty &&
          harness.playback.played.last == t3take.path,
    );
    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'o trecho da parte 3 chegar à sala',
      () => harness.room.chunksSent == 1,
      limit: const Duration(seconds: 2),
    );

    harness.playback.finishPlayback();
    await waitFor(
      'a parte 3 fechar a fronteira',
      () => container.read(salaSessionProvider).btParteFronteira,
    );
    notifier.ouvirGravacao();
    await waitFor(
      'a retro tocar a parte 4',
      () =>
          harness.playback.played.last ==
          container.read(salaSessionProvider).keptTakes[3].path,
    );

    // Corta três vezes seguidas sem o nome nunca chegar — o suficiente, na régua de hoje
    // (três falhas), para uma falha de sala de verdade parar por uma pessoa. Um nome
    // apenas atrasado não pode contar como essa mesma falha.
    for (var i = 0; i < 3; i++) {
      await theClipOpens(harness);
      harness.playback.at = umaParteInteira + Duration(seconds: i + 1);
      notifier.cortarTrecho();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await settle();
    }

    final depoisDoCorte = container.read(salaSessionProvider);
    expect(
      depoisDoCorte.needsPerson,
      isFalse,
      reason:
          'a sala não pode parar por uma pessoa por um nome que só está atrasado',
    );
    expect(depoisDoCorte.offline, isFalse);
    expect(
      depoisDoCorte.btPhase,
      BtPhase.playing,
      reason: 'a sala segue viva; a equipe pode continuar',
    );

    harness.room.finishHeldTake();
    await waitFor(
      'a parte 4 ser nomeada',
      () => container.read(salaSessionProvider).keptTakes[3].takeId != null,
    );
  });

  test('partes gravadas no ensaio inicial continuam como hoje', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    await settle();

    await gravarSemEsperarNome(container);
    await waitFor('a sala nomear a parte', () {
      final partes = container.read(salaSessionProvider).keptTakes;
      return partes.length == 1 && partes.first.takeId != null;
    });
    final t1 = container.read(salaSessionProvider).keptTakes.first.takeId!;

    notifier.startRetro();
    await waitFor('a retro tocar', () => harness.playback.played.isNotEmpty);

    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    notifier.retroTap();
    await settle();
    await confirmarATraducao(container);
    await waitFor(
      'o trecho chegar à sala',
      () => harness.room.chunksSent == 1,
      limit: const Duration(seconds: 2),
    );

    expect(harness.room.chunkTakes, [t1]);
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
  });
}
