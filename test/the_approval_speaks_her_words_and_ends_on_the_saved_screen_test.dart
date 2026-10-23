import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

const _aprovar = 'Aprovar como rascunho final';
const _ouvir = 'Ouvir a gravação';
const _traduzir = 'Traduzir a gravação';
const _sinal = 'Um momento para uma pessoa';

const _faltaOuvir = 'ainda falta ouvir um trecho da gravação';
const _precisaConferida = 'para aprovar, a tradução precisa estar conferida';
const _naoDeu = 'não deu para conferir agora — tentem de novo';
const _ensaioSalvo = 'Ensaio salvo';
const _pronto = 'Pronto';

String _aprovado(int v) =>
    'Aprovado como rascunho final da equipe (v$v). Próximo passo: a checagem '
    'externa — o botão aqui embaixo.';

String _approved(int v) =>
    "Approved as the team's final draft (v$v). Next step: the external check "
    '— the button below.';

typedef _Sala = ({SalaHarness harness, ProviderContainer container});

/// One part recorded, told back whole, and the room's check clean: the team standing on
/// the approval press.
Future<_Sala> _ateAConferida(
  WidgetTester tester, {
  String lingua = testLanguage,
  String aprovar = _aprovar,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: lingua);
  harness.room.verdictChecked = true;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = container.read(salaSessionProvider.notifier);
  await sala.goConversa(book: 'Ruth', pericope: 'P01');
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await theRoomNamesTheParts(tester, container, parts: 1);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  sala.retroTap();
  sala.retroTap();
  await tester.pump(const Duration(milliseconds: 200));
  await confirmarATraducaoNaTela(tester, container);
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));

  expect(
    byLabel(aprovar),
    findsOneWidget,
    reason:
        'o cenário só mede alguma coisa se a sala chegar ao gesto de aprovar',
  );
  return (harness: harness, container: container);
}

Future<void> _tocar(WidgetTester tester, [String rotulo = _aprovar]) async {
  await tester.tap(byLabel(rotulo));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _approvedThroughPronto(
  WidgetTester tester,
  _Sala it, {
  ApprovedDraft? readSays = const ApprovedDraft(version: 1),
}) async {
  it.harness.room.approvedDraft = readSays;
  await _tocar(tester);
  expect(find.text(_ensaioSalvo), findsOneWidget);
  await tester.tap(byLabel(_pronto));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'a take not heard in full: the approval shows «$_faltaOuvir» and the part '
    'plays',
    (tester) async {
      late Sala it;
      await tester.runAsync(() async {
        it = await umEnsaioContadoInteiro(
          partesDoEnsaio,
          numaSala: SalaHarness(filaEmMemoria: true),
        );
        it.harness.room.verdictChecked = true;
        await pedirOVeredito(it);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: it.container,
          child: const SalaApp(),
        ),
      );
      await tester.pump();
      final segunda = it.partes[1];
      it.harness.room
        ..releaseBlockers = const ['playback_did_not_cover_the_clip']
        ..releaseUnheardTakeIds = [segunda.takeId!];

      expect(find.text(_faltaOuvir), findsNothing);
      final tocadas = it.harness.playback.played.length;
      await tester.tap(byLabel(_aprovar));
      await tester.runAsync(
        () => waitFor(
          'a parte 2 entrar no ar',
          () =>
              it.harness.playback.played.length > tocadas &&
              it.harness.playback.played.last == segunda.path,
        ),
      );
      await tester.pump();

      expect(find.text(_faltaOuvir), findsOneWidget);
      expect(it.harness.playback.played.last, segunda.path);
      expect(byLabel(_sinal), findsNothing);
      closeTheRoom(it.container);
    },
  );

  for (final (codigo, trecho) in [
    ('telling_back_not_checked', null),
    ('telling_back_never_analysed', null),
    ('untold_stretch', 'trecho-1'),
  ]) {
    testWidgets(
      'no clean check on these takes ($codigo): «$_precisaConferida»',
      (tester) async {
        final it = await _ateAConferida(tester);
        it.harness.room
          ..releaseBlockers = [codigo]
          ..releaseUntoldSegmentId = trecho;
        expect(find.text(_precisaConferida), findsNothing);

        await _tocar(tester);

        expect(find.text(_precisaConferida), findsOneWidget);
        expect(byLabel(_sinal), findsNothing);
        closeTheRoom(it.container);
      },
    );
  }

  testWidgets('the server cannot answer: «$_naoDeu»', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const NetworkFailed('sem rede');

    await _tocar(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(byLabel(_sinal), findsNothing);
    expect(byLabel(_aprovar), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets('a failed approval is never sent again on its own', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const NetworkFailed('sem rede');
    await _tocar(tester);

    await tester.pump(const Duration(minutes: 2));

    expect(it.harness.room.releasesAsked, hasLength(1));

    it.harness.room.failReleaseWith = null;
    await _tocar(tester);

    expect(it.harness.room.releasesAsked, hasLength(2));
    expect(find.text(_ensaioSalvo), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets('the version race: «$_naoDeu»', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const Refused('CONFLICT');

    await _tocar(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(byLabel(_sinal), findsNothing);

    await tester.pump(const Duration(minutes: 2));

    expect(it.harness.room.releasesAsked, hasLength(1));
    closeTheRoom(it.container);
  });

  testWidgets('a refusal no door names shows the third text, never nothing', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['coisa_nova'];

    await _tocar(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets(
    'an answer with neither a version nor a refusal shows the third text',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.release = const ApprovalAnswer();

      await _tocar(tester);

      expect(find.text(_naoDeu), findsOneWidget);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'approved from the check screen: the sentence, P3, then «$_ensaioSalvo», '
    'and «$_pronto» lands on the Back-translation',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      final falasAntes = it.harness.voice.fixedLines.length;

      it.harness.voice.holdNextLine();
      await _tocar(tester);

      expect(find.text(_aprovado(1)), findsOneWidget);
      expect(
        it.harness.voice.fixedLines.skip(falasAntes),
        contains(('P3', testLanguage)),
      );
      expect(find.text(_ensaioSalvo), findsNothing);

      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsOneWidget);
      expect(find.text(_aprovado(1)), findsOneWidget);
      expect(byLabel(_pronto), findsOneWidget);
      expect(byLabel(_aprovar), findsNothing);
      expect(byLabel(_ouvir), findsNothing);
      expect(find.text(_traduzir), findsNothing);

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsNothing);
      expect(find.text(_traduzir), findsOneWidget);
      expect(find.text('✓ aprovado como rascunho final (v1)'), findsOneWidget);
      expect(byLabel(_aprovar), findsNothing);
      expect(it.harness.emAberto.rows, contains('Ruth/P01/pt'));

      await tester.pump(it.harness.fimLinger + const Duration(seconds: 2));

      expect(find.text(_traduzir), findsOneWidget);
      expect(it.harness.emAberto.rows, contains('Ruth/P01/pt'));
      closeTheRoom(it.container);
    },
  );

  testWidgets('«Done» never leads to the Choice, in English too', (
    tester,
  ) async {
    final it = await _ateAConferida(
      tester,
      lingua: 'en',
      aprovar: 'Approve as the final draft',
    );
    it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
    final falasAntes = it.harness.voice.fixedLines.length;

    await _tocar(tester, 'Approve as the final draft');

    expect(
      it.harness.voice.fixedLines.skip(falasAntes),
      contains(('P3', 'en')),
    );
    expect(find.text('Rehearsal saved'), findsOneWidget);
    expect(find.text(_approved(1)), findsOneWidget);

    await tester.tap(byLabel('Done'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(it.harness.fimLinger + const Duration(seconds: 2));

    expect(find.text('Rehearsal saved'), findsNothing);
    expect(find.text('Translate the recording'), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets('a second version reads v2 on both screens', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room
      ..release = const ApprovalAnswer(releaseId: 'solta-2', version: 2)
      ..approvedDraft = const ApprovedDraft(version: 2);

    it.harness.voice.holdNextLine();
    await _tocar(tester);

    expect(find.text(_aprovado(2)), findsOneWidget);

    it.harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_ensaioSalvo), findsOneWidget);
    expect(find.text(_aprovado(2)), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets(
    'an approval line cut short still ends on «$_ensaioSalvo», and the line is '
    'not asked again',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      final falasAntes = it.harness.voice.fixedLines.length;

      it.harness.voice.holdNextLine();
      await _tocar(tester);
      it.harness.voice.succeeds = false;
      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsOneWidget);
      expect(find.text(_aprovado(1)), findsOneWidget);

      it.harness.voice.succeeds = true;
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('✓ aprovado como rascunho final (v1)'), findsOneWidget);
      expect(
        it.harness.voice.fixedLines
            .skip(falasAntes)
            .where((line) => line.$1 == 'P3'),
        hasLength(1),
      );
      expect(it.harness.room.releasesAsked, hasLength(1));
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'an approval line the room could not give still ends on «$_ensaioSalvo»',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);

      it.harness.voice.holdNextLine();
      await _tocar(tester);
      it.harness.voice.failHeldLine(const NetworkFailed('sem rede'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsOneWidget);
      expect(find.text(_aprovado(1)), findsOneWidget);
      expect(find.text(_naoDeu), findsNothing);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'after «$_pronto», an approval pressed again asks the room again',
    (tester) async {
      final it = await _ateAConferida(tester);
      await _approvedThroughPronto(tester, it, readSays: null);

      expect(byLabel(_aprovar), findsOneWidget);

      await _tocar(tester);

      expect(it.harness.room.releasesAsked, hasLength(2));
      closeTheRoom(it.container);
    },
  );

  testWidgets('«Ele vai para o OBT Refine.» is never shown', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.voice.holdNextLine();
    await _tocar(tester);

    expect(find.textContaining('Refine'), findsNothing);

    it.harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_ensaioSalvo), findsOneWidget);
    expect(find.textContaining('Refine'), findsNothing);
    closeTheRoom(it.container);
  });
}
