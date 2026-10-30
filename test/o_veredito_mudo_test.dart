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
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  await untilTheAdvanceDiscLights(notifier);
  notifier.startRetro();
  await settle();
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await settle();
}

void main() {
  test('a verdict whose sound fails to load twice leaves the back-translation '
      'with no sign and a live «terminei», as hers', () async {
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
      isFalse,
      reason:
          'o sinal cobria a retro, e o Drafting dela só volta ao repouso '
          'quando o som do veredito falha',
    );
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
    expect(
      read().canFinishBackTranslation,
      isTrue,
      reason:
          'thinking não aceita toque e não devolve o botão de terminar: a '
          'equipe precisa poder pedir o veredito de novo',
    );
  });

  test('a verdict whose sound fails to load twice is still offered by «ouvir a '
      'resposta de novo», as hers', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(read().needsPerson, isFalse);
    expect(
      read().canHearTheVerdictAgain,
      isTrue,
      reason:
          'sem o sinal, o veredito que não soou sumia; o dela guarda a '
          'resposta antes de tocar e oferece ouvir de novo',
    );
  });

  test('a verdict heard again after its sound failed twice leaves nothing '
      'waiting to call a person on the conversation', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);
    expect(read().machine.aHaltWaitsForTheCanvas, isNotNull);

    harness.voice.refuses.remove(_verdictUrl);
    notifier.ouvirARespostaDeNovo();
    await waitFor(
      'o veredito soar de novo',
      () => read().machine.aHaltWaitsForTheCanvas == null,
    );

    expect(
      read().machine.aHaltWaitsForTheCanvas,
      isNull,
      reason:
          'o veredito ouvido de novo deixava de pé a chamada por uma pessoa '
          'que subiria na conversa',
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
