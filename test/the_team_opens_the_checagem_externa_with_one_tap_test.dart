import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/features/sala/presentation/widgets/codigo_view.dart';

import 'a_change_over_an_approved_draft_takes_the_armed_tap_test.dart'
    show aprovadaNaConferida;
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, thePersonSign;
import 'the_back_translation_is_told_by_beads_test.dart' show tocar;
import 'the_team_re_records_one_whole_sentence_test.dart'
    show quatroFrasesEmWav;

const _checagem = 'Checagem externa';
const _subIdle =
    'Quem não ajudou a traduzir ouve a passagem e diz o que entendeu.';
const _novoOuvinte = 'Novo ouvinte';
const _voltar = 'Voltar para a gravação';
const _badge = '✓ aprovado como rascunho final (v1)';
const _naoAbre =
    'a checagem externa abre depois que o rascunho final é aprovado';
const _naoDeu = 'não deu para abrir a checagem externa — tentem de novo';
const _sinal = 'Um momento para uma pessoa';
const _ouvirAFrase1 = 'ouvir a minha tradução da frase 1';
const _recomecar = 'recomeçar a tradução';
const _recomecoArmado = 'toque de novo para apagar as 4 frases traduzidas';

SalaSessionState _sala(ProviderContainer container) =>
    container.read(salaSessionProvider);

Future<void> _tocar(WidgetTester tester, String label) async {
  await tester.ensureVisible(byLabel(label).first);
  await tester.tap(byLabel(label).first);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _passar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _tocarNoRecomeco(WidgetTester tester) async {
  final recomeco = find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (widget.data == _recomecar || widget.data == _recomecoArmado),
  );
  await tester.ensureVisible(recomeco);
  await tester.tap(recomeco);
  await tester.pump(const Duration(milliseconds: 300));
}

bool? _habilitado(WidgetTester tester, String label) =>
    tester.widget<Semantics>(byLabel(label)).properties.enabled;

void main() {
  testWidgets('over an approved draft, one tap on «Checagem externa» opens '
      'its station', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    final falas = List.of(harness.voice.fixedLines);

    await _tocar(tester, _checagem);

    expect(harness.room.externalChecksOpened, [_sala(container).sessionId]);
    expect(find.text(_checagem), findsOneWidget);
    expect(find.text(_subIdle), findsOneWidget);
    expect(byLabel(_novoOuvinte), findsOneWidget);
    expect(_habilitado(tester, _novoOuvinte), isTrue);
    expect(find.byType(CodigoView), findsNothing);
    expect(harness.voice.fixedLines, falas);
    closeTheRoom(container);
  });

  testWidgets('the station holds the version the room answered', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.approvedDraft = const ApprovedDraft(version: 2);

    await _tocar(tester, _checagem);

    expect(_sala(container).station, const ChecagemExterna(2));
    closeTheRoom(container);
  });

  testWidgets('a draft the room no longer holds as approved opens nothing and '
      'says why', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.approvedDraft = null;

    await _tocar(tester, _checagem);

    expect(find.text(_naoAbre), findsOneWidget);
    expect(_sala(container).stage, SalaStage.retro);
    expect(find.text(_badge), findsNothing);
    expect(byLabel(_checagem), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('when the room cannot answer, the team stays and reads her '
      'open-failed text', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.failExternalCheckOnceWith = const NetworkFailed('sem rede');

    await _tocar(tester, _checagem);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(_sala(container).stage, SalaStage.retro);
    expect(find.text(_badge), findsOneWidget);
    expect(byLabel(_checagem), findsOneWidget);
    expect(find.text(_sinal), findsNothing);
    expect(thePersonSign, findsNothing);
    closeTheRoom(container);
  });

  testWidgets('a passage zeroed on the Desk sends the team to the Choice', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.forgetTheSession(_sala(container).sessionId!);

    await _tocar(tester, _checagem);

    expect(harness.room.askedOfTheForgotten.first, 'openTheExternalCheck');
    expect(_sala(container).stage, SalaStage.escolha);
    closeTheRoom(container);
  });

  testWidgets('the way back lands on the Back-translation as it was, and a '
      'second tap opens the station again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    final sessionId = _sala(container).sessionId;
    await _tocar(tester, _checagem);
    expect(harness.room.externalChecksOpened, [sessionId]);

    await _tocar(tester, _voltar);

    expect(find.text(_badge), findsOneWidget);
    expect(byLabel(_checagem), findsOneWidget);
    expect(find.text(_subIdle), findsNothing);

    await _tocar(tester, _checagem);

    expect(find.text(_subIdle), findsOneWidget);
    expect(harness.room.externalChecksOpened, [sessionId, sessionId]);
    closeTheRoom(container);
  });

  testWidgets('on the station, «Ouvir de novo» is not offered', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);

    await _tocar(tester, _checagem);

    expect(find.text(_subIdle), findsOneWidget);
    expect(byLabel('Ouvir de novo'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('while an approval is in the air, «Checagem externa» opens '
      'nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await quatroFrasesEmWav(tester, harness);
    harness.room.verdictChecked = true;
    await tocar(tester, 'terminei');
    await waitFor(
      'a sala conferir',
      () => byLabel('Aprovar como rascunho final').evaluate().isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );
    harness.room.approvedDraft = const ApprovedDraft(version: 1);
    harness.voice.holdNextLine();
    await tocar(tester, 'Aprovar como rascunho final');
    await waitFor(
      'o botão da checagem aparecer',
      () => byLabel(_checagem).evaluate().isNotEmpty,
      step: () => tester.pump(const Duration(milliseconds: 100)),
    );

    await tester.ensureVisible(byLabel(_checagem));
    await tester.tap(byLabel(_checagem));
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.room.externalChecksOpened, isEmpty);
    harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(container);
  });

  testWidgets('a stretch tapped while the open is out plays nothing on the '
      'station', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.holdNextExternalCheck();
    await _tocar(tester, _checagem);

    await _tocar(tester, _ouvirAFrase1);
    harness.room.finishHeldExternalCheck();
    await _passar(tester);

    expect(find.text(_subIdle), findsOneWidget);
    expect(harness.playback.sounding, isFalse);
    closeTheRoom(container);
  });

  testWidgets('a restart tapped while the open is out sends nothing, and the '
      'Back-translation is as it was', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aprovadaNaConferida(tester, harness);
    harness.room.holdNextExternalCheck();
    await _tocar(tester, _checagem);

    await _tocarNoRecomeco(tester);
    await tester.pump(const Duration(seconds: 1));
    await _tocarNoRecomeco(tester);
    harness.room.finishHeldExternalCheck();
    await _passar(tester);

    expect(harness.room.restartsAsked, isEmpty);
    await _tocar(tester, _voltar);
    expect(find.text(_badge), findsOneWidget);
    expect(byLabel(_checagem), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('in English', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aprovadaNaConferida(
      tester,
      harness,
      caminho: (
        terminei: 'done',
        aprovar: 'Approve as the final draft',
        salvo: 'Rehearsal saved',
        pronto: 'Done',
      ),
    );

    await _tocar(tester, 'External check');

    expect(find.text('External check'), findsOneWidget);
    expect(
      find.text(
        "Those who didn't help translate hear the passage and say what they "
        'understood.',
      ),
      findsOneWidget,
    );
    expect(byLabel('New listener'), findsOneWidget);
    expect(byLabel('Back to recording'), findsOneWidget);
    closeTheRoom(container);
  });
}
