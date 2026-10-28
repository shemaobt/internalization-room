import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _verdictUrl = '/api/internalization-room/voice/veredito';

Future<ProviderContainer> _inConversa(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await settle();
  return container;
}

/// Tell the passage back and ask the room for its verdict.
Future<void> _toTheVerdict(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  notifier.startRetro();
  await settle();
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await settle();
}

void main() {
  test('a verdict that cannot be spoken leaves the room, once the sign is '
      'cleared, where any unspoken turn leaves it', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);
    notifier.teamTapped();
    await settle();

    expect(read().needsPerson, isFalse);
    expect(
      read().btPhase,
      isNot(BtPhase.conferida),
      reason:
          'a sala encerrava a passagem por causa de um veredito que a '
          'equipe nunca ouviu, e numa sala sem palavra escrita isso é '
          'indistinguível de um app travado',
    );
    expect(
      read().voice,
      VoiceState.invite,
      reason:
          'um turno que não foi falado devolve o convite, como nos cinco '
          'irmãos que já fazem isso',
    );
  });

  test('a verdict that could not be said leaves the team a live gesture once the '
      'sign is cleared', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);
    notifier.teamTapped();
    await settle();

    expect(read().needsPerson, isFalse);
    expect(
      read().btPhase,
      isNot(BtPhase.thinking),
      reason:
          'thinking não aceita toque e não devolve o botão de terminar: a '
          'equipe ficaria olhando "um instante" sem nada para tocar',
    );
    expect(
      read().canFinishBackTranslation,
      isTrue,
      reason:
          'o convite tem de vir com um gesto — os cinco irmãos nunca falam '
          'de dentro de thinking, então voice: invite bastava para eles e aqui '
          'não basta; a equipe precisa poder pedir o veredito de novo',
    );
  });

  test('a verdict whose sound fails to load twice calls a person', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(
      harness.voice.played.where((url) => url == _verdictUrl),
      hasLength(2),
    );
    expect(
      read().needsPerson,
      isTrue,
      reason:
          'numa sala sem palavra escrita, um veredito que ninguém ouviu é '
          'indistinguível de um app travado — e a escada existe para chamar '
          'alguém antes disso',
    );
  });

  test('a verdict that speaks calls nobody', () async {
    final harness = SalaHarness();
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(read().needsPerson, isFalse);
    expect(harness.voice.played, contains(_verdictUrl));
  });
}
