import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show enterThePassage, settle, theChoiceOffersAPassage;

const _panorama = Passagem(
  pericope: 'OV-Ruth',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
  book: 'Ruth',
);
const _p01 = Passagem(pericope: 'P01', audioUrl: '/voice/p01', book: 'Ruth');

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
    final state = SalaSessionState(
      machine: Machine(station: Station.stored(SalaStage.escolha)),
      naRoda: [_panorama],
    );

    expect(
      state.livroInteiroFeito,
      isTrue,
      reason:
          'o panorama não é uma passagem — todas as passagens feitas é '
          'livro terminado, esteja ou não o raio de ouvir o livro de novo '
          'ainda na roda',
    );
  });

  test('a wheel with the panorama and a passage left is not finished', () {
    final state = SalaSessionState(
      machine: Machine(station: Station.stored(SalaStage.escolha)),
      naRoda: [_panorama, _p01],
    );

    expect(state.livroInteiroFeito, isFalse);
  });

  test('a wheel with only the panorama left calls nobody', () async {
    final harness = SalaHarness()..room.passages = const [_panorama];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.needsPerson,
      isFalse,
      reason: 'a roda que só oferece o panorama não é um dos seis casos',
    );
    expect(
      state.naRoda,
      [_panorama],
      reason:
          'o raio de ouvir o livro de novo fica na roda mesmo com o '
          'livro inteiro terminado',
    );
  });

  test('the panorama alongside real passages calls nobody', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isFalse);
    expect(state.naRoda, [_panorama, _p01]);
    expect(
      state.naRoda!.first,
      _panorama,
      reason:
          'o panorama vem em primeiro na roda, à frente de toda '
          'passagem — é a porta de entrada da roda',
    );
  });

  test(
    'entering the panorama spoke opens a panorama session, not a passage',
    () async {
      final harness = SalaHarness()..room.passages = const [_panorama, _p01];
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await theChoiceOffersAPassage(container);

      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await settle();

      expect(
        harness.room.pericopesAsked,
        ['OV-Ruth'],
        reason:
            'o panorama é pedido pelo id que a roda pôs nele, nunca pelo alias',
      );
      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.panorama,
        reason:
            'entrar no panorama nunca cai numa passagem — a equipe '
            'fica no panorama depois de ele falar',
      );
      expect(
        harness.room.sessionsSpokenTo,
        hasLength(1),
        reason: 'a sessão de panorama que a sala abriu é a que a voz fala',
      );
      expect(container.read(salaSessionProvider).voice, VoiceState.invite);
      expect(
        harness.voice.played,
        [turnoUrl],
        reason:
            'a Escolha não diz nada ao abrir; entrar no panorama é o turno '
            'da sala, e só ele é falado',
      );
    },
  );

  test('a panorama spoke refused is asked again under a fresh turn id', () async {
    final harness = SalaHarness()
      ..room.passages = const [_panorama, _p01]
      ..room.failHeldTurnWith = const Refused('BAD_REQUEST');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await theChoiceOffersAPassage(container);

    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();
    await waitFor(
      'o círculo descansar no convite',
      () =>
          !container.read(salaSessionProvider).needsPerson &&
          container.read(salaSessionProvider).voice == VoiceState.invite,
    );
    notifier.leaveThePassage();
    await theChoiceOffersAPassage(container);
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();

    expect(
      harness.room.turnIdsAsked,
      hasLength(2),
      reason:
          'a primeira falha ao entrar já é a chamada de turno que para a sala; '
          'o toque que segue o atendimento precisa dos dois pedidos de turno '
          'para haver o que comparar',
    );
    expect(harness.room.turnIdsAsked[0], isNotNull);
    expect(
      harness.room.turnIdsAsked[1],
      isNot(harness.room.turnIdsAsked[0]),
      reason:
          'a soltura nunca reenvia com a mesma chave o pedido que parou a '
          'sala: o servidor devolveria a mesma resposta lembrada',
    );
  });

  test('entering the panorama writes no resume point', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await theChoiceOffersAPassage(container);

    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();

    expect(
      harness.emAberto.rows.containsKey('Ruth/panorama/pt'),
      isFalse,
      reason:
          'nada no panorama é um lugar para retomar; é a própria '
          'roda o lugar onde a equipe volta a ele',
    );
  });

  test('nothing ends the panorama on a timer or a turn count', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await theChoiceOffersAPassage(container);

    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle(const Duration(seconds: 5));

    final state = container.read(salaSessionProvider);
    expect(
      state.stage,
      SalaStage.panorama,
      reason:
          'o panorama não tem fim previsto e nada aqui agenda um — '
          'esperar não move a equipe para lugar nenhum',
    );
    expect(state.voice, VoiceState.invite);
    expect(state.needsPerson, isFalse);
  });

  test('returning to the same Panorama in the same language reuses its '
      'session', () async {
    final harness = SalaHarness()..room.passages = const [_panorama, _p01];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await theChoiceOffersAPassage(container);

    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();
    notifier.leaveThePassage();
    await theChoiceOffersAPassage(container);
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.last);
    await settle();
    notifier.leaveThePassage();
    await theChoiceOffersAPassage(container);
    notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
    await settle();

    expect(harness.room.pericopesAsked, ['OV-Ruth', 'P01']);
    final [panorama, passage] = harness.room.sessionIds;
    expect(
      harness.room.sessionsSpokenTo,
      [panorama, passage],
      reason:
          'voltar ao Panorama não cunha uma segunda sessão de panorama, '
          'e a sessão que a sala diz aberta não pede a abertura de novo',
    );
  });

  test(
    'the team leaves the panorama for the wheel and enters a passage',
    () async {
      final harness = SalaHarness()..room.passages = const [_panorama, _p01];
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await theChoiceOffersAPassage(container);
      notifier.openTheEntry(container.read(salaSessionProvider).naRoda!.first);
      await settle();
      final panoramaSession = harness.room.sessionIds.single;

      notifier.leaveThePassage();
      await enterThePassage(
        notifier,
        () => container.read(salaSessionProvider),
        'P01',
      );
      await waitFor(
        'a passagem abrir',
        () => container.read(salaSessionProvider).sessionId != null,
      );

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'sair do panorama é exatamente como sair de qualquer '
            'outra sessão: virar a roda para uma passagem e entrar nela',
      );
      expect(
        harness.room.metBefore.last,
        isTrue,
        reason:
            'a sessão da passagem carrega a sessão de panorama que a '
            'precedeu, do mesmo jeito que sempre carregou',
      );
      expect(harness.room.sessionIds, hasLength(2));
      expect(
        harness.room.sessionIds.last,
        isNot(panoramaSession),
        reason:
            'a passagem ganha sua própria sessão — nunca reaproveita '
            'a do panorama',
      );
    },
  );
}
