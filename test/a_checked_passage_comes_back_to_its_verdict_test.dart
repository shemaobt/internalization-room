import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

const _gravacao = 'gravacao-1';
const _umaParte = Duration(seconds: 30);

Future<Sala> _conferidaEDeixadaPelaVolta() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room.retroSoFar = BackTranslationProgress(
    segments: [...it.harness.room.segments],
    checked: true,
  );
  await pedirOVeredito(it);
  expect(it.estado.btPhase, BtPhase.conferida);
  it.sala.leaveTheBackTranslation();
  await waitFor(
    'a equipe voltar à casa da gravação',
    () => it.estado.stage == SalaStage.ensaio,
  );
  return it;
}

Future<void> _traduzirAGravacao(Sala it) async {
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () => it.estado.stage == SalaStage.retro && !it.estado.awaitingTheGuide,
  );
  await settle();
}

void main() {
  test(
    'coming back from the home to a passage checked clean lands on its verdict, '
    'with nothing played and nothing said',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = const [];
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      await _traduzirAGravacao(it);

      expect(
        it.estado.btPhase,
        BtPhase.conferida,
        reason: 'a volta da casa esquecia a conferência e reabria a tradução',
      );
      expect(it.estado.btVeredito, isTrue);
      expect(it.harness.playback.played.skip(tocadas), isEmpty);
      expect(it.harness.voice.fixedLines.skip(falas), isEmpty);
    },
  );

  test(
    'a room that says nothing of what was heard still brings the checked '
    'passage back to its verdict, not to the untold ground playing',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = null;
      final tocadas = it.harness.playback.played.length;

      await _traduzirAGravacao(it);

      expect(it.estado.btPhase, BtPhase.conferida);
      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason: 'a última parte voltava a tocar sobre a conferência limpa',
      );
    },
  );

  test('an approved passage opened from the home lands on its verdict with its '
      'badge and its frases, never the parts played again', () async {
    final harness = SalaHarness()
      ..playback.length = _umaParte
      ..playback.measured = _umaParte;
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 12000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: _gravacao,
            startsMs: 12000,
            endsMs: 30000,
          ),
        ],
        checked: true,
      )
      ..takes.add(
        const TakeView(
          takeId: _gravacao,
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      )
      ..takeAudio[_gravacao] = Uint8List.fromList([7, 7, 7, 7])
      ..openedSessions.add('sessao-antiga')
      ..listeningUnheardTakeIds = const [];
    harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState estado() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a passagem aprovada pousar na conversa',
      () => estado().stage == SalaStage.conversa && !estado().awaitingTheGuide,
    );
    sala.openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir com a parte da sala',
      () => estado().stage == SalaStage.ensaio && estado().partes.isNotEmpty,
    );
    await settle();
    final tocadas = harness.playback.played.length;
    final falas = harness.voice.fixedLines.length;

    sala.startRetro();
    await waitFor(
      'a tradução abrir',
      () => estado().stage == SalaStage.retro && !estado().awaitingTheGuide,
    );
    await settle();

    expect(
      estado().btPhase,
      BtPhase.conferida,
      reason: 'a passagem aprovada recomeçava a tradução do zero',
    );
    expect(estado().approvedDraftDrawn?.version, 1);
    expect(estado().btTrechos, hasLength(2));
    expect(
      harness.playback.played.skip(tocadas),
      isEmpty,
      reason: 'as partes tocavam de novo antes do selo',
    );
    expect(harness.voice.fixedLines.skip(falas), isEmpty);
  });
}
