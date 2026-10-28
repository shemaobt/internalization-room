import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/hear_again_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/moment_label.dart';
import 'package:internalization_room/features/sala/presentation/widgets/panorama_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, enterThePanorama;
import 'the_kept_retellings_are_numbered_buttons_on_the_conversation_test.dart'
    show atRestAfterATurn;

const _panorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
);

Future<void> _beat(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _inConversa(WidgetTester tester) async {
  final container = await pumpSala(tester, SalaHarness());
  addTearDown(() => closeTheRoom(container));
  unawaited(
    container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth'),
  );
  await waitFor('a conversa abrir no convite', () {
    final estado = container.read(salaSessionProvider);
    return estado.stage == SalaStage.conversa &&
        estado.voice == VoiceState.invite;
  }, step: () => _beat(tester));
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

Future<ProviderContainer> _inThePanorama(WidgetTester tester) async {
  final harness = SalaHarness();
  harness.room.passages = [_panorama, ...harness.room.passages];
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  SalaSessionState estado() => container.read(salaSessionProvider);
  await enterThePanorama(
    container.read(salaSessionProvider.notifier),
    estado,
    step: () => _beat(tester),
  );
  await waitFor(
    'a sala voltar ao convite',
    () => estado().panoramaSaid && estado().voice == VoiceState.invite,
    step: () => _beat(tester),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

void _onA(WidgetTester tester, double width, double height) {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _circleOn(Type view) => find.descendant(
  of: find.byType(view),
  matching: find.byType(FacilitatorCircle),
);

void main() {
  for (final (screen, enter) in [
    (ConversaView, _inConversa),
    (PanoramaView, _inThePanorama),
  ]) {
    for (final (width, height, side) in [
      (375.0, 667.0, 217.5),
      (768.0, 1024.0, 232.0),
    ]) {
      testWidgets('the circle on the $screen of a ${width.toInt()} wide '
          'screen is ${side}pt across, not one size for every tablet', (
        tester,
      ) async {
        _onA(tester, width, height);
        await enter(tester);

        expect(
          tester.getSize(_circleOn(screen)),
          Size(side, side),
          reason:
              'o círculo tinha 158/160 em toda tela; o dela é '
              'min(58vw, 232px) (globals.css:110)',
        );
      });
    }
  }

  for (final (screen, enter) in [
    (ConversaView, _inConversa),
    (PanoramaView, _inThePanorama),
  ]) {
    testWidgets('the mic clock on the $screen of an SE sits 2.4rem above '
        'her ring, not above a 158 disc', (tester) async {
      _onA(tester, 375, 667);
      final container = await enter(tester);
      screen == PanoramaView
          ? container.read(salaSessionProvider.notifier).panoramaTap()
          : container.read(salaSessionProvider.notifier).conversaTap();
      await waitFor(
        'o microfone abrir',
        () => container.read(salaSessionProvider).voice == VoiceState.listening,
        step: () => _beat(tester),
      );
      await _beat(tester);

      expect(
        tester.getTopLeft(find.text('0:00')).dy,
        closeTo(186.35, 0.01),
        reason:
            'o relógio ficava a 38,4 da borda de um círculo de 158; o dela '
            'fica em 50% - min(29vw,116px) - 2.4rem (globals.css:78)',
      );
    });
  }

  for (final (width, height) in [
    (375.0, 667.0),
    (768.0, 1024.0),
    (1024.0, 768.0),
  ]) {
    testWidgets('on a ${width.toInt()} by ${height.toInt()} screen her ring, '
        'breathing at its fullest, touches neither the hand, hear-again, the '
        'moment label nor the mic clock', (tester) async {
      _onA(tester, width, height);
      final (_, container) = await atRestAfterATurn(tester, const []);
      Rect circle() {
        final drawn = tester.getRect(_circleOn(ConversaView));
        return Rect.fromCenter(
          center: drawn.center,
          width: drawn.width * 1.045,
          height: drawn.height * 1.045,
        );
      }

      for (final (name, around) in [
        ('a mão', byLabel('Leave a question for your facilitator')),
        (
          'o ouvir de novo',
          find
              .descendant(
                of: find.byType(HearAgainButton),
                matching: find.byType(SizedBox),
              )
              .first,
        ),
        ('o rótulo do momento', find.byType(MomentLabel)),
      ]) {
        expect(around, findsOneWidget, reason: '$name precisa estar na tela');
        expect(
          circle().overlaps(tester.getRect(around)),
          isFalse,
          reason: 'o círculo dela encostava em $name',
        );
      }

      container.read(salaSessionProvider.notifier).conversaTap();
      await waitFor(
        'o microfone abrir',
        () => container.read(salaSessionProvider).voice == VoiceState.listening,
        step: () => _beat(tester),
      );
      await _beat(tester);
      expect(
        circle().overlaps(tester.getRect(find.text('0:00'))),
        isFalse,
        reason: 'o círculo dela encostava no relógio do microfone',
      );
    });
  }
}
