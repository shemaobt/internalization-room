import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePanorama, settle;

/// Stages the room is meant never to leave.
///
/// Declared, and empty: no stage of this room is a place the team is meant to stay in.
/// The set exists so that a stage which is terminal on purpose can be told apart from one
/// that is terminal because nobody noticed — without it the property cannot say which it
/// is looking at.
const _terminal = <SalaStage>{};

const _noGestureReaches = <SalaStage>{};

/// What the team can do to leave each stage, named rather than read off the code: a table
/// derived from the implementation proves only that the code equals itself.
///
/// Each row carries the gesture as well as its name, so the two cannot drift. Mapping to a
/// name that something else matched would let a row name a gesture that matcher did not
/// know: the gesture would quietly do nothing, and the walk would report the station as
/// having no way out — blaming the room for a hole in this table.
final _wayOut =
    <
      SalaStage,
      ({
        String name,
        Future<void> Function(SalaSessionNotifier, SalaSessionState) take,
      })
    >{
      SalaStage.panorama: (
        name: 'leaveThePassage',
        take: (n, _) async => n.leaveThePassage(),
      ),
      SalaStage.escolha: (
        name: 'openTheEntry',
        take: (n, state) async => n.openTheEntry(state.naRoda!.first),
      ),
      SalaStage.conversa: (
        name: 'goEnsaio',
        take: (n, _) async => n.goEnsaio(),
      ),
      SalaStage.ensaio: (
        name: 'startRetro',
        take: (n, _) async {
          n.gravarACena(1);
          n.gravarACena(1);
          await settle();
          n.takeKeep();
          await untilTheAdvanceDiscLights(n);
          n.startRetro();
        },
      ),
      SalaStage.retro: (
        name: 'leaveThePassage',
        take: (n, _) async => n.leaveThePassage(),
      ),
      SalaStage.cena: (
        name: 'leaveTheSceneRehearsal',
        take: (n, _) async => n.leaveTheSceneRehearsal(),
      ),
      SalaStage.checagem: (
        name: 'leaveTheExternalCheck',
        take: (n, _) async => n.leaveTheExternalCheck(),
      ),
    };

const _gravacao = 'gravacao-1';

const _conferida = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
    ),
  ],
  checked: true,
);

/// Put the room in [stage], through the gestures that really reach it.
Future<void> _standIn(
  SalaStage stage,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  if (stage == SalaStage.panorama) {
    harness.room.passages = [
      const Passagem(
        pericope: 'panorama',
        audioUrl: '/voice/panorama',
        kind: PassagemKind.panorama,
      ),
      ...harness.room.passages,
    ];
    await enterThePanorama(notifier, read);
    await waitFor('o panorama abrir', () => read().stage == SalaStage.panorama);
    return;
  }

  await notifier.abrirEscolha();
  await waitFor('a roda abrir', () => read().naRoda != null);
  if (stage == SalaStage.escolha) {
    await waitFor('a Escolha abrir as entradas', () => read().entriesOpen);
    return;
  }

  if (stage == SalaStage.checagem) {
    harness.playback
      ..length = const Duration(seconds: 12)
      ..measured = const Duration(seconds: 12);
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..retroSoFar = _conferida
      ..takes.add(
        const TakeView(
          takeId: _gravacao,
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      )
      ..takeAudio[_gravacao] = Uint8List.fromList([7, 7, 7, 7]);
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor('a conversa pousar', () => read().canHearAgain);
    notifier.openTheEnsaioFinal();
    await waitFor(
      'o rascunho aprovado aparecer na casa da gravação',
      () => read().approvedOnTheHome != null,
    );
    notifier.abrirAChecagemExterna();
    await waitFor(
      'a checagem externa abrir',
      () => read().stage == SalaStage.checagem,
    );
    return;
  }

  await notifier.goConversa(book: 'Ruth', pericope: 'P01');
  await waitFor('a conversa abrir', () => read().sessionId != null);
  if (stage == SalaStage.conversa) return;

  if (stage == SalaStage.cena) {
    await waitFor(
      'a conversa repousar',
      () => read().voice == VoiceState.invite && !read().awaitingTheGuide,
    );
    notifier.openTheSceneRehearsal();
    await waitFor(
      'o ensaio da cena abrir',
      () => read().stage == SalaStage.cena,
    );
    return;
  }

  notifier.goEnsaio();
  await settle();
  if (stage == SalaStage.ensaio) return;

  notifier.gravarACena(1);
  notifier.gravarACena(1);
  await settle();
  notifier.takeKeep();
  await untilTheAdvanceDiscLights(notifier);
  notifier.startRetro();
  await settle();
}

void main() {
  test('every stage of the room has a way out the team can take', () async {
    expect(
      _wayOut.keys.toSet().union(_terminal).union(_noGestureReaches),
      SalaStage.values.toSet(),
      reason:
          'a tabela é sobre o enum inteiro: uma etapa nova entra aqui sem '
          'ninguém precisar lembrar de escrever um caso para ela',
    );

    for (final stage in SalaStage.values) {
      if (_terminal.contains(stage) || _noGestureReaches.contains(stage)) {
        continue;
      }
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await _standIn(stage, harness, container);
      expect(
        container.read(salaSessionProvider).stage,
        stage,
        reason: 'o caso precisa começar onde diz que começa',
      );

      await _wayOut[stage]!.take(notifier, container.read(salaSessionProvider));

      // Espera com prazo e falha alta: uma saída que nunca chega é uma parede, e
      // tem de ser dita como tal em vez de estourar em outro lugar.
      await waitFor(
        'a equipe sair de $stage por ${_wayOut[stage]!.name} — uma etapa sem saída é '
        'uma sala que só se deixa matando o app',
        () => container.read(salaSessionProvider).stage != stage,
        limit: const Duration(seconds: 5),
      );
      expect(container.read(salaSessionProvider).stage, isNot(stage));
    }
  });
}
