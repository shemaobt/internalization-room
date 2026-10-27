import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

final _azul = const Color(0xFF89AAA3).withValues(alpha: 0.75);

final _theCircle = find.descendant(
  of: find.byType(ConversaView),
  matching: find.byType(FacilitatorCircle),
);

class _Room {
  final WidgetTester tester;
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.tester, this.harness, this.container);

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

  Text? clock(String digits) => switch (find.text(digits).evaluate()) {
    final found when found.isEmpty => null,
    final found => found.single.widget as Text,
  };

  Future<void> theTeamOpensItsTake() async {
    sala.conversaTap();
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
  final room = _Room(tester, harness, container);
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

void main() {
  testWidgets(
    'a take on the conversation shows 0:00 above the circle and counts up '
    'each second, in a quiet blue-green',
    (tester) async {
      final room = await _inConversa(tester);
      expect(room.clock('0:00'), isNull, reason: 'o relógio já estava lá');

      await room.theTeamOpensItsTake();

      final atStart = room.clock('0:00');
      expect(atStart, isNotNull, reason: 'o microfone abriu sem relógio');
      expect(atStart!.style?.color, _azul);
      expect(
        tester.getRect(find.text('0:00')).bottom,
        lessThan(tester.getRect(_theCircle).top),
        reason: 'o relógio não estava acima do círculo',
      );

      await room.waits(const Duration(seconds: 1));
      expect(room.clock('0:01'), isNotNull, reason: 'o relógio não andou');

      await room.waits(const Duration(seconds: 64));
      expect(room.clock('1:05'), isNotNull, reason: 'o relógio não contava');
    },
  );
}
