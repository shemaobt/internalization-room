import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show holdTheSession, intoTheRecordingHome, settle, theHaltIsLifted;
import 'session_notifier_test.dart' show inConversa;
import 'support/temp.dart';

/// What the recorder did once the start that was in the air answered: a start left
/// running with no Channel holding it records the room until the app is closed.
void _expectTheLateStartDiscarded(
  SalaHarness harness,
  int soundsBefore,
  SalaSessionState state,
) {
  final sounds = harness.sounds;
  expect(
    sounds.lastIndexOf('recorder:discard'),
    allOf(
      greaterThanOrEqualTo(soundsBefore),
      greaterThan(sounds.lastIndexOf('recorder:start')),
    ),
    reason:
        'o gravador que abriu depois de o seu microfone fechar ficava '
        'gravando a sala sem ninguém segurando o canal',
  );
  expect(state.channel, isNot(isA<Microphone>()));
}

/// A room reopened straight into the rehearsal over one kept part, with a warning
/// standing so the watch beats. The shape of the one in
/// `a_permission_answer_after_a_halt_keeps_the_halt_test.dart`; fixtures never travel
/// between modules.
Future<ProviderContainer> _inTheRehearsalWithAWarning(
  SalaHarness harness,
) async {
  final gravada = File('${aTempDir('sala-1347').path}/p1.m4a')
    ..writeAsBytesSync([1, 2, 3]);
  harness.room.serverStatus = 'needs_person';
  harness.room.serverHalt = HaltKind.warning;
  await holdTheSession(
    harness,
    ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    ),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.openTheRoom();
  await intoTheRecordingHome(
    notifier,
    () => container.read(salaSessionProvider),
  );
  await waitFor(
    'o aviso chegar',
    () => container.read(salaSessionProvider).warning,
  );
  return container;
}

void main() {
  group('a recorder start still in the air is discarded when, before it '
      'answers,', () {
    test('a question is sent', () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.handTap();
      await settle();
      harness.recorder.holdNextStart();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'a pergunta sair',
        () => harness.inbox.questionsSent.isNotEmpty,
      );
      await settle();
      final soundsBefore = harness.sounds.length;
      final questionsBefore = harness.inbox.questionsSent.length;

      harness.recorder.finishStart();
      await settle();

      _expectTheLateStartDiscarded(harness, soundsBefore, read());
      expect(harness.inbox.questionsSent, hasLength(questionsBefore));
    });

    test('a Rehearsal take finishes', () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      harness.recorder.holdNextStart();
      notifier.gravarACena(1);
      await settle();
      notifier.gravarACena(1);
      await waitFor(
        'a tomada voltar',
        () => read().ensaio == EnsaioStatus.recorded,
      );
      final soundsBefore = harness.sounds.length;
      final partsBefore = read().partes.length;

      harness.recorder.finishStart();
      await settle();

      _expectTheLateStartDiscarded(harness, soundsBefore, read());
      expect(read().partes, hasLength(partsBefore));
    });

    test('a blocking halt is cleared by the tap', () async {
      final harness = SalaHarness(settleDelay: const Duration(seconds: 3));
      final container = await _inTheRehearsalWithAWarning(harness);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.recorder.holdNextStart();
      notifier.gravarACena(2);
      await waitFor(
        'o ensaio começar a gravar',
        () => read().ensaio == EnsaioStatus.recording,
      );
      notifier.haltForABrokenBuild();
      expect(read().needsPerson, isTrue);
      await theHaltIsLifted(harness, notifier, read);
      final soundsBefore = harness.sounds.length;
      final partsBefore = read().partes.length;

      harness.recorder.finishStart();
      await settle();

      _expectTheLateStartDiscarded(harness, soundsBefore, read());
      expect(read().partes, hasLength(partsBefore));
    });

    test('the passage changes', () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.recorder.holdNextStart();
      notifier.conversaTap();
      await settle();
      await notifier.goConversa(book: 'Ruth', pericope: 'P02');
      await waitFor('P02 abrir', () => read().voice == VoiceState.invite);
      final soundsBefore = harness.sounds.length;
      final turnsBefore = harness.room.turnsSent;

      harness.recorder.finishStart();
      await settle();

      _expectTheLateStartDiscarded(harness, soundsBefore, read());
      expect(harness.room.turnsSent, turnsBefore);
    });
  });

  group('a start that is not the newest is never kept', () {
    Future<(SalaHarness, SalaSessionState Function())>
    twoStartsInTheAir() async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      harness.recorder.holdNextStart();
      notifier.gravarACena(1);
      await settle();
      notifier.gravarACena(1);
      await waitFor(
        'a primeira tomada voltar',
        () => read().ensaio == EnsaioStatus.recorded,
      );
      harness.recorder.holdNextStart();
      notifier.gravarACena(1);
      await waitFor(
        'a segunda abertura sair',
        () => read().ensaio == EnsaioStatus.recording,
      );
      return (harness, read);
    }

    test('and it never stops the newest', () async {
      final (harness, read) = await twoStartsInTheAir();
      final soundsBefore = harness.sounds.length;

      harness.recorder.finishStart();
      await settle();

      expect(
        harness.sounds.skip(soundsBefore),
        isNot(contains('recorder:discard')),
        reason:
            'o gravador é um só: descartar a abertura velha pararia a nova, '
            'que a equipe acabou de pedir',
      );
      harness.recorder.finishStart();
      await settle();
      expect(read().channel, isA<Microphone>());
    });

    test('and it is discarded when the newest never started', () async {
      final (harness, read) = await twoStartsInTheAir();
      harness.recorder.finishStart();
      await settle();
      final soundsBefore = harness.sounds.length;

      harness.recorder.startThrows = true;
      harness.recorder.finishStart();
      await settle();

      expect(
        harness.sounds.skip(soundsBefore),
        contains('recorder:discard'),
        reason:
            'sem a abertura nova, a velha seguia gravando a sala sem ninguém '
            'segurando o canal',
      );
      expect(read().channel, isNot(isA<Microphone>()));
    });
  });

  test(
    'an older start is discarded when the newest failed before it answered',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      harness.recorder.holdNextStart();
      notifier.gravarACena(1);
      await settle();
      notifier.gravarACena(1);
      await waitFor(
        'a primeira tomada voltar',
        () => read().ensaio == EnsaioStatus.recorded,
      );
      harness.recorder.startThrows = true;
      notifier.gravarACena(1);
      await settle();
      harness.recorder.startThrows = false;
      final soundsBefore = harness.sounds.length;

      harness.recorder.finishStart();
      await settle();

      expect(
        harness.sounds.skip(soundsBefore),
        contains('recorder:discard'),
        reason: 'a abertura velha seria a única gravando, sem ninguém no canal',
      );
    },
  );

  test('an older start of the passage before is discarded when the newest '
      'never started', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    harness.recorder.holdNextStart();
    notifier.gravarACena(1);
    await settle();
    await notifier.goConversa(book: 'Ruth', pericope: 'P02');
    await waitFor('P02 abrir', () => read().voice == VoiceState.invite);
    notifier.goEnsaio();
    harness.recorder.startThrows = true;
    notifier.gravarACena(1);
    await settle();
    harness.recorder.startThrows = false;
    final soundsBefore = harness.sounds.length;

    harness.recorder.finishStart();
    await settle();

    expect(
      harness.sounds.skip(soundsBefore),
      contains('recorder:discard'),
      reason:
          'a abertura da passagem de antes gravava a sala sem canal quando a '
          'nova não abriu',
    );
    expect(read().channel, isNot(isA<Microphone>()));
  });

  test('an older start is discarded when the newest fails after the passage '
      'changed', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    notifier.goEnsaio();
    harness.recorder.holdNextStart();
    notifier.gravarACena(1);
    await settle();
    notifier.gravarACena(1);
    await waitFor(
      'a primeira tomada voltar',
      () => read().ensaio == EnsaioStatus.recorded,
    );
    harness.recorder.holdNextStart();
    notifier.gravarACena(1);
    await settle();
    await notifier.goConversa(book: 'Ruth', pericope: 'P02');
    await waitFor('P02 abrir', () => read().voice == VoiceState.invite);
    harness.recorder.finishStart();
    await settle();
    final soundsBefore = harness.sounds.length;

    harness.recorder.startThrows = true;
    harness.recorder.finishStart();
    await settle();

    expect(harness.sounds.skip(soundsBefore), contains('recorder:discard'));
  });
}
