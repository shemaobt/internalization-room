import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

/// Sends `sendChunk` through the real [RoomRepository] — the actual production decode, not
/// a hand-picked failure — so a test using this room stays sensitive to a regression in
/// whether `sendChunk`'s own 404 is the session gone. Everything else this room is asked
/// for still comes from [FakeRoom].
class _RealSendChunkRoom extends FakeRoom {
  int? sendChunkStatus;

  @override
  Future<RoomAnswer<BackTranslationChunk>> sendChunk(
    String sessionId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
  }) {
    final status = sendChunkStatus;
    if (status == null) {
      return super.sendChunk(
        sessionId,
        audio,
        takeId: takeId,
        from: from,
        to: to,
      );
    }
    final real = RoomRepository(
      client: MockClient(
        (_) async => http.Response(
          status == 422
              ? jsonEncode({
                  'detail':
                      'Internalization room rehearsal take $takeId not found',
                  'code': 'UNKNOWN_REFERENCE',
                })
              : '{}',
          status,
        ),
      ),
      deviceId: () async => 'aparelho-1',
    );
    return real.sendChunk(sessionId, audio, takeId: takeId, from: from, to: to);
  }
}

const _sessao = 'sessao-antiga';
const _parte = Duration(seconds: 10);
const _inicioDoTrecho = Duration(seconds: 4);

class _Retomada {
  final SalaHarness harness;
  final ProviderContainer container;
  late final String linhaAntes;

  _Retomada(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  String get linhaAgora =>
      jsonEncode(harness.emAberto.rows['Ruth/P01']?.toJson());
}

/// A passage picked back up in the back-translation on a tablet that holds none of its
/// three rehearsal parts: parts 1 and 2 are told, and part 3 is told up to four seconds,
/// so the stretch the team tells next starts there.
Future<_Retomada> _retomadaNaRetro(SalaHarness harness) async {
  final casa = Directory.systemTemp.createTempSync('sala-trecho-recusado');
  addTearDown(() => casa.deleteSync(recursive: true));
  final linha = ResumePoint(
    sessionId: _sessao,
    stage: SalaStage.retro,
    takes: [
      for (var n = 1; n <= 3; n++)
        KeptTake(
          scopeId: KeptScope.parte(n),
          path: '${casa.path}/p$n.m4a',
          takeId: 'gravacao-$n',
          pass: 1,
        ),
    ],
  );
  harness.emAberto.rows['Ruth/P01'] = linha;
  harness.playback.measured = _parte;
  harness.room
    ..retroSoFar = BackTranslationProgress(
      segments: [
        for (var n = 1; n <= 2; n++)
          SegmentView(
            segmentId: 'trecho-$n',
            takeId: 'gravacao-$n',
            startsMs: 0,
            endsMs: _parte.inMilliseconds,
          ),
        SegmentView(
          segmentId: 'trecho-3',
          takeId: 'gravacao-3',
          startsMs: 0,
          endsMs: _inicioDoTrecho.inMilliseconds,
        ),
      ],
    )
    ..takes.addAll([
      for (var n = 1; n <= 3; n++)
        TakeView(
          takeId: 'gravacao-$n',
          kind: 'ensaio',
          scope: KeptScope.parte(n),
          ordinal: n,
        ),
    ]);

  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Retomada(harness, container);
  await it.sala.abrirEscolha();
  await settle();
  unawaited(it.sala.goConversa(pericope: 'P01'));
  await _ateAParteTresNoAr(it);
  it.linhaAntes = it.linhaAgora;
  return it;
}

Future<void> _ateAParteTresNoAr(_Retomada it) async {
  await waitFor(
    'a retro voltar com a parte 3 no ar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.played.isNotEmpty,
  );
}

Future<void> _contarUmTrechoRecusado(_Retomada it) async {
  final recusadosAntes = it.estado.btChunkFailures.length;
  it.harness.playback.at = const Duration(seconds: 7);
  it.sala.cortarTrecho();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  await confirmarATraducao(it.container);
  await waitFor(
    'a sala recusar o trecho',
    () => it.estado.btChunkFailures.length > recusadosAntes,
  );
  await settle();
}

Future<void> _confirmarDeNovoARecusada(_Retomada it) async {
  final recusadosAntes = it.estado.btChunkFailures.length;
  await it.sala.confirmarTraducao();
  await waitFor(
    'a sala recusar o trecho de novo',
    () => it.estado.btChunkFailures.length > recusadosAntes,
  );
  await settle();
}

void _aSessaoContinuaAMesma(_Retomada it) {
  expect(
    it.estado.sessionId,
    _sessao,
    reason: 'um trecho recusado não é a sessão sumida',
  );
  expect(
    it.linhaAgora,
    it.linhaAntes,
    reason:
        'a linha de retomada de uma sessão viva, com quatro partes e um trecho, '
        'era esquecida, e a próxima entrada nascia vazia',
  );
  expect(it.estado.stage, SalaStage.retro, reason: 'a equipe fica onde estava');
  expect(
    it.harness.room.calls,
    isNot(contains('createSession')),
    reason: 'nenhuma sessão nova nasce por cima da que a sala ainda guarda',
  );
}

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  test(
    'a stretch the room refuses leaves the session, the resume row and the station as they were',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.room.failChunkWith = const Refused('BAD_REQUEST', 'HTTP 400');

      await _contarUmTrechoRecusado(it);

      _aSessaoContinuaAMesma(it);
      expect(it.estado.needsPerson, isFalse);
    },
  );

  test(
    'ENG-1133: a chunk answered 404 by the real door leaves the passage',
    () async {
      final room = _RealSendChunkRoom();
      final harness = SalaHarness(room: room);
      final it = await _retomadaNaRetro(harness);
      room.sendChunkStatus = 404;

      it.harness.playback.at = const Duration(seconds: 7);
      it.sala.cortarTrecho();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await confirmarATraducao(it.container);
      await waitFor(
        'a sala deixar a passagem',
        () => it.estado.stage == SalaStage.escolha,
      );

      expect(
        it.estado.sessionId,
        isNull,
        reason: 'a sessão sumiu, como em toda outra porta que pergunta por ela',
      );
      expect(
        await harness.emAberto.of('Ruth', 'P01'),
        isNull,
        reason: 'a sessão sumida não deixa onde retomar',
      );
      expect(
        it.estado.needsPerson,
        isFalse,
        reason: 'a sessão sumida deixa a passagem; não risca rumo a uma pessoa',
      );
    },
  );

  test(
    'ENG-1133: a chunk answered 422 by the real door strikes, and the session stays',
    () async {
      final room = _RealSendChunkRoom();
      final harness = SalaHarness(room: room);
      final it = await _retomadaNaRetro(harness);
      room.sendChunkStatus = 422;

      it.harness.playback.at = const Duration(seconds: 7);
      it.sala.cortarTrecho();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      final recusadosAntes = it.estado.btChunkFailures.length;
      await confirmarATraducao(it.container);
      await waitFor(
        'a sala recusar o trecho',
        () => it.estado.btChunkFailures.length > recusadosAntes,
      );
      await settle();

      _aSessaoContinuaAMesma(it);
      expect(
        it.estado.needsPerson,
        isFalse,
        reason: 'uma só recusa ainda está abaixo das três da escada',
      );
    },
  );

  test(
    'the third refused stretch calls a person, and the session is still the same',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.room.failChunkWith = const Refused('BAD_REQUEST', 'HTTP 422');

      await _contarUmTrechoRecusado(it);
      expect(
        it.estado.needsPerson,
        isFalse,
        reason: 'a recusa 1 ainda está abaixo das três da escada',
      );
      await _confirmarDeNovoARecusada(it);
      expect(
        it.estado.needsPerson,
        isFalse,
        reason: 'a recusa 2 ainda está abaixo das três da escada',
      );
      await _confirmarDeNovoARecusada(it);

      expect(
        it.estado.needsPerson,
        isTrue,
        reason:
            'a terceira recusa seguida chama uma pessoa, como toda chamada recusada',
      );
      _aSessaoContinuaAMesma(it);
    },
  );

  test(
    'after a refused stretch the passage opened again resumes in the back-translation of the same session with its parts',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.room.failChunkWith = const Refused('BAD_REQUEST', 'HTTP 400');
      await _contarUmTrechoRecusado(it);

      it.sala.leaveThePassage();
      await settle();
      harness.room.failChunkWith = null;
      harness.playback.played.clear();
      unawaited(it.sala.goConversa(pericope: 'P01'));
      await _ateAParteTresNoAr(it);

      expect(
        it.estado.stage,
        SalaStage.retro,
        reason: 'a retomada volta à retro, nunca ao ensaio',
      );
      expect(it.estado.sessionId, _sessao);
      expect(
        [for (final parte in it.estado.partes) parte.takeId],
        ['gravacao-1', 'gravacao-2', 'gravacao-3'],
        reason: 'as partes do ensaio voltam com a sessão',
      );
      expect(harness.room.calls, isNot(contains('createSession')));
    },
  );

  test(
    'a cut with the playhead still on the stretch start opens no microphone and sends nothing',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.playback.at = _inicioDoTrecho;
      expect(
        harness.playback.sounding,
        isTrue,
        reason: 'o clipe toca antes do corte',
      );

      it.sala.cortarTrecho();
      it.sala.retroTap();
      await settle();
      expect(
        harness.playback.sounding,
        isFalse,
        reason: 'o corte recusado segura o clipe',
      );
      expect(
        it.estado.btPhase,
        isNot(BtPhase.capturing),
        reason: 'um trecho que termina onde começa não tem nada a contar',
      );
      expect(harness.room.chunksSent, 0);
      expect(
        harness.room.chunkSpans,
        isEmpty,
        reason: 'o trecho vazio ia à sala e voltava recusado com 400',
      );

      it.sala.ouvirGravacao();
      await settle();
      expect(
        harness.playback.sounding,
        isTrue,
        reason:
            'o corte recusado segura o clipe; um toque em ouvir tem de trazê-lo '
            'de volta, não pedir dois',
      );
    },
  );

  test(
    'a cut behind the stretch start records nothing, and one step past it tells the stretch',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);

      harness.playback.at = _inicioDoTrecho - const Duration(milliseconds: 1);
      it.sala.cortarTrecho();
      it.sala.retroTap();
      await settle();
      expect(it.estado.btPhase, isNot(BtPhase.capturing));
      expect(harness.room.chunkSpans, isEmpty);
      it.sala.ouvirGravacao();
      await settle();
      expect(harness.playback.sounding, isTrue);

      await _ateAParteTresNoAr(it);
      harness.playback.at = _inicioDoTrecho + const Duration(milliseconds: 1);
      it.sala.cortarTrecho();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await confirmarATraducao(it.container);
      await waitFor(
        'o trecho chegar à sala',
        () => harness.room.chunkSpans.isNotEmpty,
      );

      expect(harness.room.chunkSpans, ['4000-4001']);
    },
  );
}
