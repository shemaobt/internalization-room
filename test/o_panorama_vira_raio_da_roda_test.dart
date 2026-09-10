import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _p01 = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

/// The wheel's answer for a book, when its panorama has a line to say: the panorama comes
/// first and every entry, passage or panorama, says its own kind.
void main() {
  test('a panorama entry parses its own kind', () {
    final panorama = Passagem.fromJson(const {
      'pericope': 'panorama',
      'kind': 'panorama',
      'audio_url': '/voice/panorama',
      'beads': 0,
      'absence_index': -1,
    });

    expect(panorama.kind, PassagemKind.panorama);
    expect(panorama.isPanorama, isTrue);
  });

  test('a passage entry parses its own kind too', () {
    final passagem = Passagem.fromJson(const {
      'pericope': 'P01',
      'kind': 'passage',
      'audio_url': '/voice/p01',
    });

    expect(passagem.kind, PassagemKind.passage);
    expect(passagem.isPanorama, isFalse);
  });

  test('an entry with no kind at all is read as a passage', () {
    // The wire always sends `kind` today, but every fixture and every fake room built
    // before this ticket constructs a `Passagem` with none — a server that has not
    // deployed the field yet must still read as the wheel always has.
    final passagem = Passagem.fromJson(const {
      'pericope': 'P01',
      'audio_url': '/voice/p01',
    });

    expect(passagem.kind, PassagemKind.passage);
  });

  test('the constructor itself defaults to a passage', () {
    const passagem = Passagem(pericope: 'P01', audioUrl: '/voice/p01');

    expect(passagem.kind, PassagemKind.passage);
    expect(passagem.isPanorama, isFalse);
  });

  test('a wheel with only the panorama left is still a finished book', () {
    const state = SalaSessionState(
      stage: SalaStage.escolha,
      naRoda: [_panorama],
    );

    expect(
      state.livroInteiroFeito,
      isTrue,
      reason: 'the panorama is not a passage — every real passage done is a '
          'finished book, whether or not the spoke to hear the whole book '
          'again is still sitting on the wheel',
    );
  });

  test('a wheel with the panorama and a passage left is not finished', () {
    const state = SalaSessionState(
      stage: SalaStage.escolha,
      naRoda: [_panorama, _p01],
    );

    expect(state.livroInteiroFeito, isFalse);
  });

  test('a wheel with only the panorama left still calls a person', () async {
    final harness = SalaHarness()..room.passages = const [_panorama];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.needsPerson,
      isTrue,
      reason: 'abrirEscolha counted the panorama as a passage still to '
          'work, the same bug livroInteiroFeito carried',
    );
    expect(state.naRoda, [_panorama],
        reason: 'the spoke to hear the book again stays on the wheel even '
            'once the book itself is done');
  });

  test('the panorama alongside real passages calls nobody', () async {
    final harness = SalaHarness()
      ..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isFalse);
    expect(state.naRoda, [_panorama, _p01]);
    expect(state.oferecida, _panorama,
        reason: 'the panorama is first on the wheel, ahead of every '
            "passage — it's the wheel's front door");
  });

  test('entering the panorama spoke opens a panorama session, not a passage',
      () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.entrarNaOferecida();
    await settle();

    expect(harness.room.pericopesAsked, contains('panorama'),
        reason: 'the panorama is asked for by the id the wheel gave it, '
            'exactly as any other spoke on it is');
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason: 'entering the panorama never falls into a passage — the '
          'team is still standing at the wheel once it has spoken',
    );
    expect(harness.room.sessionsSpokenTo, hasLength(1),
        reason: 'the panorama session the room opened is the one the '
            'voice speaks into');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
    expect(
      harness.voice.played,
      [_panorama.audioUrl, turnoUrl],
      reason: 'the ruler names the panorama first, aiming at it; entering '
          "it is the room's own turn, spoken second",
    );
  });

  test('entering the panorama writes no ledger row and no resume point',
      () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.entrarNaOferecida();
    await settle();

    expect(harness.finished.done, isNot(contains('Ruth/panorama')),
        reason: 'the panorama is not a passage — it never leaves the '
            "wheel, so it must never mark itself as one of the book's "
            'finished passages');
    expect(harness.emAberto.rows.containsKey('Ruth/panorama'), isFalse,
        reason: 'nothing about the panorama is a resume point to come '
            'back to; the wheel itself is where the team returns to it');
  });

  test('nothing ends the panorama on a timer or a turn count', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.entrarNaOferecida();
    await settle(const Duration(seconds: 5));

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.escolha,
        reason: 'the panorama has no foreseen end and nothing here '
            'schedules one — waiting does not move the team anywhere');
    expect(state.voice, VoiceState.invite);
    expect(state.needsPerson, isFalse);
  });

  test('the team leaves the panorama by turning the wheel to a passage',
      () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    final panoramaSession = harness.room.sessionIds.single;

    notifier.apontarPassagem(1);
    notifier.dizerAPassagem();
    await settle();
    notifier.entrarNaOferecida();
    await settle();

    expect(container.read(salaSessionProvider).stage, SalaStage.conversa,
        reason: 'leaving the panorama is exactly like leaving any other '
            'session: turning the wheel to a passage and entering it');
    expect(harness.room.metBefore.last, isTrue,
        reason: 'the passage session carries the panorama session it '
            'followed, the same way it always has');
    expect(harness.room.sessionIds, hasLength(2));
    expect(harness.room.sessionIds.last, isNot(panoramaSession),
        reason: 'the passage gets its own session — it never reuses the '
            "panorama's");
  });
}
