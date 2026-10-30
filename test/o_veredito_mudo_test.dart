import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
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
  SalaSessionNotifier notifier, {
  void Function()? beforeTheVerdict,
}) async {
  notifier.goEnsaio();
  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  notifier.startRetro();
  await settle();
  harness.playback.finishPlayback();
  await settle();
  beforeTheVerdict?.call();
  await notifier.finishBackTranslation();
  await settle();
}

void main() {
  test('a verdict that arrives without audio writes her «não deu para '
      'conferir», asks the voice for nothing, and calls nobody', () async {
    final harness = SalaHarness()..room.verdictAudioUrl = '';
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(
      read().btRecusa,
      CheckRefusal.checkUnavailable,
      reason:
          'um veredito sem áudio descia pelo recarregamento da resposta e '
          'deixava a tela sem linha nenhuma',
    );
    expect(read().btPhase, BtPhase.playing);
    expect(
      harness.voice.played.where((url) => url.isEmpty),
      isEmpty,
      reason: 'a voz era chamada com um endereço vazio',
    );
    expect(read().machine.aHaltWaitsForTheCanvas, isNull);
    expect(read().needsPerson, isFalse);
    expect(read().canFinishBackTranslation, isTrue);
  });

  test('a verdict whose sound fails is tried once, writes her «não deu para '
      'conferir», and calls nobody, as hers', () async {
    final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(harness, notifier);

    expect(
      harness.voice.played.where((url) => url == _verdictUrl),
      hasLength(1),
      reason:
          'o veredito era carregado mais uma vez 1,5 s depois; o dela toca '
          'uma vez e volta ao repouso',
    );
    expect(
      read().btRecusa,
      CheckRefusal.checkUnavailable,
      reason: 'o veredito que não soava deixava a tela sem linha nenhuma',
    );
    expect(
      read().machine.aHaltWaitsForTheCanvas,
      isNull,
      reason:
          'a segunda falha deixava uma chamada por pessoa esperando a '
          'conversa, por um veredito que o dela nunca conta',
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

  test(
    'a verdict that would not sound is heard through «ouvir a resposta de '
    'novo» once the player allows, and nothing waits for the conversation',
    () async {
      final harness = SalaHarness()..voice.refuses.add(_verdictUrl);
      final container = await _inConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await _toTheVerdict(harness, notifier);
      expect(read().machine.aHaltWaitsForTheCanvas, isNull);

      harness.voice.refuses.remove(_verdictUrl);
      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'o veredito soar de novo',
        () =>
            harness.voice.played.where((url) => url == _verdictUrl).length == 2,
      );

      expect(
        harness.voice.played.where((url) => url == _verdictUrl),
        hasLength(2),
        reason: 'o veredito que não soou não voltava pelo ouvir de novo',
      );
      expect(read().machine.aHaltWaitsForTheCanvas, isNull);
      expect(read().needsPerson, isFalse);
    },
  );

  test(
    'a verdict whose clip never comes down is not handed to «ouvir a '
    'resposta de novo», as her replay exists only once the audio arrived',
    () async {
      final harness = SalaHarness();
      final container = await _inConversa(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      Object? before;

      await _toTheVerdict(
        harness,
        notifier,
        beforeTheVerdict: () {
          before = read().lastSpoken;
          harness.voice.succeeds = false;
        },
      );

      expect(harness.voice.played, isNot(contains(_verdictUrl)));
      expect(read().btRecusa, CheckRefusal.checkUnavailable);
      expect(
        identical(read().lastSpoken, before),
        isTrue,
        reason:
            'o veredito cujo clipe nunca desceu era entregue ao ouvir de novo, '
            'e o toque carregava de novo e chamava uma pessoa pela conversa',
      );
      expect(read().offersTheVerdictAgain, isFalse);
    },
  );

  test('a verdict whose clip the room refuses writes her «não deu para '
      'conferir» and calls nobody, as a refused check does', () async {
    final harness = SalaHarness();
    final container = await _inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _toTheVerdict(
      harness,
      notifier,
      beforeTheVerdict: () =>
          harness.voice.roomFailsWith = const Refused('HTTP_500'),
    );

    expect(
      read().btRecusa,
      CheckRefusal.checkUnavailable,
      reason:
          'a sala recusando o clipe do veredito soltava o passo em silêncio, '
          'sem a linha que a recusa da própria conferência escreve',
    );
    expect(read().btPhase, BtPhase.playing);
    expect(read().machine.aHaltWaitsForTheCanvas, isNull);
    expect(read().needsPerson, isFalse);
    expect(read().canFinishBackTranslation, isTrue);
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
