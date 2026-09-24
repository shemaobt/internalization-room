import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;
import 'session_notifier_test.dart' show inConversa, settle;

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() notYet, {
  Duration step = const Duration(milliseconds: 60),
  int times = 20,
}) async {
  for (var i = 0; i < times && notYet(); i++) {
    await tester.pump(step);
  }
}

const _entry = 'Gravar o ensaio de vocês';

Future<ProviderContainer> _pumpInConversa(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await container
      .read(salaSessionProvider.notifier)
      .goConversa(pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 2));
  return container;
}

void main() {
  testWidgets(
    'the entry is on screen from the first turn, before the room says done',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _pumpInConversa(tester, harness);

      expect(
        container.read(salaSessionProvider).voice,
        VoiceState.invite,
        reason: 'a equipe ainda não disse nada',
      );
      expect(harness.room.done, isFalse);
      expect(
        bySemanticsLabelWidget(_entry),
        findsOneWidget,
        reason:
            'a entrada de gravação é alcançável desde o primeiro turno, '
            'não só quando a sala reporta done',
      );
    },
  );

  testWidgets('the entry stays through listening, thinking and speaking', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _pumpInConversa(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.conversaTap();
    await tester.pump();
    expect(read().voice, VoiceState.listening);
    expect(bySemanticsLabelWidget(_entry), findsOneWidget, reason: 'listening');

    harness.room.holdNextTurn();
    notifier.conversaTap();
    await _pumpWhile(tester, () => read().voice != VoiceState.thinking);
    expect(read().voice, VoiceState.thinking);
    expect(bySemanticsLabelWidget(_entry), findsOneWidget, reason: 'thinking');

    harness.voice.holdNextLine();
    harness.room.finishHeldTurn();
    await _pumpWhile(tester, () => read().voice != VoiceState.speaking);
    expect(read().voice, VoiceState.speaking);
    expect(bySemanticsLabelWidget(_entry), findsOneWidget, reason: 'speaking');

    harness.voice.finishHeldLine();
    await _pumpWhile(tester, () => read().voice != VoiceState.invite);
  });

  testWidgets('the entry stays on screen once the room reports done', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)..room.done = true;
    final container = await _pumpInConversa(tester, harness);

    expect(container.read(salaSessionProvider).voice, VoiceState.done);
    expect(bySemanticsLabelWidget(_entry), findsOneWidget);
  });

  testWidgets('a warning does not hide the entry', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await _pumpInConversa(tester, harness);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _pumpWhile(tester, () => !read().warning);
    expect(read().warning, isTrue);

    expect(
      bySemanticsLabelWidget(_entry),
      findsOneWidget,
      reason: 'um aviso não recusa nada à equipe',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'a blocking halt hides the entry, and the desk attending brings it back',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.blocking;
      final container = await _pumpInConversa(tester, harness);
      SalaSessionState read() => container.read(salaSessionProvider);

      await _pumpWhile(tester, () => !read().needsPerson);
      expect(read().needsPerson, isTrue);

      expect(
        bySemanticsLabelWidget(_entry),
        findsNothing,
        reason: 'só uma parada bloqueante esconde a entrada',
      );

      harness.room.theDeskAttended();
      await _pumpWhile(tester, () => read().voice != VoiceState.invite);

      expect(
        bySemanticsLabelWidget(_entry),
        findsOneWidget,
        reason: 'a entrada volta assim que a mesa atende a parada',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('nothing moves when the halt hides the entry', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = await _pumpInConversa(tester, harness);
    SalaSessionState read() => container.read(salaSessionProvider);

    await _pumpWhile(tester, () => !read().needsPerson);
    expect(read().needsPerson, isTrue);
    expect(bySemanticsLabelWidget(_entry), findsNothing);

    final withHalt = tester.getRect(find.byType(FacilitatorCircle).first);

    harness.room.theDeskAttended();
    await _pumpWhile(tester, () => read().voice != VoiceState.invite);
    expect(bySemanticsLabelWidget(_entry), findsOneWidget);

    final withEntry = tester.getRect(find.byType(FacilitatorCircle).first);

    expect(
      withHalt,
      withEntry,
      reason:
          'a fileira de 64px já reserva o lugar da entrada, então mostrá-la '
          'não move o círculo',
    );
    closeTheRoom(container);
  });

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

      await notifier.goConversa(pericope: 'P02');
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
