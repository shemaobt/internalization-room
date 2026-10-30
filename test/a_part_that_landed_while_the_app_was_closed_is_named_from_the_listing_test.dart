import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_parte_da_volta_ganha_nome_test.dart' show gravarSemEsperarNome;
import 'fakes.dart';
import 'resto_da_historia_test.dart' show aRetomadaNoEnsaio;
import 'scenario_helpers.dart' show relaunch, settle;

final _parte3 = KeptScope.parte(3);

Future<(SalaHarness, ProviderContainer)>
_aParte3QueChegouComOAppFechado() async {
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

void main() {
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
