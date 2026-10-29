import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        aceso,
        cabeca,
        conferir,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        passaDoCursor,
        tocarNoCirculo;

const _faltaOuvir = 'ainda falta ouvir um trecho da gravação';
const _stillToHear = 'there is still a part of the recording to listen to';

Finder _naTela(String linha) =>
    find.descendant(of: find.byType(RetroView), matching: find.text(linha));

Future<ProviderContainer> _umaFraseEPausada(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  harness.playback.at = cabeca;
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await tocarNoCirculo(tester);
  await waitFor(
    'a parte seguir depois da frase',
    () => harness.playback.sounding,
    step: () => tester.pump(const Duration(milliseconds: 100)),
  );
  harness.playback.at = const Duration(seconds: 6);
  await tester.pump(passaDoCursor);
  await tocarNoCirculo(tester);
  return container;
}

void main() {
  testWidgets('a frase told and the telling paused writes «ainda falta ouvir '
      'um trecho da gravação» under the dark terminei, before any tap', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _umaFraseEPausada(tester, harness);
    final estado = container.read(salaSessionProvider);

    expect(estado.btTrechos.where((trecho) => trecho.contado), hasLength(1));
    expect(estado.btPhase, BtPhase.playing);
    expect(aceso(tester, conferir), isFalse);
    expect(
      _naTela(_faltaOuvir),
      findsOneWidget,
      reason: 'a linha só aparecia depois de um terminei recusado',
    );
    expect(
      tester.getRect(_naTela(_faltaOuvir)).top,
      greaterThanOrEqualTo(tester.getRect(byLabel(conferir)).bottom),
      reason: 'a linha dela fica debaixo do terminei apagado',
    );
    closeTheRoom(container);
  });

  testWidgets('in English the dark terminei carries «there is still a part of '
      'the recording to listen to» under it', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await _umaFraseEPausada(tester, harness);

    expect(
      _naTela(_stillToHear),
      findsOneWidget,
      reason: 'a linha em inglês não aparecia antes do toque',
    );
    closeTheRoom(container);
  });

  testWidgets('a telling paused before any frase is told writes nothing under '
      'terminei, not the line of a part still to hear', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = const Duration(seconds: 2);
    await tester.pump(passaDoCursor);
    await tocarNoCirculo(tester);
    final estado = container.read(salaSessionProvider);

    expect(estado.btTrechos.where((trecho) => trecho.contado), isEmpty);
    expect(estado.btPhase, BtPhase.playing);
    expect(aceso(tester, conferir), isFalse);
    expect(
      _naTela(_faltaOuvir),
      findsNothing,
      reason: 'sem frase contada ela não escreve nada debaixo do terminei',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase being recorded clears the line under terminei, which '
      'is written only while nothing of the team runs', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _umaFraseEPausada(tester, harness);
    expect(_naTela(_faltaOuvir), findsOneWidget);

    await tocarNoCirculo(tester);

    expect(container.read(salaSessionProvider).btPhase, BtPhase.capturing);
    expect(
      _naTela(_faltaOuvir),
      findsNothing,
      reason: 'a linha ficava debaixo do terminei com a equipe gravando',
    );
    closeTheRoom(container);
  });

  testWidgets('the line under terminei goes as soon as the telling reaches the '
      'end and terminei lights', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);
    harness.playback.at = cabeca;
    await tocarNoCirculo(tester);
    await gravarATraducao(tester);
    expect(_naTela(_faltaOuvir), findsOneWidget);

    await contarAteOFimDaParte(tester, harness);
    await waitFor(
      'o terminei acender',
      () => container.read(salaSessionProvider).canAdvanceToTheVerdict,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    expect(aceso(tester, conferir), isTrue);
    expect(
      _naTela(_faltaOuvir),
      findsNothing,
      reason: 'a linha ficava debaixo do terminei já aceso',
    );
    closeTheRoom(container);
  });
}
