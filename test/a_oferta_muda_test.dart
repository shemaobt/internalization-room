import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

/// The name of the first passage on the wheel, which is the one offered first.
const _oferecidaUrl = '/voice/p01';

/// Open the wheel. Opening it already offers the first passage, so this is the room's
/// first attempt at saying that name.
Future<ProviderContainer> _atTheWheel(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await waitFor(
    'a roda carregar',
    () => container.read(salaSessionProvider).naRoda != null,
  );
  await settle();
  return container;
}

int _timesOffered(SalaHarness harness) =>
    harness.voice.played.where((url) => url == _oferecidaUrl).length;

void main() {
  test('two offers the room could not say call a person', () async {
    final harness = SalaHarness()..voice.refuses.add(_oferecidaUrl);
    final container = await _atTheWheel(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    // Abrir a roda já é a primeira tentativa.
    expect(_timesOffered(harness), 1);
    expect(read().needsPerson, isFalse, reason: 'um degrau não é a escada');

    notifier.escolhaTap();
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'numa sala sem palavra escrita, um nome que ninguém ouviu é uma '
          'roda que parece parada, e uma roda parada que não chama ninguém '
          'deixa a equipe sozinha com ela',
    );
    expect(_timesOffered(harness), 2);
  });

  test('a turn and then the offer, both unsaid, call a person', () async {
    final harness = SalaHarness()..voice.refuses.add(_oferecidaUrl);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await notifier.goConversa();
    await settle();
    harness.voice.succeeds = false;
    await notifier.hearAgain();
    harness.voice.succeeds = true;
    expect(read().needsPerson, isFalse, reason: 'um degrau, não dois');

    await notifier.abrirEscolha();
    await waitFor('a roda carregar', () => read().naRoda != null);
    await settle();

    expect(
      read().needsPerson,
      isTrue,
      reason:
          'a oferta muda tem de subir a mesma escada dos turnos, não uma '
          'contagem paralela sua',
    );
  });

  test('an offer the room says changes nothing', () async {
    final harness = SalaHarness();
    final container = await _atTheWheel(harness);
    SalaSessionState read() => container.read(salaSessionProvider);

    expect(_timesOffered(harness), 1);
    expect(read().needsPerson, isFalse);
    expect(read().voice, VoiceState.invite);
  });
}
