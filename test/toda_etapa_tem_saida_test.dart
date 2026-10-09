import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/main.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
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
      ({String name, Future<void> Function(SalaSessionNotifier) take})
    >{
      SalaStage.panorama: (
        name: 'leaveThePassage',
        take: (n) async => n.leaveThePassage(),
      ),
      SalaStage.escolha: (
        name: 'entrarNaOferecida',
        take: (n) async => n.entrarNaOferecida(),
      ),
      SalaStage.conversa: (name: 'goEnsaio', take: (n) async => n.goEnsaio()),
      SalaStage.ensaio: (name: 'startRetro', take: (n) async => n.startRetro()),
      SalaStage.retro: (
        name: 'leaveThePassage',
        take: (n) async => n.leaveThePassage(),
      ),
      SalaStage.fim: (name: 'beginAgain', take: (n) async => n.beginAgain()),
    };

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
    // A roda diz o nome da passagem oferecida ao abrir, e o gesto de entrar só
    // responde depois disso. Esperar aqui é ficar de pé onde a equipe fica: a
    // saída existe, ela apenas não é instantânea.
    await waitFor(
      'a roda terminar de dizer a passagem oferecida',
      () => read().voice == VoiceState.invite,
    );
    return;
  }

  await notifier.goConversa(pericope: 'P01');
  await waitFor('a conversa abrir', () => read().sessionId != null);
  if (stage == SalaStage.conversa) return;

  notifier.goEnsaio();
  await settle();
  if (stage == SalaStage.ensaio) return;

  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  notifier.startRetro();
  await settle();
  if (stage == SalaStage.retro) return;

  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await waitFor(
    'a sala conferir a passagem',
    () => read().btPhase == BtPhase.conferida,
  );
  await notifier.aprovarRascunhoFinal();
  await waitFor(
    'a passagem fechar',
    () => read().stage == SalaStage.fim,
    limit: const Duration(seconds: 5),
  );
}

void main() {
  test('every stage of the room has a way out the team can take', () async {
    expect(
      _wayOut.keys.toSet().union(_terminal),
      SalaStage.values.toSet(),
      reason:
          'a tabela é sobre o enum inteiro: uma etapa nova entra aqui sem '
          'ninguém precisar lembrar de escrever um caso para ela',
    );

    for (final stage in SalaStage.values) {
      if (_terminal.contains(stage)) continue;
      // A long linger, so no timer can be what moves the room: what is measured here is
      // the gesture the table names, and nothing else.
      final harness = SalaHarness(fimLinger: const Duration(minutes: 5));
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await _standIn(stage, harness, container);
      expect(
        container.read(salaSessionProvider).stage,
        stage,
        reason: 'o caso precisa começar onde diz que começa',
      );

      await _wayOut[stage]!.take(notifier);

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

  test('the fecho leaves the team somewhere they can act', () async {
    final harness = SalaHarness(fimLinger: const Duration(minutes: 5));
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await _standIn(SalaStage.fim, harness, container);

    notifier.beginAgain();
    await waitFor(
      'a roda voltar',
      () => container.read(salaSessionProvider).stage == SalaStage.escolha,
    );

    // E o gesto que a roda oferece responde: a saída leva a um lugar vivo, não a
    // outra parede.
    await waitFor(
      'a roda ficar pronta para o toque',
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );
    notifier.entrarNaOferecida();
    await waitFor(
      'a passagem abrir a partir da roda',
      () => container.read(salaSessionProvider).stage == SalaStage.conversa,
    );
  });

  test('the fecho also comes back on its own, without a touch', () async {
    final harness = SalaHarness(fimLinger: const Duration(milliseconds: 150));
    final container = harness.container();
    addTearDown(container.dispose);

    await _standIn(SalaStage.fim, harness, container);

    await waitFor(
      'a sala voltar sozinha para a roda dentro do tempo do fecho',
      () => container.read(salaSessionProvider).stage == SalaStage.escolha,
      limit: const Duration(seconds: 5),
    );
  });

  testWidgets('the fecho screen answers the touch it offers', (tester) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
    final harness = SalaHarness(
      filaEmMemoria: true,
      fimLinger: const Duration(minutes: 5),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.takeKeep();
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.aprovarRascunhoFinal();
    await tester.pump(const Duration(seconds: 3));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.fim,
      reason: 'o caso precisa chegar ao fecho para medir o toque dele',
    );

    // O que os outros casos não provam: que o gesto existe na árvore desenhada,
    // e não só no notifier.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Começar de novo',
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.escolha,
      reason:
          'a saída do fecho tem de responder ao dedo na tela, não só à '
          'chamada do método',
    );
  });

  testWidgets('the fecho offers to begin again in english to an english room', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
    final harness = SalaHarness(
      filaEmMemoria: true,
      fimLinger: const Duration(minutes: 5),
      lingua: 'en',
    );
    final container = harness.container();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SalaApp()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.goConversa(pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 300));
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 300));
    notifier.takeKeep();
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 300));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.finishBackTranslation();
    await tester.pump(const Duration(milliseconds: 300));
    await notifier.aprovarRascunhoFinal();
    await tester.pump(const Duration(seconds: 3));

    expect(container.read(salaSessionProvider).stage, SalaStage.fim);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Begin again',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Começar de novo',
      ),
      findsNothing,
      reason: 'o fecho oferecia "Começar de novo" a um aparelho em inglês',
    );

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Begin again',
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(salaSessionProvider).stage, SalaStage.escolha);
  });
}
