import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

void main() {
  test('a start answering after the room is gone touches nothing', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.recorder.holdNextStart();
    notifier.conversaTap();
    await settle();

    container.dispose();
    harness.recorder.finishStart();
    await settle();
  });

  test(
    'goEnsaio while the recorder start is still in the air leaves no microphone open',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.recorder.holdNextStart();
      notifier.conversaTap();
      await settle();
      expect(read().voice, VoiceState.listening);

      notifier.goEnsaio();
      final deletedBefore = harness.recorder.deleted.length;
      harness.recorder.finishStart();
      await settle();

      expect(read().stage, SalaStage.ensaio);
      expect(
        harness.recorder.deleted.length,
        greaterThan(deletedBefore),
        reason:
            'a abertura do microfone que chegou depois do goEnsaio precisa '
            'ser descartada, não deixada aberta dentro do ensaio',
      );
    },
  );

  test(
    'the rehearsal own start is not discarded by the conversa mic answering late',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.recorder.holdNextStart();
      notifier.conversaTap();
      await settle();
      expect(read().voice, VoiceState.listening);

      notifier.goEnsaio();
      notifier.ensaioTap();
      await settle();
      expect(read().ensaio, EnsaioStatus.recording);

      final deletedBefore = harness.recorder.deleted.length;
      harness.recorder.finishStart();
      await settle();

      expect(
        read().ensaio,
        EnsaioStatus.recording,
        reason:
            'a conversa é que ficou a abrir; o ensaio já abriu o seu '
            'próprio microfone de verdade, e a resposta atrasada da '
            'conversa não pode fechar o que o ensaio abriu',
      );
      expect(harness.recorder.deleted.length, deletedBefore);
    },
  );

  test(
    'the next passage own start is not discarded by the previous one answering late',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.recorder.holdNextStart();
      notifier.conversaTap();
      await settle();
      expect(read().voice, VoiceState.listening);

      await notifier.goConversa(book: 'Ruth', pericope: 'P02');
      await waitFor('P02 abrir', () => read().voice == VoiceState.invite);
      notifier.conversaTap();
      await settle();
      expect(read().voice, VoiceState.listening);

      final deletedBefore = harness.recorder.deleted.length;
      harness.recorder.finishStart();
      await settle();

      expect(
        read().voice,
        VoiceState.listening,
        reason:
            'P01 é que ficou a abrir; P02 já abriu o seu próprio microfone '
            'de verdade, e a resposta atrasada de P01 não pode fechá-lo',
      );
      expect(harness.recorder.deleted.length, deletedBefore);
    },
  );

  test('goEnsaio mid-thinking leaves nothing sounding afterwards', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.conversaTap();
    await settle();
    harness.room.holdNextTurn();
    notifier.conversaTap();
    await settle();
    expect(read().voice, VoiceState.thinking);

    notifier.goEnsaio();
    final upToGesture = harness.sounds.length;
    harness.room.finishHeldTurn();
    await settle(const Duration(milliseconds: 300));

    expect(read().stage, SalaStage.ensaio);
    expect(read().voice, VoiceState.invite);
    final soundsAfter = harness.sounds.skip(upToGesture);
    expect(
      soundsAfter.where(
        (som) => som == 'playback:play' || som.startsWith('voice:'),
      ),
      isEmpty,
      reason:
          'a resposta do servidor chegou depois do gesto ter movido a sala '
          'para o ensaio; nada disso pode soar',
    );
  });

  test('goEnsaio mid-speaking leaves nothing sounding afterwards', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    harness.voice.holdNextLine();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    expect(read().voice, VoiceState.speaking);

    final calando = harness.sounds.length;
    notifier.goEnsaio();
    await settle();

    expect(read().stage, SalaStage.ensaio);
    expect(read().voice, VoiceState.invite);
    expect(harness.sounds.skip(calando), contains('voice:stop'));

    harness.voice.finishHeldLine();
    await settle();

    expect(
      harness.sounds.where((som) => som == 'playback:play'),
      isEmpty,
      reason:
          'a Guia continuava falando por baixo do gesto; ela tem de calar, nunca tocar depois',
    );
  });
}
