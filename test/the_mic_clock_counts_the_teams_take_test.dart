import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/panorama_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show enterThePanorama;

final _azul = const Color(0xFF89AAA3).withValues(alpha: 0.75);
final _terracotta = const Color(0xFFBE4A01).withValues(alpha: 0.95);

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

class _Room {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;
  final Type view;

  _Room(this.tester, this.harness, this.container, this.view);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  Future<void> beat([int ms = 100]) => tester.pump(Duration(milliseconds: ms));

  Future<void> until(String what, bool Function() ready) async {
    await waitFor(what, ready, step: beat);
    await beat();
  }

  Future<void> waits(Duration span) async {
    for (var gone = Duration.zero; gone < span; gone += _second) {
      await tester.pump(_second);
    }
  }

  static const _second = Duration(seconds: 1);

  Finder get circle => find.descendant(
    of: find.byType(view),
    matching: find.byType(FacilitatorCircle),
  );

  bool get anyClock =>
      find.textContaining(RegExp(r'^\d+:\d\d$')).evaluate().isNotEmpty;

  bool get circleListens =>
      tester.widget<FacilitatorCircle>(circle).voice == VoiceState.listening;

  Text? clock(String digits) => switch (find.text(digits).evaluate()) {
    final found when found.isEmpty => null,
    final found => found.single.widget as Text,
  };

  void tap() => view == PanoramaView ? sala.panoramaTap() : sala.conversaTap();

  Future<void> theTeamOpensItsTake() async {
    tap();
    await until(
      'o microfone abrir',
      () => estado.voice == VoiceState.listening,
    );
  }
}

Future<_Room> _inConversa(WidgetTester tester) async {
  final harness = SalaHarness();
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container, ConversaView);
  unawaited(room.sala.goConversa(book: 'Ruth'));
  await room.until(
    'a conversa abrir no convite',
    () =>
        room.estado.sessionId != null &&
        room.estado.stage == SalaStage.conversa &&
        room.estado.voice == VoiceState.invite,
  );
  await room.beat(300);
  return room;
}

Future<_Room> _inThePanorama(WidgetTester tester) async {
  final harness = SalaHarness();
  harness.room.passages = [_panorama, ...harness.room.passages];
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final room = _Room(tester, harness, container, PanoramaView);
  await enterThePanorama(room.sala, () => room.estado, step: room.beat);
  await room.until('o panorama ser dito', () => room.estado.panoramaSaid);
  await room.until(
    'a sala voltar ao convite',
    () => room.estado.voice == VoiceState.invite,
  );
  await room.beat(300);
  return room;
}

Future<void> _theClockCountsTheTake(_Room room) async {
  final tester = room.tester;
  expect(room.clock('0:00'), isNull, reason: 'o relógio já estava lá');

  await room.theTeamOpensItsTake();

  final atStart = room.clock('0:00');
  expect(atStart, isNotNull, reason: 'o microfone abriu sem relógio');
  expect(atStart!.style?.color, _azul);
  expect(
    tester.getRect(find.text('0:00')).bottom,
    lessThan(tester.getRect(room.circle).top),
    reason: 'o relógio não estava acima do círculo',
  );

  await room.waits(const Duration(seconds: 1));
  expect(room.clock('0:01'), isNotNull, reason: 'o relógio não andou');

  await room.waits(const Duration(seconds: 64));
  expect(room.clock('1:05'), isNotNull, reason: 'o relógio não contava');
}

Future<void> _theClockWaitsForTheRecorder(_Room room) async {
  room.harness.recorder.holdNextStart();
  await room.theTeamOpensItsTake();
  await room.waits(const Duration(seconds: 3));
  expect(
    room.anyClock,
    isFalse,
    reason: 'o relógio contava antes de o gravador dizer que começou',
  );

  room.harness.recorder.finishStart();
  await room.beat();
  expect(
    room.clock('0:00'),
    isNotNull,
    reason: 'o gravador começou e o relógio não marcava 0:00',
  );

  await room.waits(const Duration(seconds: 2));
  expect(
    room.clock('0:02'),
    isNotNull,
    reason: 'o relógio contava desde o toque, não desde o gravador',
  );
}

void main() {
  testWidgets(
    'a take on the conversation shows 0:00 above the circle and counts up '
    'each second, in a quiet blue-green',
    (tester) async => _theClockCountsTheTake(await _inConversa(tester)),
  );

  testWidgets(
    'a take on the Panorama shows the same clock, not a bare circle',
    (tester) async => _theClockCountsTheTake(await _inThePanorama(tester)),
  );

  testWidgets(
    'a recorder that starts late shows no clock until it answers, and the '
    'clock counts from its answer, not from the tap',
    (tester) async => _theClockWaitsForTheRecorder(await _inConversa(tester)),
  );

  testWidgets(
    'on the Panorama too the clock waits for the recorder, not for the tap',
    (tester) async =>
        _theClockWaitsForTheRecorder(await _inThePanorama(tester)),
  );

  testWidgets(
    'the next take whose recorder is slow shows no clock, never the time of '
    'the take before',
    (tester) async {
      final room = await _inConversa(tester);
      await room.theTeamOpensItsTake();
      await room.waits(const Duration(seconds: 3));
      room.sala.conversaTap();
      await room.until(
        'a sala voltar ao convite',
        () => room.estado.voice == VoiceState.invite,
      );

      room.harness.recorder.holdNextStart();
      await room.theTeamOpensItsTake();
      await room.waits(const Duration(seconds: 1));
      expect(
        room.anyClock,
        isFalse,
        reason: 'a vez seguinte mostrava o tempo da anterior',
      );

      room.harness.recorder.finishStart();
      await room.beat();
      expect(room.clock('0:00'), isNotNull);
    },
  );

  testWidgets(
    'a take that cuts her reply waits for the recorder before its clock '
    'counts, the same as a take from rest',
    (tester) async {
      final room = await _inConversa(tester);
      room.harness.room.holdNextTurn();
      await room.theTeamOpensItsTake();
      room.sala.conversaTap();
      await room.until('a vez sair', () => room.harness.room.turnsSent > 0);
      room.harness.voice.holdNextLine();
      room.harness.room.finishHeldTurn();
      await room.until(
        'a resposta falar',
        () => room.estado.voice == VoiceState.speaking,
      );

      room.harness.recorder.holdNextStart();
      room.sala.conversaTap();
      await room.until(
        'o corte abrir o microfone',
        () => room.estado.voice == VoiceState.listening,
      );
      await room.waits(const Duration(seconds: 3));
      expect(
        room.anyClock,
        isFalse,
        reason: 'o corte contava antes de o gravador dizer que começou',
      );

      room.harness.recorder.finishStart();
      await room.beat();
      await room.waits(const Duration(seconds: 2));
      expect(
        room.clock('0:02'),
        isNotNull,
        reason: 'o corte contava desde o toque, não desde o gravador',
      );
      room.harness.voice.finishHeldLine();
    },
  );

  for (final (how, breaks) in [
    ('fails to start', (FakeRecorder recorder) => recorder.startThrows = true),
    ('is refused', (FakeRecorder recorder) => recorder.permitted = false),
  ]) {
    testWidgets(
      'a recorder that $how shows no clock, not even while the tablet waits '
      'for its answer',
      (tester) async {
        final room = await _inConversa(tester);
        room.harness.recorder.holdNextStart();
        await room.theTeamOpensItsTake();
        breaks(room.harness.recorder);

        await room.waits(const Duration(seconds: 2));
        expect(
          room.anyClock,
          isFalse,
          reason: 'o relógio contava com o gravador ainda sem responder',
        );

        room.harness.recorder.finishStart();
        await room.beat(300);
        expect(room.estado.channel, isNot(isA<Microphone>()));
        expect(
          room.anyClock,
          isFalse,
          reason: 'o gravador não começou e o relógio apareceu',
        );
        closeTheRoom(room.container);
      },
    );
  }

  for (final (screen, enter) in [
    ('conversation', _inConversa),
    ('Panorama', _inThePanorama),
  ]) {
    testWidgets(
      'a recorder that starts late leaves the circle on the $screen at rest '
      'until it answers, then it listens',
      (tester) async {
        final room = await enter(tester);
        room.harness.recorder.holdNextStart();
        await room.theTeamOpensItsTake();
        await room.waits(const Duration(seconds: 2));
        expect(
          room.circleListens,
          isFalse,
          reason: 'o círculo ouvia antes de o gravador dizer que começou',
        );

        room.harness.recorder.finishStart();
        await room.beat();
        expect(
          room.circleListens,
          isTrue,
          reason: 'o gravador começou e o círculo não ouvia',
        );
      },
    );

    for (final (how, breaks) in [
      (
        'fails to start',
        (FakeRecorder recorder) => recorder.startThrows = true,
      ),
      ('is refused', (FakeRecorder recorder) => recorder.permitted = false),
    ]) {
      testWidgets(
        'a recorder that $how never turns the circle on the $screen to '
        'listening, not even while the tablet waits for its answer',
        (tester) async {
          final room = await enter(tester);
          room.harness.recorder.holdNextStart();
          await room.theTeamOpensItsTake();
          breaks(room.harness.recorder);

          await room.waits(const Duration(seconds: 2));
          expect(
            room.circleListens,
            isFalse,
            reason: 'o círculo ouvia com o gravador ainda sem responder',
          );

          room.harness.recorder.finishStart();
          await room.beat(300);
          expect(
            room.circleListens,
            isFalse,
            reason: 'o gravador não começou e o círculo ouvia',
          );
          closeTheRoom(room.container);
        },
      );
    }

    testWidgets(
      'a microphone another app takes leaves the circle on the $screen at '
      'rest with no clock, and both come back with the microphone',
      (tester) async {
        final room = await enter(tester);
        await room.theTeamOpensItsTake();
        await room.waits(const Duration(seconds: 2));
        expect(room.circleListens, isTrue);
        expect(room.clock('0:02'), isNotNull);

        room.harness.recorder.takeTheMicrophone();
        await room.beat();
        expect(
          room.circleListens,
          isFalse,
          reason: 'outro app tomou o microfone e o círculo seguia ouvindo',
        );
        expect(
          room.anyClock,
          isFalse,
          reason: 'outro app tomou o microfone e o relógio seguia contando',
        );

        await room.waits(const Duration(seconds: 3));
        room.harness.recorder.giveTheMicrophoneBack();
        await room.beat();
        expect(
          room.circleListens,
          isTrue,
          reason: 'o microfone voltou e o círculo não ouvia',
        );
        expect(
          room.clock('0:05'),
          isNotNull,
          reason: 'o relógio não contava desde que o gravador começou',
        );
      },
    );

    testWidgets(
      'a stop the recorder fails leaves the circle on the $screen at rest '
      'with no clock, not listening over a take that is over',
      (tester) async {
        final room = await enter(tester);
        await room.theTeamOpensItsTake();
        await room.waits(const Duration(seconds: 2));
        expect(room.circleListens, isTrue);

        room.harness.recorder.stopThrows = true;
        room.tap();
        await room.beat(300);
        expect(room.estado.channel, isA<Microphone>());
        expect(
          room.circleListens,
          isFalse,
          reason: 'o gravador falhou ao parar e o círculo seguia ouvindo',
        );
        expect(
          room.anyClock,
          isFalse,
          reason: 'o gravador falhou ao parar e o relógio seguia contando',
        );
      },
    );

    testWidgets(
      'after a stop the recorder fails, the next tap on the $screen discards '
      'the dead microphone and opens a new take, not a second stop',
      (tester) async {
        final room = await enter(tester);
        await room.theTeamOpensItsTake();
        await room.waits(const Duration(seconds: 2));
        room.harness.recorder.stopThrows = true;
        room.tap();
        await room.beat(300);
        expect(room.circleListens, isFalse);
        final deadTake = room.harness.recorder.starts.single;
        final deadStart = room.harness.sounds.lastIndexOf('recorder:start');

        room.harness.recorder.stopThrows = false;
        room.tap();
        await room.beat(300);
        expect(
          room.harness.recorder.starts,
          hasLength(2),
          reason:
              'o toque no círculo em repouso fechava de novo o microfone '
              'morto, e nada voltava a gravar',
        );
        expect(
          room.harness.recorder.starts.last,
          isNot(deadTake),
          reason: 'a nova vez reabria o microfone com o nome da vez morta',
        );
        final newStart = room.harness.sounds.lastIndexOf('recorder:start');
        expect(
          room.harness.sounds.sublist(deadStart + 1, newStart),
          contains('recorder:discard'),
          reason: 'o microfone morto não foi descartado antes da nova vez',
        );
        expect(
          room.circleListens,
          isTrue,
          reason: 'a nova vez abriu e o círculo seguia em repouso',
        );
      },
    );

    testWidgets(
      'a tap on the $screen while another app holds the microphone discards '
      'the dead take and opens a new one, instead of sending what was cut off',
      (tester) async {
        final room = await enter(tester);
        await room.theTeamOpensItsTake();
        await room.waits(const Duration(seconds: 2));
        room.harness.recorder.takeTheMicrophone();
        await room.beat();
        expect(room.circleListens, isFalse);
        final deadTake = room.harness.recorder.starts.single;
        final deadStart = room.harness.sounds.lastIndexOf('recorder:start');
        final turnsBefore = room.harness.room.turnsSent;

        room.tap();
        await room.beat(300);
        expect(
          room.harness.recorder.starts,
          hasLength(2),
          reason:
              'o toque com o microfone tomado parava a vez e mandava à sala '
              'o que foi gravado até a chamada',
        );
        expect(room.harness.recorder.starts.last, isNot(deadTake));
        final newStart = room.harness.sounds.lastIndexOf('recorder:start');
        expect(
          room.harness.sounds.sublist(deadStart + 1, newStart),
          contains('recorder:discard'),
          reason: 'a vez morta não foi descartada antes da nova',
        );
        expect(
          room.harness.room.turnsSent,
          turnsBefore,
          reason: 'o que foi gravado até a chamada subiu como uma vez',
        );
      },
    );

    testWidgets(
      'a second tap on the $screen while the recorder has not answered opens '
      'no second take and stops nothing',
      (tester) async {
        final room = await enter(tester);
        room.harness.recorder.holdNextStart();
        await room.theTeamOpensItsTake();
        await room.beat();
        final heldStart = room.harness.sounds.lastIndexOf('recorder:start');

        room.tap();
        await room.beat(300);
        expect(
          room.harness.recorder.starts,
          hasLength(1),
          reason:
              'o segundo toque descartava o microfone que ainda esperava o '
              'gravador e abria outro',
        );
        expect(
          room.harness.sounds.sublist(heldStart + 1),
          isNot(contains('recorder:discard')),
          reason: 'o toque na espera descartou a vez que o gravador ia abrir',
        );

        room.harness.recorder.finishStart();
        await room.beat(300);
        expect(
          room.circleListens,
          isTrue,
          reason: 'o toque na espera fechou a vez antes de o gravador começar',
        );
      },
    );
  }

  testWidgets(
    'a take past four minutes turns its clock terracotta, and not a second '
    'before',
    (tester) async {
      final room = await _inConversa(tester);
      await room.theTeamOpensItsTake();

      await room.waits(const Duration(minutes: 3, seconds: 59));
      expect(
        room.clock('3:59')?.style?.color,
        _azul,
        reason: 'ficava telha antes dos quatro minutos',
      );

      await room.waits(const Duration(seconds: 1));
      expect(
        room.clock('4:00')?.style?.color,
        _terracotta,
        reason: 'aos quatro minutos o relógio seguia azul',
      );
    },
  );

  testWidgets(
    'the clock goes when the take ends, and the next take starts again at '
    '0:00',
    (tester) async {
      final room = await _inConversa(tester);
      await room.theTeamOpensItsTake();
      await room.waits(const Duration(seconds: 3));
      expect(room.clock('0:03'), isNotNull);

      room.sala.conversaTap();
      await room.until(
        'o microfone fechar',
        () => room.estado.voice != VoiceState.listening,
      );
      expect(room.anyClock, isFalse, reason: 'o relógio ficou depois da vez');

      await room.until(
        'a sala voltar ao convite',
        () => room.estado.voice == VoiceState.invite,
      );
      await room.theTeamOpensItsTake();
      expect(
        room.clock('0:00'),
        isNotNull,
        reason: 'a vez seguinte herdava o tempo da anterior',
      );
    },
  );

  testWidgets(
    'the raised-hand note records with no clock, nor on the tap that sends it',
    (tester) async {
      final room = await _inConversa(tester);
      room.sala.handTap();
      await room.beat();
      room.sala.conversaTap();
      await room.until(
        'a pergunta abrir o microfone',
        () => room.estado.voice == VoiceState.listening,
      );
      expect(room.estado.noteMode, isTrue);
      await room.waits(const Duration(seconds: 3));
      expect(room.anyClock, isFalse, reason: 'o recado mostrava o relógio');

      room.harness.recorder.holdNextStop();
      room.sala.conversaTap();
      await room.beat(300);
      expect(room.estado.voice, VoiceState.listening);
      expect(room.estado.noteMode, isFalse);
      expect(
        room.anyClock,
        isFalse,
        reason: 'o toque que envia o recado acendia o relógio',
      );

      room.harness.recorder.finishStop();
      await room.until(
        'o recado sair',
        () => room.estado.voice != VoiceState.listening,
      );
    },
  );

  testWidgets(
    'the clock takes no touch, and VoiceOver passes over it, not reading the '
    'digits',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final room = await _inConversa(tester);
      await room.theTeamOpensItsTake();
      expect(room.clock('0:00'), isNotNull);

      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(
                of: find.text('0:00'),
                matching: find.byType(IgnorePointer),
              ),
            )
            .any((pointer) => pointer.ignoring),
        isTrue,
        reason: 'o relógio recebia o toque',
      );
      expect(
        find.bySemanticsLabel(RegExp(r'\d+:\d\d')),
        findsNothing,
        reason: 'o leitor de tela lia os dígitos',
      );
      semantics.dispose();
    },
  );
}
