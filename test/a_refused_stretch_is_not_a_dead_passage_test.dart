import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

const _sessao = 'sessao-antiga';
const _parte = Duration(seconds: 10);
const _inicioDoTrecho = Duration(seconds: 4);

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) =>
    Future<void>.delayed(delay);

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
  await waitFor(
    'o microfone abrir',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'a sala recusar o trecho',
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
  test(
    'a stretch the room refuses leaves the session, the resume row and the station as they were',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.room.failChunkWith = const RoomBroke('HTTP 400');

      await _contarUmTrechoRecusado(it);

      _aSessaoContinuaAMesma(it);
      expect(it.estado.needsPerson, isFalse);
    },
  );

  test(
    'the third refused stretch calls a person, and the session is still the same',
    () async {
      final harness = SalaHarness();
      final it = await _retomadaNaRetro(harness);
      harness.room.failChunkWith = const RoomBroke('HTTP 404');

      for (var recusa = 1; recusa <= 2; recusa++) {
        await _contarUmTrechoRecusado(it);
        expect(
          it.estado.needsPerson,
          isFalse,
          reason: 'a recusa $recusa ainda está abaixo das três da escada',
        );
      }
      await _contarUmTrechoRecusado(it);

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
      harness.room.failChunkWith = const RoomBroke('HTTP 400');
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

      it.sala.retroTap();
      await settle();

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
      await settle();
      expect(it.estado.btPhase, isNot(BtPhase.capturing));
      it.sala.retroTap();
      await settle();
      expect(harness.room.chunkSpans, isEmpty);
      it.sala.ouvirGravacao();
      await settle();
      expect(harness.playback.sounding, isTrue);

      await _ateAParteTresNoAr(it);
      harness.playback.at = _inicioDoTrecho + const Duration(milliseconds: 1);
      it.sala.cortarTrecho();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      it.sala.retroTap();
      await waitFor(
        'o trecho chegar à sala',
        () => harness.room.chunkSpans.isNotEmpty,
      );

      expect(harness.room.chunkSpans, ['4000-4001']);
    },
  );
}
