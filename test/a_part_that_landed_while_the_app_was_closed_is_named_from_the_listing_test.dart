import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_parte_da_volta_ganha_nome_test.dart' show gravarSemEsperarNome;
import 'fakes.dart';
import 'resto_da_historia_test.dart' show aRetomadaNoEnsaio;
import 'scenario_helpers.dart' show relaunch, settle, umaParteInteira;

final _parte3 = KeptScope.parte(3);

Future<(SalaHarness, ProviderContainer)>
_aParte3QueChegouComOAppFechado() async {
  final (harness, container) = await _aParte3QueChegouLongeDaPassagem();
  return relaunch(harness, container);
}

Future<void> _voltarAoEnsaio(ProviderContainer container) async {
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await settle();
  expect(container.read(salaSessionProvider).stage, SalaStage.ensaio);
}

String _oNomeQueASalaDeu(SalaHarness harness) =>
    harness.room.takes.lastWhere((take) => take.scope == _parte3).takeId;

Future<void> _aParte3GanhaONome(ProviderContainer container) => waitFor(
  'a parte 3 ganhar o nome da sala',
  () => container.read(salaSessionProvider).partes[2].takeId != null,
  limit: const Duration(seconds: 5),
);

Future<(SalaHarness, ProviderContainer)>
_aParte3QueChegouLongeDaPassagem() async {
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
  return (harness, container);
}

Future<ProviderContainer> _umaLinhaComAParte3SemNome(
  SalaHarness harness,
) async {
  final home = Directory.systemTemp.createTempSync('sala-parte-sem-nome');
  addTearDown(() => home.deleteSync(recursive: true));
  await harness.emAberto.remember(
    'Ruth',
    'P01',
    'pt',
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [
        for (var parte = 1; parte <= 3; parte++)
          KeptTake(
            scopeId: KeptScope.parte(parte),
            path: (File(
              '${home.path}/p$parte.m4a',
            )..writeAsBytesSync([1, 2, 3])).path,
            takeId: parte == 3 ? null : 'antiga-$parte',
          ),
      ],
    ),
  );
  harness.room.takes.addAll([
    for (var parte = 1; parte <= 3; parte++)
      TakeView(
        takeId: parte == 3 ? 'da-sala-3' : 'antiga-$parte',
        kind: partTakeKind,
        scope: KeptScope.parte(parte),
        ordinal: parte,
        pass: 1,
      ),
  ]);
  harness.room.failTakesWith = const NetworkFailed('sem rede');
  final container = harness.container();
  addTearDown(container.dispose);
  await _voltarAoEnsaio(container);
  expect(container.read(salaSessionProvider).partes[2].takeId, isNull);
  return container;
}

void main() {
  test('a name taken from the listing on a relaunch into the passage is '
      'written to the row at once, under the station the row said', () async {
    final before = SalaHarness();
    final first = await _umaLinhaComAParte3SemNome(before);
    final (harness, container) = await relaunch(before, first);
    harness.room.failTakesWith = null;
    await container.read(salaSessionProvider.notifier).openTheRoom();
    await _aParte3GanhaONome(container);

    final linha = before.emAberto.rows['Ruth/P01/pt']!;
    expect(
      linha.takes.where((take) => take.scopeId == _parte3).single.takeId,
      'da-sala-3',
      reason:
          'o nome vindo da listagem só ia ao disco na próxima gravação da '
          'linha, e um fechamento antes dela devolvia a parte sem nome',
    );
    expect(
      linha.stage,
      SalaStage.ensaio,
      reason:
          'a gravação da linha na retomada direta à passagem escrevia a tela '
          'onde a equipe estava, a conversa, e a próxima abertura não achava '
          'mais o ensaio',
    );
  });

  test('after the relaunch the check hears the part under its name and cuts '
      'its stretch by part, not turned away as having no part', () async {
    final (harness, container) = await _aParte3QueChegouComOAppFechado();
    await _voltarAoEnsaio(container);
    await _aParte3GanhaONome(container);
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
          'o trecho contado sobre a parte que chegou com o app fechado era '
          'recusado por não ter parte',
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
      reason:
          'a escuta da parte que chegou com o app fechado nunca chegava à '
          'sala, e a conferência a contava como não ouvida',
    );
  });

  test('a part still in the Outbox at the kill never takes the name of another '
      'take at its number, it waits to go up', () async {
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
    harness.room.takes.add(
      TakeView(
        takeId: 'de-outro-tablet',
        kind: partTakeKind,
        scope: _parte3,
        ordinal: 3,
        pass: 1,
      ),
    );
    final (again, next) = await relaunch(harness, container);

    await _voltarAoEnsaio(next);
    await waitFor(
      'a parte 3 aparecer por enviar',
      () => next.read(salaSessionProvider).unsentParts.containsKey(3),
    );
    await settle();

    expect(
      next.read(salaSessionProvider).partes[2].takeId,
      isNull,
      reason:
          'a parte ainda na Fila tomava o nome de outra gravação do mesmo '
          'número, e o trecho contado sobre ela ia para a gravação errada',
    );
    expect(again.room.clipsFetched, isEmpty);
  });

  test('a standing part the resume could not name is named when the recording '
      'home lays in the listing, not left nameless', () async {
    final before = SalaHarness();
    final first = await _umaLinhaComAParte3SemNome(before);
    final (harness, container) = await relaunch(before, first);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.openTheRoom();
    await waitFor(
      'a equipe pousar na conversa',
      () =>
          container.read(salaSessionProvider).sessionId == 'sessao-antiga' &&
          !container.read(salaSessionProvider).awaitingTheGuide,
    );
    await settle();
    expect(container.read(salaSessionProvider).partes[2].takeId, isNull);
    harness.room.failTakesWith = null;

    notifier.openTheEnsaioFinal();
    await waitFor(
      'a casa das gravações abrir',
      () => container.read(salaSessionProvider).stage == SalaStage.ensaio,
    );
    await _aParte3GanhaONome(container);

    expect(
      container.read(salaSessionProvider).partes[2].takeId,
      'da-sala-3',
      reason:
          'a casa das gravações deitava só as partes de fileiras vazias e '
          'nunca tocava uma fileira com parte, mesmo sem nome',
    );
    expect(harness.room.clipsFetched, isEmpty);
  });

  test('a name taken back from the Outbox is written to the row at once, not '
      'left for the next save', () async {
    final (harness, container) = await _aParte3QueChegouLongeDaPassagem();
    await _voltarAoEnsaio(container);
    await _aParte3GanhaONome(container);

    final guardada = harness.emAberto.rows['Ruth/P01/pt']!.takes
        .where((take) => take.scopeId == _parte3)
        .single;
    expect(
      guardada.takeId,
      _oNomeQueASalaDeu(harness),
      reason:
          'o nome adotado só ia ao disco na próxima gravação da linha, e um '
          'fechamento antes dela devolvia a parte sem nome',
    );
  });

  test('a part that landed while the app was closed comes back named from the '
      "room's listing, not nameless", () async {
    final (harness, container) = await _aParte3QueChegouComOAppFechado();

    await _voltarAoEnsaio(container);
    await _aParte3GanhaONome(container);

    final parte3 = container.read(salaSessionProvider).partes[2];
    expect(
      parte3.takeId,
      _oNomeQueASalaDeu(harness),
      reason:
          'a parte que chegou à sala com o app fechado voltava sem nome, e a '
          'conferência a contava como não ouvida',
    );
    expect(
      harness.room.clipsFetched,
      isEmpty,
      reason:
          'o arquivo da parte já estava no tablet; buscar uma cópia gastaria '
          'a rede da equipe',
    );
  });
}
