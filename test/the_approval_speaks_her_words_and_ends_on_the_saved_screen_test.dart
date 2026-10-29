import 'package:flutter/widgets.dart';
import 'dart:ui' show Tristate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/approval_answer.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart';

const _aprovar = 'Aprovar como rascunho final';
const _ouvir = 'Ouvir a gravação';
const _traduzir = 'Traduzir a gravação';

const _faltaOuvir = 'ainda falta ouvir um trecho da gravação';
const _precisaConferida = 'para aprovar, a tradução precisa estar conferida';
const _naoDeu = 'não deu para conferir agora — tentem de novo';
const _ensaioSalvo = 'Ensaio salvo';
const _pronto = 'Pronto';
const _recomecar = 'recomeçar a tradução';
const _naoDeuRecomecar = 'não deu para recomeçar agora — tentem de novo';
const _badge = '✓ aprovado como rascunho final (v1)';
const _conferida = '✓ traduzida e conferida';

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
  await _conferir(tester, harness, container);

  expect(
    byLabel(aprovar),
    findsOneWidget,
    reason:
        'o cenário só mede alguma coisa se a sala chegar ao gesto de aprovar',
  );
  return (harness: harness, container: container);
}

Future<void> _conferir(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
) async {
  final sala = container.read(salaSessionProvider.notifier);
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
}

Future<void> _assentar(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _saiEVoltaAConferida(WidgetTester tester, _Sala it) async {
  final sala = it.container.read(salaSessionProvider.notifier);
  sala.goEnsaio();
  await tester.pump(const Duration(milliseconds: 300));
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));
  await _conferir(tester, it.harness, it.container);
}

ButtonMood _humor(WidgetTester tester, String rotulo) => tester
    .widget<RoundActionButton>(
      find.ancestor(
        of: byLabel(rotulo),
        matching: find.byType(RoundActionButton),
      ),
    )
    .mood;

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

Finder _recomecoArmado() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label ?? '').startsWith(
        'toque de novo para apagar as',
      ),
);

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
      await tester.ensureVisible(byLabel(_aprovar));
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
      expect(thePersonSign, findsNothing);
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
        expect(thePersonSign, findsNothing);
        closeTheRoom(it.container);
      },
    );
  }

  testWidgets('the server cannot answer: «$_naoDeu»', (tester) async {
    final it = await _ateAConferida(tester);
    it.harness.room.failReleaseWith = const NetworkFailed('sem rede');

    await _tocar(tester);

    expect(find.text(_naoDeu), findsOneWidget);
    expect(thePersonSign, findsNothing);
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
    expect(thePersonSign, findsNothing);

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

  testWidgets(
    'a refusal text from an earlier press never stands under the badge',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.failReleaseWith = const NetworkFailed('sem rede');
      await _tocar(tester);
      expect(find.text(_naoDeu), findsOneWidget);

      it.harness.room.failReleaseWith = null;
      await _approvedThroughPronto(tester, it);

      expect(find.text(_badge), findsOneWidget);
      expect(find.text(_naoDeu), findsNothing);
      closeTheRoom(it.container);
    },
  );

  for (final (lingua, aprovar, pronto, selo) in [
    ('pt', _aprovar, _pronto, _badge),
    (
      'en',
      'Approve as the final draft',
      'Done',
      '✓ approved as the final draft (v1)',
    ),
  ]) {
    testWidgets(
      'on a phone as narrow as the iPhone SE the $lingua badge wraps beside the '
      'listen button instead of running off the screen',
      (tester) async {
        tester.view
          ..physicalSize = const Size(375, 667)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final it = await _ateAConferida(
          tester,
          lingua: lingua,
          aprovar: aprovar,
        );
        it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
        await _tocar(tester, aprovar);
        await tester.tap(byLabel(pronto));
        await tester.pump(const Duration(milliseconds: 300));

        final onde = tester.getRect(find.text(selo));
        expect(onde.left, greaterThanOrEqualTo(0));
        expect(
          onde.right,
          lessThanOrEqualTo(375),
          reason:
              'o selo passava da borda direita do iPhone SE e era cortado '
              'no «final»',
        );
        closeTheRoom(it.container);
      },
    );
  }

  testWidgets(
    'the restart pressed twice while the approval line plays does nothing, and '
    '«$_ensaioSalvo» still comes',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      it.harness.voice.holdNextLine();
      await _tocar(tester);

      it.container.read(salaSessionProvider.notifier).recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 700));
      it.container.read(salaSessionProvider.notifier).recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 300));
      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));

      expect(it.harness.room.restartsAsked, isEmpty);
      expect(find.text(_ensaioSalvo), findsOneWidget);

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_badge), findsOneWidget);
      expect(find.text(_aprovado(1)), findsNothing);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'a frase told again while the approval line plays starts nothing, and '
    '«$_ensaioSalvo» comes after the line',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      it.harness.voice.holdNextLine();
      await _tocar(tester);

      final tocadas = it.harness.playback.playedFrom.length;
      it.container.read(salaSessionProvider.notifier).traduzirAFraseDeNovo(0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        it.container.read(salaSessionProvider).btPhase,
        BtPhase.conferida,
        reason: 'a frase contada de novo abria uma regravação sob a aprovação',
      );
      expect(it.harness.playback.playedFrom, hasLength(tocadas));
      expect(find.text(_ensaioSalvo), findsNothing);

      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_ensaioSalvo), findsOneWidget);

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_badge), findsOneWidget);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'the recording asked while the approval line plays does not play',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.voice.holdNextLine();
      await _tocar(tester);
      final tocadas = it.harness.playback.playedFrom.length;

      await tester.tap(byLabel(_ouvir));
      await tester.pump(const Duration(milliseconds: 300));

      expect(it.harness.playback.playedFrom, hasLength(tocadas));
      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(it.container);
    },
  );

  testWidgets('a frase asked while the approval line plays does not play', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.voice.holdNextLine();
    await _tocar(tester);
    final tocadas = it.harness.playback.playedFrom.length;

    it.container.read(salaSessionProvider.notifier).ouvirOTrechoContado(0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.harness.playback.playedFrom, hasLength(tocadas));
    it.harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));
    closeTheRoom(it.container);
  });

  testWidgets(
    'an approval left before its line ended leaves no approved sentence behind',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.voice.holdNextLine();
      await _tocar(tester);
      expect(find.text(_aprovado(1)), findsOneWidget);

      final sala = it.container.read(salaSessionProvider.notifier);
      sala.goEnsaio();
      await tester.pump(const Duration(milliseconds: 300));
      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));
      sala.startRetro();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_traduzir), findsOneWidget);
      expect(find.text(_aprovado(1)), findsNothing);
      closeTheRoom(it.container);
    },
  );

  testWidgets('a restart armed before the approval is idle after «$_pronto»', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
    it.container.read(salaSessionProvider.notifier).recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 100));

    await _tocar(tester);
    await tester.tap(byLabel(_pronto));
    await tester.pump(const Duration(milliseconds: 800));

    expect(byLabel(_recomecar), findsOneWidget);
    it.container.read(salaSessionProvider.notifier).recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.harness.room.restartsAsked, isEmpty);
    closeTheRoom(it.container);
  });

  testWidgets(
    'after a failed restart, an approval the room cannot answer shows her third '
    'text, not the restart\'s',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.failRestartWith = const NetworkFailed('sem rede');
      it.container.read(salaSessionProvider.notifier).recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 700));
      it.container.read(salaSessionProvider.notifier).recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_naoDeuRecomecar), findsOneWidget);

      it.harness.room.failReleaseWith = const NetworkFailed('sem rede');
      await _tocar(tester);

      expect(find.text(_naoDeu), findsOneWidget);
      expect(find.text(_naoDeuRecomecar), findsNothing);
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'while the approval line plays, the recording circle is not offered and '
    'the restart reads disabled',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await _ateAConferida(tester);
      it.harness.voice.holdNextLine();
      await _tocar(tester);

      expect(_humor(tester, _ouvir), ButtonMood.dimmed);
      expect(
        tester
            .getSemantics(byLabel(_recomecar))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );

      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(it.container);
      semantics.dispose();
    },
  );

  testWidgets('an approval left in the air answers only its own press: a newer '
      'approval\'s line still holds the room and ends on «$_ensaioSalvo»', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.holdNextRelease();
    await _tocar(tester);

    final sala = it.container.read(salaSessionProvider.notifier);
    await _saiEVoltaAConferida(tester, it);
    it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
    it.harness.voice.holdNextLine();
    await _tocar(tester);
    expect(find.text(_aprovado(1)), findsOneWidget);

    it.harness.room.finishHeldRelease();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_aprovado(1)), findsOneWidget);
    sala.recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _recomecoArmado(),
      findsNothing,
      reason: 'a resposta da primeira aprovação abria os gestos da segunda',
    );

    it.harness.voice.finishHeldLine();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_ensaioSalvo), findsOneWidget);
    closeTheRoom(it.container);
  });

  testWidgets(
    'while the room still reads back the stretch a refusal names, the restart '
    'and the approve button do nothing and are not drawn live; the stretch '
    'plays, then the restart acts',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room
        ..releaseBlockers = const ['untold_stretch']
        ..releaseUntoldSegmentId = 'trecho-1'
        ..holdNextState();
      final trechosNoAr = it.harness.playback.ranges.length;
      await _tocar(tester);
      expect(find.text(_precisaConferida), findsOneWidget);

      final sala = it.container.read(salaSessionProvider.notifier);
      sala.recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 700));
      sala.recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 300));
      expect(it.harness.room.restartsAsked, isEmpty);
      expect(_humor(tester, _aprovar), ButtonMood.dimmed);

      it.harness.room.finishHeldState();
      await tester.pump(const Duration(milliseconds: 400));
      expect(it.harness.playback.ranges, hasLength(trechosNoAr + 1));

      sala.recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 700));
      sala.recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 300));
      expect(it.harness.room.restartsAsked, hasLength(1));
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'an approval left in the air never lets a newer one be sent twice',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.holdNextRelease();
      await _tocar(tester);
      final sala = it.container.read(salaSessionProvider.notifier);
      await _saiEVoltaAConferida(tester, it);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      it.harness.voice.holdNextLine();
      await _tocar(tester);

      it.harness.room.finishHeldRelease();
      await tester.pump(const Duration(milliseconds: 300));
      await sala.aprovarRascunhoFinal();
      await tester.pump(const Duration(milliseconds: 300));

      expect(it.harness.room.releasesAsked, hasLength(2));
      it.harness.voice.finishHeldLine();
      await tester.pump(const Duration(milliseconds: 300));
      closeTheRoom(it.container);
    },
  );

  testWidgets(
    'an approval left in the air holds nothing once the team comes back to '
    'the checked translation: the restart and the recording act',
    (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.holdNextRelease();
      await _tocar(tester);
      await _saiEVoltaAConferida(tester, it);

      final tocadas = it.harness.playback.playedFrom.length;
      await tester.tap(byLabel(_ouvir));
      await tester.pump(const Duration(milliseconds: 300));
      expect(it.harness.playback.playedFrom, hasLength(tocadas + 1));

      it.container.read(salaSessionProvider.notifier).recomecarATraducao();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_recomecoArmado(), findsOneWidget);
      it.harness.room.finishHeldRelease();
      await tester.pump(const Duration(seconds: 7));
      closeTheRoom(it.container);
    },
  );

  testWidgets('a refusal whose read fails gives the gestures back', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room
      ..releaseBlockers = const ['untold_stretch']
      ..releaseUntoldSegmentId = 'trecho-1'
      ..failStateOnceWith = const NetworkFailed('sem rede');
    await _tocar(tester);

    it.container.read(salaSessionProvider.notifier).recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_recomecoArmado(), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(it.container);
  });

  group('the recording home', () {
    Future<_Sala> aCasaConferida(
      WidgetTester tester, {
      String lingua = testLanguage,
    }) async {
      final it = await _ateAConferida(
        tester,
        lingua: lingua,
        aprovar: lingua == 'en' ? 'Approve as the final draft' : _aprovar,
      );
      it.harness.room.retroSoFar = const BackTranslationProgress(checked: true);
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await _assentar(tester);
      return it;
    }

    testWidgets('a checked passage says «$_conferida» above the approve '
        'button', (tester) async {
      final it = await aCasaConferida(tester);

      expect(
        find.text(_conferida),
        findsOneWidget,
        reason: 'a sala dava a passagem por conferida e a casa não dizia',
      );
      expect(
        tester.getTopLeft(find.text(_conferida)).dy,
        lessThan(tester.getTopLeft(byLabel(_aprovar)).dy),
      );
      closeTheRoom(it.container);
    });

    testWidgets('an approved passage still says «$_conferida», above its '
        'badge', (tester) async {
      final it = await aCasaConferida(tester);
      await _approvedThroughPronto(tester, it);

      expect(find.text(_conferida), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_conferida)).dy,
        lessThan(tester.getTopLeft(find.text(_badge)).dy),
      );
      closeTheRoom(it.container);
    });

    testWidgets('an English session says «✓ translated and checked»', (
      tester,
    ) async {
      final it = await aCasaConferida(tester, lingua: 'en');

      expect(find.text('✓ translated and checked'), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('a passage the room has not checked says nothing of it, and a '
        'kept take takes the line away', (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room.retroSoFar = const BackTranslationProgress();
      final sala = it.container.read(salaSessionProvider.notifier);
      sala.goEnsaio();
      await _assentar(tester);
      expect(
        find.text(_conferida),
        findsNothing,
        reason: 'a casa dizia conferida sem a sala ter conferido',
      );

      it.harness.room.retroSoFar = const BackTranslationProgress(checked: true);
      sala.goEnsaio();
      await _assentar(tester);
      expect(find.text(_conferida), findsOneWidget);
      it.harness.room.holdNextState();
      sala.ensaioTap();
      sala.ensaioTap();
      await tester.pump(const Duration(milliseconds: 100));
      sala.takeKeep();
      await tester.pump(const Duration(seconds: 3));

      expect(
        find.text(_conferida),
        findsNothing,
        reason: 'a gravação nova ficava dita conferida antes da sala ler',
      );
      it.harness.room.finishHeldState();
      await tester.pump(const Duration(seconds: 1));
      closeTheRoom(it.container);
    });

    testWidgets('a checked, unapproved draft: the tap approves in silence', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      final falasAntes = it.harness.voice.fixedLines.length;

      await _tocar(tester);

      expect(find.text(_ensaioSalvo), findsOneWidget);
      expect(it.harness.voice.fixedLines.skip(falasAntes), isEmpty);
      expect(it.harness.room.releasesAsked, hasLength(1));

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_badge), findsOneWidget);
      expect(byLabel('Checagem externa'), findsOneWidget);
      expect(byLabel(_aprovar), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('«Checagem externa» on the home opens the external check', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(byLabel('Checagem externa'));
      await tester.tap(byLabel('Checagem externa'));
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);

      expect(it.harness.room.externalChecksOpened, hasLength(1));
      expect(byLabel('Novo ouvinte'), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('leaving the external check opened from the home returns to '
        'the home and keeps the home as the resume point', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byLabel('Checagem externa'));
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);

      it.harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      it.container.read(salaSessionProvider.notifier).leaveTheExternalCheck();
      await _assentar(tester);

      expect(
        it.harness.room.failStateOnceWith,
        isNotNull,
        reason: 'the home reads no telling-back on the way out',
      );
      expect(it.container.read(salaSessionProvider).stage, SalaStage.ensaio);
      expect(it.harness.emAberto.rows['Ruth/P01/pt']?.stage, SalaStage.ensaio);
      closeTheRoom(it.container);
    });

    for (final (what, blockers, failure, text, offered, answer) in [
      (
        'not checked',
        ['telling_back_not_checked'],
        null,
        _precisaConferida,
        false,
        null,
      ),
      ('an unknown code', ['coisa_nova'], null, _naoDeu, true, null),
      (
        'neither a version nor a refusal',
        <String>[],
        null,
        _naoDeu,
        true,
        ApprovalAnswer(),
      ),
      (
        'an untold stretch before an unheard part',
        ['playback_did_not_cover_the_clip', 'untold_stretch'],
        null,
        _precisaConferida,
        false,
        null,
      ),
      (
        'a part unheard',
        ['playback_did_not_cover_the_clip'],
        null,
        _faltaOuvir,
        true,
        null,
      ),
      (
        'the server cannot answer',
        <String>[],
        NetworkFailed('sem rede'),
        _naoDeu,
        true,
        null,
      ),
    ]) {
      testWidgets('a refusal on the home says one of her three texts: $what', (
        tester,
      ) async {
        final it = await aCasaConferida(tester);
        it.harness.room
          ..releaseBlockers = blockers
          ..failReleaseWith = failure;
        if (answer != null) it.harness.room.release = answer;
        final tocadas = it.harness.playback.played.length;

        await _tocar(tester);

        expect(find.text(text), findsOneWidget);
        expect(byLabel(_aprovar).evaluate().isNotEmpty, offered);
        expect(it.container.read(salaSessionProvider).stage, SalaStage.ensaio);
        expect(it.harness.playback.played, hasLength(tocadas));
        closeTheRoom(it.container);
      });
    }

    testWidgets('a refusal text stays on the home it was said on', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      it.harness.room.releaseBlockers = const ['telling_back_not_checked'];
      await _tocar(tester);
      expect(find.text(_precisaConferida), findsOneWidget);

      it.container.read(salaSessionProvider.notifier).startRetro();
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);

      expect(find.text(_precisaConferida), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('a kept take clears the refusal text on the home', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      it.harness.room.releaseBlockers = const ['telling_back_not_checked'];
      await _tocar(tester);
      final sala = it.container.read(salaSessionProvider.notifier);

      sala.ensaioTap();
      sala.ensaioTap();
      await tester.pump(const Duration(milliseconds: 100));
      sala.takeKeep();
      await tester.pump(const Duration(seconds: 3));

      expect(find.text(_precisaConferida), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('a grain switch takes the offer away', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.holdNextState();

      it.container
          .read(salaSessionProvider.notifier)
          .recordTheWholePassageInstead();
      await _assentar(tester);

      expect(byLabel(_aprovar), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('a draft the room reopens and checks again offers the button '
        'again', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));
      expect(byLabel(_aprovar), findsNothing);

      it.harness.room
        ..approvedDraft = null
        ..retroSoFar = const BackTranslationProgress();
      final sala = it.container.read(salaSessionProvider.notifier);
      sala.goEnsaio();
      await _assentar(tester);

      expect(byLabel(_aprovar), findsNothing);

      it.harness.room.retroSoFar = const BackTranslationProgress(checked: true);
      sala.goEnsaio();
      await _assentar(tester);

      expect(byLabel(_aprovar), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('no approval, no external check', (tester) async {
      final it = await aCasaConferida(tester);

      it.container.read(salaSessionProvider.notifier).abrirAChecagemExterna();
      await _assentar(tester);

      expect(it.harness.room.externalChecksOpened, isEmpty);
      closeTheRoom(it.container);
    });

    testWidgets('no offer while a take is being recorded', (tester) async {
      final it = await aCasaConferida(tester);

      it.container.read(salaSessionProvider.notifier).ensaioTap();
      await tester.pump(const Duration(milliseconds: 300));

      expect(byLabel(_aprovar), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('the circle does not record while the approval is in the air', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      it.harness.room.holdNextRelease();
      await _tocar(tester);

      it.container.read(salaSessionProvider.notifier).ensaioTap();
      await tester.pump(const Duration(milliseconds: 300));
      it.harness.room.finishHeldRelease();
      await tester.pump(const Duration(milliseconds: 300));

      expect(it.container.read(salaSessionProvider).ensaio, EnsaioStatus.idle);
      closeTheRoom(it.container);
    });

    testWidgets('a kept take takes the offer away until the room reads again', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      final sala = it.container.read(salaSessionProvider.notifier);
      it.harness.room.holdNextState();
      sala.ensaioTap();
      sala.ensaioTap();
      await tester.pump(const Duration(milliseconds: 100));
      sala.takeKeep();
      await tester.pump(const Duration(seconds: 3));

      expect(byLabel(_aprovar), findsNothing);
      it.harness.room.finishHeldState();
      await tester.pump(const Duration(seconds: 1));
      expect(byLabel(_aprovar), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('an approved draft: no button', (tester) async {
      final it = await _ateAConferida(tester);
      it.harness.room
        ..retroSoFar = const BackTranslationProgress(checked: true)
        ..approvedDraft = const ApprovedDraft(version: 1);
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await _assentar(tester);

      expect(byLabel(_aprovar), findsNothing);
      expect(find.text(_badge), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('a passage the room has not checked: no button', (
      tester,
    ) async {
      final it = await _ateAConferida(tester);
      it.harness.room.retroSoFar = const BackTranslationProgress();
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await _assentar(tester);
      expect(byLabel(_aprovar), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets('an English session: «Approve as the final draft», silent', (
      tester,
    ) async {
      final it = await aCasaConferida(tester, lingua: 'en');
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      final falasAntes = it.harness.voice.fixedLines.length;

      await _tocar(tester, 'Approve as the final draft');

      expect(find.text('Rehearsal saved'), findsOneWidget);
      expect(it.harness.voice.fixedLines.skip(falasAntes), isEmpty);
      closeTheRoom(it.container);
    });
  });
}
