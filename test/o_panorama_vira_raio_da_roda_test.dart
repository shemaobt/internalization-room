import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}
