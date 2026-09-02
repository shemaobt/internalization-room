import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

const _verdictUrl = '/api/internalization-room/voice/veredito';

Future<ProviderContainer> _inConversa(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}

/// Two lines the room tried to say and could not — the ladder, two rungs up.
Future<void> _twoThatWouldNotPlay(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  harness.voice.succeeds = false;
  await notifier.hearAgain();
  await notifier.hearAgain();
  harness.voice.succeeds = true;
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
  test('a verdict that cannot be spoken leaves the room where any unspoken '
      'turn leaves it', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(read().needsPerson, isFalse, reason: 'um degrau não é a escada toda');
    expect(
      read().btPhase,
      isNot(BtPhase.conferida),
      reason: 'a sala encerrava a passagem por causa de um veredito que a '
          'equipe nunca ouviu, e numa sala sem palavra escrita isso é '
          'indistinguível de um app travado',
    );
    expect(
      read().voice,
      VoiceState.invite,
      reason: 'um turno que não foi falado devolve o convite, como nos cinco '
          'irmãos que já fazem isso',
    );
  });

  test('a verdict that could not be said leaves the team a live gesture',
      () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(read().needsPerson, isFalse, reason: 'este é o primeiro degrau');
    expect(
      read().btPhase,
      isNot(BtPhase.thinking),
      reason: 'thinking não aceita toque e não devolve o botão de terminar: a '
          'equipe ficaria olhando "um instante" sem nada para tocar',
    );
    expect(
      read().canFinishBackTranslation,
      isTrue,
      reason: 'o convite tem de vir com um gesto — os cinco irmãos nunca falam '
          'de dentro de thinking, então voice: invite bastava para eles e aqui '
          'não basta; a equipe precisa poder pedir o veredito de novo',
    );
  });

  test('three that could not be spoken, the last of them the verdict, call a '
      'person', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _twoThatWouldNotPlay(harness, notifier);
    expect(read().needsPerson, isFalse);

    await _toTheVerdict(harness, notifier);

    expect(
      read().needsPerson,
      isTrue,
      reason: 'numa sala sem palavra escrita, um veredito que ninguém ouviu é '
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
