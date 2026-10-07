import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePassage, settle;

/// The passage the team taps on the Choice.
const _passagem = 'P02';

/// The session the row names: the one the team worked in and left.
const _daLinha = 'sessao-antiga';

const _parte = Duration(seconds: 10);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);
const _p01 = Passagem(pericope: 'P01', audioUrl: '/voice/p01');
const _p02 = Passagem(pericope: _passagem, audioUrl: '/voice/p02');

/// What the room hands back of the telling-back the team had already done.
const _contado = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-1',
      startsMs: 0,
      endsMs: 10000,
    ),
  ],
);

/// The row this tablet left on [_passagem], with three kept parts.
///
/// [noTablet] writes each part's file, the way a tablet that still holds its rehearsal
/// does; without it the row names files a restore left behind, and the room's own parts
/// are what the resume has to fetch.
void _aLinhaDeixada(
  SalaHarness harness, {
  required SalaStage parouEm,
  bool noTablet = true,
  String? lingua,
}) {
  final casa = Directory.systemTemp.createTempSync('sala-porta-da-sala');
  addTearDown(() => casa.deleteSync(recursive: true));
  final takes = <KeptTake>[];
  for (var n = 1; n <= 3; n++) {
    final caminho = '${casa.path}/p$n.m4a';
    if (noTablet) {
      File(caminho).writeAsBytesSync([1, 2, 3]);
      harness.playback.lengths[caminho] = _parte;
    }
    takes.add(
      KeptTake(
        scopeId: KeptScope.parte(n),
        path: caminho,
        takeId: 'gravacao-$n',
      ),
    );
  }
  harness.emAberto.rows['Ruth/$_passagem'] = ResumePoint(
    sessionId: _daLinha,
    stage: parouEm,
    takes: parouEm == SalaStage.conversa ? const [] : takes,
    language: lingua,
  );
  harness.room.retroSoFar = _contado;
  harness.playback.measured = _parte;
}

/// The team taps [_passagem] on the Choice.
Future<ProviderContainer> _aEquipeTocaAPassagem(SalaHarness harness) async {
  harness.room.passages = const [_panorama, _p01, _p02];
  final container = harness.container();
  addTearDown(container.dispose);
  await enterThePassage(
    container.read(salaSessionProvider.notifier),
    () => container.read(salaSessionProvider),
    _passagem,
  );
  await settle();
  return container;
}

/// The session the room minted for the tap, which no row names.
String _aMintada(SalaHarness harness) {
  expect(
    harness.room.sessionIds,
    hasLength(1),
    reason:
        'o toque pede uma sessão só; é essa que as asserções abaixo nomeiam',
  );
  return harness.room.sessionIds.first;
}

void main() {
  test('a passagem tocada na roda respeita a sua linha', () async {
    final harness = SalaHarness();
    _aLinhaDeixada(harness, parouEm: SalaStage.retro);

    final container = await _aEquipeTocaAPassagem(harness);

    await waitFor(
      'a equipe pousar na tradução que deixou',
      () => container.read(salaSessionProvider).stage == SalaStage.retro,
    );
    final estado = container.read(salaSessionProvider);
    expect(
      estado.sessionId,
      _daLinha,
      reason: 'a porta é outra e a linha é a mesma',
    );
    expect(estado.keptTakes, hasLength(3));
    expect(harness.emAberto.rows['Ruth/$_passagem']!.sessionId, _daLinha);
  });

  test('uma linha parada na conversa guarda a sua sessão', () async {
    final harness = SalaHarness();
    _aLinhaDeixada(harness, parouEm: SalaStage.conversa);

    final container = await _aEquipeTocaAPassagem(harness);

    await waitFor(
      'a sala abrir a conversa da sessão lembrada',
      () => harness.room.sessionsSpokenTo.isNotEmpty,
    );
    expect(
      harness.room.sessionsSpokenTo,
      [_daLinha],
      reason:
          'a estação em que a linha parou é detalhe; a linha é o fato, '
          'e a conversa dela continua na sessão que a equipe deixou',
    );
    expect(container.read(salaSessionProvider).sessionId, _daLinha);
    expect(harness.emAberto.rows['Ruth/$_passagem']!.sessionId, _daLinha);
  });

  test(
    'uma linha de outra língua não vence a sessão que a sala abriu',
    () async {
      final harness = SalaHarness();
      _aLinhaDeixada(harness, parouEm: SalaStage.retro, lingua: 'xx');

      final container = await _aEquipeTocaAPassagem(harness);

      await waitFor(
        'a equipe chegar à conversa da passagem que a sala devolveu',
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await waitFor(
        'o lugar da equipe ser anotado',
        () => harness.emAberto.rows['Ruth/$_passagem']!.sessionId != _daLinha,
      );
      expect(
        container.read(salaSessionProvider).sessionId,
        _aMintada(harness),
        reason:
            'uma linha escrita noutra língua não é desta corrida (ADR '
            '0031): a sessão que a sala abriu é a que a equipe entra',
      );
      expect(
        harness.emAberto.rows['Ruth/$_passagem']!.sessionId,
        _aMintada(harness),
      );
    },
  );

  test(
    'as partes que faltam no tablet são buscadas para a sessão da linha',
    () async {
      final harness = SalaHarness();
      _aLinhaDeixada(harness, parouEm: SalaStage.retro, noTablet: false);
      harness.room.takes.addAll([
        for (var n = 1; n <= 3; n++)
          TakeView(
            takeId: 'gravacao-$n',
            kind: 'ensaio',
            scope: KeptScope.parte(n),
            ordinal: n,
          ),
      ]);

      final container = await _aEquipeTocaAPassagem(harness);

      await waitFor(
        'as partes voltarem da sala',
        () => container.read(salaSessionProvider).partes.length == 3,
      );
      expect(
        harness.room.clipsFetched,
        [
          for (var n = 1; n <= 3; n++)
            RoomRepository.takeAudioUrl(_daLinha, 'gravacao-$n'),
        ],
        reason:
            'o ensaio que a sala guarda está sob a sessão da linha (ADR '
            '0023); a sessão que ela acabou de abrir não guarda parte nenhuma',
      );
      expect(container.read(salaSessionProvider).sessionId, _daLinha);
      expect(harness.emAberto.rows['Ruth/$_passagem']!.sessionId, _daLinha);
    },
  );
}
