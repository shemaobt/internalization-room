import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';

import 'a_parte_da_volta_ganha_nome_test.dart' show gravarSemEsperarNome;
import 'fakes.dart';
import 'resto_da_historia_test.dart' show aRetomadaNoEnsaio;
import 'scenario_helpers.dart'
    show intoTheRecordingHome, relaunch, settle, umaParteInteira;

final _parte3 = KeptScope.parte(3);

Future<(SalaHarness, ProviderContainer)> _aParte3QueNaoChegou() async {
  final harness = SalaHarness();
  final container = await aRetomadaNoEnsaio(
    harness,
    traduzidasAte: [30000, 30000],
  );
  harness.room.unreachableTake = 'ensaio/$_parte3';
  await gravarSemEsperarNome(container, 3);
  await waitFor(
    'a parte 3 ficar na Fila',
    () async =>
        (await harness.takes.pending()).any((row) => row.scope == _parte3),
  );
  await settle();
  return relaunch(harness, container);
}

Future<void> _voltarAoEnsaio(ProviderContainer container) async {
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await intoTheRecordingHome(
    notifier,
    () => container.read(salaSessionProvider),
  );
}

String _oNomeQueASalaDeu(SalaHarness harness) =>
    harness.room.takes.lastWhere((take) => take.scope == _parte3).takeId;

Future<void> _enviarAParte3Agora(
  SalaHarness harness,
  ProviderContainer container,
) async {
  await waitFor(
    'a parte 3 aparecer por enviar',
    () => container.read(salaSessionProvider).unsentParts.containsKey(3),
  );
  harness.room.unreachableTake = null;
  container.read(salaSessionProvider.notifier).enviarACena(3);
  await waitFor(
    'a parte 3 chegar à sala',
    () => harness.room.takesKept.contains('ensaio/$_parte3'),
  );
  await waitFor(
    'a parte 3 ganhar um nome',
    () => container.read(salaSessionProvider).partes[2].takeId != null,
    limit: const Duration(seconds: 5),
  );
}

void main() {
  test('a part kept on one visit and landed on the next takes the name the '
      'room gave it, not none', () async {
    final (harness, container) = await _aParte3QueNaoChegou();
    await _voltarAoEnsaio(container);
    expect(container.read(salaSessionProvider).partes[2].takeId, isNull);

    await _enviarAParte3Agora(harness, container);

    expect(
      container.read(salaSessionProvider).partes[2].takeId,
      _oNomeQueASalaDeu(harness),
      reason:
          'a parte enviada numa visita anterior chegava sem nome, e a '
          'conferência a contava como não ouvida',
    );
  });

  test('a part landed on a later visit is heard and told back under its own '
      'name, not turned away as having no part', () async {
    final (harness, container) = await _aParte3QueNaoChegou();
    await _voltarAoEnsaio(container);
    await _enviarAParte3Agora(harness, container);
    final nome = _oNomeQueASalaDeu(harness);
    final parte3 = container.read(salaSessionProvider).partes[2];
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.startRetro();
    await waitFor(
      'a retro tocar a parte 3',
      () =>
          harness.playback.played.isNotEmpty &&
          harness.playback.played.last == parte3.path,
    );
    await theClipOpens(harness);
    harness.playback.at = umaParteInteira;
    notifier.retroTap();
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
      [nome],
      reason:
          'o trecho contado sobre a parte de outra visita era recusado por '
          'não ter parte',
    );
    harness.playback.finishPlayback();
    await waitFor(
      'a escuta da parte 3 chegar à sala',
      () => harness.room.listeningReports.isNotEmpty,
      limit: const Duration(seconds: 2),
    );
    expect(
      [
        for (final relato in harness.room.listeningReports)
          for (final parte in relato) parte['take_id'],
      ],
      contains(nome),
      reason: 'a escuta da parte de outra visita nunca chegava à sala',
    );
  });

  test('a part that landed while the team was away from its passage comes '
      'back with its name, not without one', () async {
    final harness = SalaHarness();
    final container = await aRetomadaNoEnsaio(
      harness,
      traduzidasAte: [30000, 30000],
    );
    harness.room.holdNextTake(_parte3);
    await gravarSemEsperarNome(container, 3);
    await harness.room.untilTakeHeld();
    container.read(salaSessionProvider.notifier).leaveThePassage();
    await settle();
    harness.room.finishHeldTake();
    await waitFor(
      'a parte 3 chegar à sala',
      () => harness.room.takesKept.contains('ensaio/$_parte3'),
    );
    await settle();

    await _voltarAoEnsaio(container);
    await waitFor(
      'a parte 3 voltar com nome',
      () => container.read(salaSessionProvider).partes[2].takeId != null,
      limit: const Duration(seconds: 5),
    );

    expect(
      container.read(salaSessionProvider).partes[2].takeId,
      _oNomeQueASalaDeu(harness),
      reason:
          'a parte que chegou à sala longe da passagem voltava sem nome, e a '
          'conferência a contava como não ouvida',
    );
  });
}
