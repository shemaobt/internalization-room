import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
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

  Text? clock(String digits) => switch (find.text(digits).evaluate()) {
    final found when found.isEmpty => null,
    final found => found.single.widget as Text,
  };

  Future<void> theTeamOpensItsTake() async {
    view == PanoramaView ? sala.panoramaTap() : sala.conversaTap();
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
}
