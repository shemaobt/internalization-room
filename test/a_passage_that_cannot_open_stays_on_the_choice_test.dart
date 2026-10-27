import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _theBook = [
  _panorama,
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
  Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
];

void main() {
  test('a passage the room refuses to open returns the team to the passage '
      'choice with the entry in place and tappable', () async {
    final harness = SalaHarness()
      ..room.passages = _theBook
      ..room.passagesThatCannotOpen = {'P02'};
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P02');
    await waitFor(
      'the room to answer the tap',
      () => harness.room.calls.contains('createSession'),
    );
    await waitFor(
      'the Choice to come back',
      () => read().station is Menu && read().naRoda != null,
    );
    await settle();

    expect(read().station, isA<Menu>());
    expect(read().needsPerson, isFalse);
    expect(read().naRoda, _theBook);

    expect(read().entriesOpen, isTrue);

    harness.room.passagesThatCannotOpen = {};
    await enterThePassage(notifier, read, 'P02');
    await waitFor('P02 to open', () => read().sessionId != null);

    expect(read().station, isA<Canvas>());
    expect(harness.room.pericopesAsked, ['P02']);
  });

  test('a passage the room cannot be reached for leaves the team on the '
      'Choice with the entries live, and the same pill asks again', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await notifier.abrirEscolha();
    await waitFor('the Choice to list its entries', () => read().entriesOpen);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final before = harness.room.calls.length;
    harness.room.reachable = false;

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked',
      () => harness.room.calls.skip(before).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a equipe ficava na tela de uma passagem sem sessão',
    );
    expect(read().entriesOpen, isTrue);
    expect(read().naRoda, _theBook);
    expect(
      harness.room.calls.skip(before),
      ['createSession'],
      reason: 'só a sessão foi pedida; a roda não é lida de novo',
    );

    harness.room.reachable = true;
    notifier.openTheEntry(p02);
    await waitFor('P02 to open', () => read().sessionId != null);

    expect(read().station, isA<Canvas>());
    expect(
      harness.room.calls.skip(before).where((call) => call == 'createSession'),
      hasLength(2),
    );
  });

  test('a failed open from the Choice keeps the way back to the passage the '
      'team left, and asks the room for nothing else', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    final p01 = read().sessionId;
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final before = harness.room.calls.length;
    harness.room.reachable = false;

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked',
      () => harness.room.calls.skip(before).contains('createSession'),
    );
    await settle();
    await settle();

    expect(read().station, isA<Menu>());
    expect(
      read().theWayBackIsLive,
      isTrue,
      reason: 'o toque na P02 apagava o caminho de volta para a P01',
    );
    expect(read().leftEntry?.pericope, 'P01');
    expect(read().leftEntry?.session, p01);
    expect(harness.room.calls.skip(before), ['createSession']);
  });

  test('a passage resumed from its pill no longer holds the way back to the '
      'passage left before it', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');

    notifier.openTheEntry(p02);
    await waitFor('P02 to resume', () => read().sessionId == 'sessao-da-p02');

    expect(
      read().leftEntry,
      isNull,
      reason: 'a P02 retomada ainda guardava a volta para a P01',
    );
  });

  test('a passage the room refuses keeps the way back to the passage the team '
      'left', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    final p01 = read().sessionId;
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    harness.room.passagesThatCannotOpen = {'P02'};

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to refuse P02',
      () =>
          harness.room.calls.where((call) => call == 'createSession').length ==
          2,
    );
    await waitFor('the Choice to come back', () => read().entriesOpen);

    expect(read().station, isA<Menu>());
    expect(
      read().theWayBackIsLive,
      isTrue,
      reason: 'a recusa da P02 apagava o caminho de volta para a P01',
    );
    expect(read().leftEntry?.session, p01);
  });

  test('a passage that cannot open goes back to the Choice saying nothing and '
      'showing no sign', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    int said() =>
        harness.voice.played.length +
        harness.voice.assets.length +
        harness.voice.fixedLines.length;
    await notifier.abrirEscolha();
    await waitFor('the Choice to list its entries', () => read().entriesOpen);
    final p02 = read().naRoda!.firstWhere((entry) => entry.pericope == 'P02');
    final before = said();
    final asked = harness.room.calls.length;
    harness.room.reachable = false;

    notifier.openTheEntry(p02);
    await waitFor(
      'the room to be asked',
      () => harness.room.calls.skip(asked).contains('createSession'),
    );
    await waitFor(
      'the Choice to come back',
      () => read().station is Menu && read().entriesOpen,
    );
    await settle();
    await settle();

    expect(read().station, isA<Menu>());
    expect(said(), before, reason: 'a volta à Escolha falava uma linha');
    expect(read().needsPerson, isFalse);
    expect(read().voice, VoiceState.invite);
  });

  test('a Panorama the room cannot be reached for leaves the team on the '
      'Choice with the way back live, saying nothing, and its pill asks '
      'again', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    int said() =>
        harness.voice.played.length +
        harness.voice.assets.length +
        harness.voice.fixedLines.length;
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );
    final panorama = read().naRoda!.firstWhere((entry) => entry.isPanorama);
    final before = harness.room.calls.length;
    final quiet = said();
    harness.room.reachable = false;

    notifier.openTheEntry(panorama);
    await waitFor(
      'the room to be asked',
      () => harness.room.calls.skip(before).contains('createSession'),
    );
    await settle();
    await settle();

    expect(
      read().station,
      isA<Menu>(),
      reason: 'a equipe ficava no Panorama sem sessão',
    );
    expect(read().entriesOpen, isTrue);
    expect(read().theWayBackIsLive, isTrue);
    expect(read().leftEntry?.pericope, 'P01');
    expect(harness.room.calls.skip(before), ['createSession']);
    expect(said(), quiet);
    expect(read().needsPerson, isFalse);

    harness.room.reachable = true;
    notifier.openTheEntry(panorama);
    await waitFor(
      'the Panorama to open',
      () => read().panoramaSessionId != null,
    );

    expect(read().station, isA<Panorama>());
  });

  test('a Panorama opened from its pill no longer holds the way back to the '
      'passage left before it', () async {
    final harness = SalaHarness()..room.passages = _theBook;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'P01 to open',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await waitFor(
      'the way back to P01 to be live',
      () => read().entriesOpen && read().theWayBackIsLive,
    );

    notifier.openTheEntry(read().naRoda!.firstWhere((e) => e.isPanorama));
    await waitFor(
      'the Panorama to open',
      () => read().panoramaSessionId != null,
    );

    expect(
      read().leftEntry,
      isNull,
      reason: 'o Panorama aberto ainda guardava a volta para a P01',
    );
  });

  test(
    'a Wheel that holds only the Panorama calls nobody and stays on the Choice',
    () async {
      final harness = SalaHarness()..room.passages = const [_panorama];
      final container = harness.container();
      addTearDown(container.dispose);

      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await settle();

      final state = container.read(salaSessionProvider);
      expect(state.needsPerson, isFalse);
      expect(state.naRoda, [_panorama]);
    },
  );
}
