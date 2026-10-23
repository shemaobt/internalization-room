import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePanorama, enterThePassage, settle;

const _livroComPanorama = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
];

const _maisDoQueUmaEspera = Duration(milliseconds: 800);

class _Fila extends QueueThatFlushesLate {
  _Fila({required super.room, super.home, required super.recordings});

  final List<String> discarded = [];
  Completer<void>? _naming;
  bool _nameAsked = false;

  bool get nameAsked => _naming != null && _nameAsked;

  void holdTheNextName() => _naming = Completer<void>();

  void giveTheName() => _naming!.complete();

  @override
  Future<void> discardTheSession(String sessionId) {
    discarded.add(sessionId);
    return super.discardTheSession(sessionId);
  }

  @override
  Future<String?> takeIdOf(String row) async {
    if (_naming case final held? when !_nameAsked) {
      _nameAsked = true;
      await held.future;
    }
    return super.takeIdOf(row);
  }
}

class _Sala extends FakeRoom {
  Completer<RoomFailure>? _read;
  Completer<RoomFailure>? _takes;
  Completer<RoomFailure>? _chunk;

  bool get readHeld => _read != null && _readAsked;
  bool get takesHeld => _takes != null && _takesAsked;
  bool get chunkHeld => _chunk != null && _chunkAsked;
  bool _readAsked = false;
  bool _takesAsked = false;
  bool _chunkAsked = false;

  void holdTheSessionRead() => _read = Completer<RoomFailure>();

  void holdTheRecordingsRead() => _takes = Completer<RoomFailure>();

  void holdTheStretch() => _chunk = Completer<RoomFailure>();

  void answerTheRead(RoomFailure failure) => _read!.complete(failure);

  void answerTheTakes(RoomFailure failure) => _takes!.complete(failure);

  void answerTheChunk(RoomFailure failure) => _chunk!.complete(failure);

  @override
  Future<RoomAnswer<SessionSnapshot>> fetchState(String sessionId) async {
    if (_read case final held? when !_readAsked) {
      _readAsked = true;
      return held.future;
    }
    return super.fetchState(sessionId);
  }

  @override
  Future<RoomAnswer<List<TakeView>>> takesOf(String sessionId) async {
    if (_takes case final held? when !_takesAsked) {
      _takesAsked = true;
      return held.future;
    }
    return super.takesOf(sessionId);
  }

  final List<({String session, String kind})> takesSent = [];

  @override
  Future<RoomAnswer<String>> sendTake(
    String sessionId,
    File audio, {
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    DateTime? recordedAt,
    int? durationMs,
    String? sha256,
    String? origin,
    bool reopensTheApprovedDraft = false,
    String? overTake,
  }) {
    takesSent.add((session: sessionId, kind: kind));
    return super.sendTake(
      sessionId,
      audio,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      recordedAt: recordedAt,
      durationMs: durationMs,
      sha256: sha256,
      origin: origin,
      reopensTheApprovedDraft: reopensTheApprovedDraft,
      overTake: overTake,
    );
  }

  @override
  Future<RoomAnswer<BackTranslationChunk>> sendChunk(
    String sessionId,
    File audio, {
    required String takeId,
    required Duration from,
    required Duration to,
    required String idempotencyKey,
  }) async {
    if (_chunk case final held? when !_chunkAsked) {
      _chunkAsked = true;
      return held.future;
    }
    return super.sendChunk(
      sessionId,
      audio,
      takeId: takeId,
      from: from,
      to: to,
      idempotencyKey: idempotencyKey,
    );
  }
}

class _Caso {
  _Caso(this.harness) : container = harness.container() {
    addTearDown(container.dispose);
  }

  final SalaHarness harness;
  final ProviderContainer container;

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  _Sala get room => harness.room as _Sala;

  _Fila get fila => harness.takes as _Fila;
}

_Caso _umaSala({TakeUploadQueue Function(FakeRoom, Directory)? fila}) => _Caso(
  SalaHarness(
    room: _Sala(),
    takesOverride: (room, home, recordings) =>
        fila?.call(room, home) ??
        _Fila(room: room, home: () async => home, recordings: recordings),
  ),
);

Future<void> _gravarUmaParte(_Caso caso) async {
  caso.sala
    ..goEnsaio()
    ..ensaioTap()
    ..ensaioTap();
  await waitFor(
    'a tomada ser oferecida',
    () => caso.estado.ensaio == EnsaioStatus.recorded,
  );
}

Future<_Caso> _naConversa() async {
  final caso = _umaSala();
  await caso.sala.goConversa(book: 'Ruth');
  await settle();
  return caso;
}

Future<_Caso> _criandoDepoisDeUmPanoramaQueSeFoi() async {
  final caso = _umaSala();
  caso.room.passages = _livroComPanorama;
  await enterThePanorama(caso.sala, () => caso.estado);
  await settle();
  await caso.sala.abrirEscolha();
  await settle();
  caso.room
    ..forgetTheSession(caso.room.sessionIds.first)
    ..holdNextCreate();
  await enterThePassage(caso.sala, () => caso.estado, 'P01');
  await waitFor('a criação sair', () => caso.room.createHeld);
  return caso;
}

int _criacoes(_Caso caso) =>
    caso.room.calls.where((call) => call == 'createSession').length;

Future<_Caso> _naTraducaoRetomada({required List<SegmentView> told}) async {
  final caso = _umaSala();
  final casa = Directory.systemTemp.createTempSync('sala-vida');
  addTearDown(() => casa.deleteSync(recursive: true));
  caso.harness.playback
    ..length = const Duration(seconds: 30)
    ..measured = const Duration(seconds: 30);
  caso.room.retroSoFar = BackTranslationProgress(segments: told);
  caso.harness.emAberto.rows['Ruth/P01/$testLanguage'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File('${casa.path}/p1.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  await caso.sala.abrirEscolha();
  caso.room.holdTheRecordingsRead();
  await caso.sala.goConversa(book: 'Ruth', pericope: 'P01');
  return caso;
}

Future<_Caso> _abrindoOMicrofoneParaUmTrecho() async {
  final caso = _umaSala();
  await caso.sala.abrirEscolha();
  await settle();
  caso.sala.openTheEntry(caso.estado.naRoda!.first);
  await waitFor('a passagem abrir', () => caso.estado.sessionId != null);
  await settle();
  await _gravarUmaParte(caso);
  caso.sala.takeKeep();
  await waitFor(
    'a parte ganhar nome',
    () => caso.estado.keptTakes.every((take) => take.takeId != null),
  );
  caso.sala.startRetro();
  await waitFor('o clipe rodar', () => caso.estado.btClipRodando);
  caso.harness.playback.at = const Duration(seconds: 2);
  caso.sala
    ..retroTap()
    ..retroTap();
  await waitFor(
    'o microfone abrir para o trecho',
    () => caso.estado.btPhase == BtPhase.capturing,
  );
  return caso;
}

Future<_Caso> _criandoUmaPassagem() async {
  final caso = _umaSala();
  caso.room.passages = _livroComPanorama;
  await caso.sala.abrirEscolha();
  await settle();
  caso.room.holdNextCreate();
  await enterThePassage(caso.sala, () => caso.estado, 'P01');
  await waitFor('a criação sair', () => caso.room.createHeld);
  return caso;
}

class _Linha {
  const _Linha(
    this.name, {
    required this.arrange,
    required this.release,
    this.inTheNextLife,
  });

  final String name;
  final Future<_Caso> Function() arrange;
  final Future<void> Function(_Caso caso)? inTheNextLife;

  /// Lets the held answer land, and hands back what the row checks once it has.
  final Future<FutureOr<void> Function()> Function(_Caso caso) release;
}

final _linhas = [
  _Linha(
    '1: SessionGone of the Panorama\'s session lands after the room was '
    'rebuilt: the new Life is untouched',
    arrange: _criandoDepoisDeUmPanoramaQueSeFoi,
    release: (caso) async {
      final panorama = caso.room.sessionIds.first;
      final apagadas = caso.harness.recorder.deleted.length;
      final criacoes = _criacoes(caso);
      caso.room.finishHeldCreate();
      return () {
        expect(caso.fila.discarded, isNot(contains(panorama)));
        expect(caso.harness.recorder.deleted, hasLength(apagadas));
        expect(_criacoes(caso), criacoes);
      };
    },
  ),
  _Linha(
    '3: a count of the Outbox that answers after the rebuild changes nothing',
    arrange: () async {
      late QueueHeldOnTheTally fila;
      final caso = _umaSala(
        fila: (room, home) => fila = QueueHeldOnTheTally(
          room: room,
          home: () async => home,
          recordings: () => FakeRecorder(sounds: []),
        ),
      );
      caso.container.read(salaSessionProvider);
      unawaited(caso.sala.refreshUnsent());
      await fila.asking.future;
      return caso;
    },
    release: (caso) async {
      (caso.harness.takes as QueueHeldOnTheTally).answer.complete();
      return () {};
    },
  ),
  _Linha(
    '4: a count started by a keep after its flush, once the room was '
    'rebuilt, changes nothing',
    arrange: () async {
      final caso = await _naConversa();
      await _gravarUmaParte(caso);
      caso.fila.flushesAfter = _maisDoQueUmaEspera;
      caso.sala.takeKeep();
      await waitFor('a Fila enviar a tomada', () => caso.fila.flushing > 0);
      return caso;
    },
    release: (caso) async {
      await waitFor(
        'a tomada chegar à sala',
        () => caso.room.takesKept.contains('ensaio/parte-1'),
      );
      await waitFor('a Fila terminar', () => caso.fila.flushing == 0);
      return () {};
    },
  ),
  _Linha(
    '5: the names the room gives a take after the rebuild are not written '
    'into the new room',
    arrange: () async {
      final caso = await _naConversa();
      await _gravarUmaParte(caso);
      caso.fila.holdTheNextName();
      caso.sala.takeKeep();
      await waitFor('a sala dar o nome', () => caso.fila.nameAsked);
      return caso;
    },
    release: (caso) async {
      caso.fila.giveTheName();
      return () {};
    },
  ),
  _Linha(
    '6: «enviar agora» whose flush answers after the rebuild changes nothing',
    arrange: () async {
      final caso = await _naConversa();
      caso.room.unreachableTake = 'ensaio/parte-1';
      await _gravarUmaParte(caso);
      caso.sala.takeKeep();
      await waitFor(
        'a parte ficar por enviar',
        () => caso.estado.unsentParts[1]?.failed ?? false,
      );
      caso.room.unreachableTake = null;
      caso.fila.flushesAfter = _maisDoQueUmaEspera;
      caso.sala.enviarACena(1);
      await waitFor('a Fila enviar de novo', () => caso.fila.flushing > 0);
      return caso;
    },
    release: (caso) async {
      await waitFor(
        'a tomada chegar à sala',
        () => caso.room.takesKept.contains('ensaio/parte-1'),
      );
      await waitFor('a Fila terminar', () => caso.fila.flushing == 0);
      return () {};
    },
  ),
  _Linha(
    '7: a read of the session that answers gone after the rebuild forgets '
    'nothing',
    arrange: () async {
      final caso = await _naConversa();
      caso.room.holdTheSessionRead();
      caso.sala.conversaTap();
      await settle();
      caso.sala.conversaTap();
      await waitFor('a leitura da sessão sair', () => caso.room.readHeld);
      return caso;
    },
    release: (caso) async {
      final sessao = caso.room.sessionIds.last;
      caso.room.answerTheRead(const SessionGone());
      return () {
        expect(caso.fila.discarded, isNot(contains(sessao)));
      };
    },
  ),
  _Linha(
    '8: a read of the session that fails on the network after the rebuild '
    'raises nothing',
    arrange: () async {
      final caso = await _naConversa();
      caso.room.holdTheSessionRead();
      caso.sala.conversaTap();
      await settle();
      caso.sala.conversaTap();
      await waitFor('a leitura da sessão sair', () => caso.room.readHeld);
      return caso;
    },
    release: (caso) async {
      caso.room.answerTheRead(const NetworkFailed('sem rede'));
      return () {
        expect(caso.estado.needsPerson, isFalse);
      };
    },
  ),
  _Linha(
    '9: the Back-translation\'s read of the recordings that fails after the '
    'rebuild raises nothing',
    arrange: () async {
      final caso = await _naTraducaoRetomada(
        told: const [
          SegmentView(
            segmentId: 'trecho-de-fora',
            takeId: 'gravacao-de-fora',
            startsMs: 0,
            endsMs: 6000,
          ),
        ],
      );
      await waitFor('a leitura das gravações sair', () => caso.room.takesHeld);
      return caso;
    },
    release: (caso) async {
      caso.room.answerTheTakes(const NetworkFailed('sem rede'));
      return () {
        expect(caso.estado.needsPerson, isFalse);
      };
    },
  ),
  _Linha(
    '10: a Back-translation recording whose send fails after the rebuild is '
    'not queued under the next room\'s session',
    arrange: () async {
      final caso = await _abrindoOMicrofoneParaUmTrecho();
      caso.room.holdTheStretch();
      caso.sala.retroTap();
      await waitFor('o trecho sair', () => caso.room.chunkHeld);
      return caso;
    },
    inTheNextLife: (caso) async {
      final daOutraSala = caso.room.sessionIds.first;
      await enterThePassage(caso.sala, () => caso.estado, 'P02');
      await waitFor(
        'a próxima sala abrir outra passagem',
        () => ![null, daOutraSala].contains(caso.estado.sessionId),
      );
      await settle();
    },
    release: (caso) async {
      final daProximaSala = caso.estado.sessionId!;
      caso.room.answerTheChunk(const NetworkFailed('sem rede'));
      return () async {
        final naFila = await caso.harness.takes.pending();
        expect([
          for (final row in naFila)
            if (row.kind == 'retro' && row.sessionId == daProximaSala) row,
        ], isEmpty);
        expect(
          caso.room.takesSent,
          isNot(contains((session: daProximaSala, kind: 'retro'))),
        );
      };
    },
  ),
  _Linha(
    '9b: the Back-translation\'s read of the recordings that answers gone '
    'after the rebuild forgets nothing',
    arrange: () async {
      final caso = await _naTraducaoRetomada(
        told: const [
          SegmentView(
            segmentId: 'trecho-de-fora',
            takeId: 'gravacao-de-fora',
            startsMs: 0,
            endsMs: 6000,
          ),
        ],
      );
      await waitFor('a leitura das gravações sair', () => caso.room.takesHeld);
      return caso;
    },
    release: (caso) async {
      caso.room.answerTheTakes(const SessionGone());
      return () {
        expect(caso.fila.discarded, isNot(contains('sessao-antiga')));
      };
    },
  ),
  _Linha(
    '9c: the Back-translation\'s read of the stretches after a verdict that '
    'fails after the rebuild raises nothing',
    arrange: () async {
      final caso = await _abrindoOMicrofoneParaUmTrecho();
      caso.sala.retroTap();
      await waitFor('o trecho chegar à sala', () => caso.room.chunksSent == 1);
      await waitFor(
        'a sala voltar a tocar',
        () => caso.estado.btPhase == BtPhase.playing,
      );
      caso.harness.playback.finishPlayback();
      await settle();
      caso.room.holdTheSessionRead();
      unawaited(caso.sala.finishBackTranslation());
      await waitFor('a releitura dos trechos sair', () => caso.room.readHeld);
      return caso;
    },
    release: (caso) async {
      caso.room.answerTheRead(const NetworkFailed('sem rede'));
      return () {
        expect(caso.estado.needsPerson, isFalse);
      };
    },
  ),
  _Linha(
    '10b: a stretch whose capture closes after the rebuild is not sent',
    arrange: () async {
      final caso = await _abrindoOMicrofoneParaUmTrecho();
      caso.harness.recorder.holdNextStop();
      caso.sala.retroTap();
      await settle();
      return caso;
    },
    release: (caso) async {
      final enviados = caso.room.chunksSent;
      caso.harness.recorder.finishStop();
      return () {
        expect(caso.room.chunksSent, enviados);
      };
    },
  ),
  _Linha(
    '12: the end of a gesture of an ended Life does nothing in the next one',
    arrange: _criandoUmaPassagem,
    release: (caso) async {
      caso.room.finishHeldCreate();
      return () {};
    },
  ),
  _Linha(
    '11: a measurement that answers after the rebuild changes nothing',
    arrange: () async {
      final caso = _umaSala();
      await caso.sala.abrirEscolha();
      await settle();
      caso.sala.openTheEntry(caso.estado.naRoda!.first);
      await waitFor('a passagem abrir', () => caso.estado.sessionId != null);
      await settle();
      await caso.harness.takes.enqueue(
        caso.harness.recorder.aFile('de-outra-visita'),
        sessionId: caso.estado.sessionId!,
        kind: 'ensaio',
        scope: KeptScope.parte(1),
        passNumber: 1,
      );
      caso.harness.playback.holdNextMeasurement();
      unawaited(caso.sala.refreshUnsent());
      await waitFor(
        'a parte de outra visita ser medida',
        () => caso.harness.playback.measurements.isNotEmpty,
      );
      return caso;
    },
    release: (caso) async {
      caso.harness.playback.finishHeldMeasurement();
      return () {};
    },
  ),
];

void main() {
  for (final linha in _linhas) {
    test(linha.name, () async {
      final caso = await linha.arrange();

      caso.container.invalidate(salaSessionProvider);
      caso.container.read(salaSessionProvider);
      await linha.inTheNextLife?.call(caso);
      await settle();
      var writes = 0;
      caso.container.listen(salaSessionProvider, (_, _) => writes++);
      final check = await linha.release(caso);
      await settle(const Duration(milliseconds: 300));

      expect(
        writes,
        0,
        reason: 'a resposta era da sala de antes do desvínculo',
      );
      await check();
    });
  }

  test('a count the next room made while a keep was in the air is right once '
      'the keep lands', () async {
    final caso = await _naConversa();
    await _gravarUmaParte(caso);
    caso.fila.flushesAfter = _maisDoQueUmaEspera;
    caso.sala.takeKeep();
    await waitFor('a Fila enviar a tomada', () => caso.fila.flushing > 0);

    caso.container.invalidate(salaSessionProvider);
    caso.container.read(salaSessionProvider);
    await caso.sala.refreshUnsent();
    expect(caso.estado.machine.somethingPending, isTrue);

    await waitFor('a Fila terminar', () => caso.fila.flushing == 0);
    await waitFor(
      'a próxima sala contar a tomada como enviada',
      () => !caso.estado.machine.somethingPending,
    );
  });

  test('2: a team that leaves while the creation after a gone Panorama is in '
      'the air still lets that session go', () async {
    final caso = await _criandoDepoisDeUmPanoramaQueSeFoi();
    final panorama = caso.room.sessionIds.first;

    caso.sala.leaveThePassage();
    caso.room.finishHeldCreate();
    await waitFor(
      'a sessão do Panorama sair da Fila',
      () => caso.fila.discarded.contains(panorama),
    );
    await settle(const Duration(milliseconds: 300));

    expect(caso.fila.discarded.where((s) => s == panorama), hasLength(1));
  });
}
