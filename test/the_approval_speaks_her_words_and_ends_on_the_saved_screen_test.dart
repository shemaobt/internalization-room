import 'package:flutter/widgets.dart';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
const _ouvirDeNovo = 'Ouvir de novo';
const _ponto = 'Gravar o ensaio de vocês';
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
  bool terminada = false,
}) async {
  final harness = SalaHarness(filaEmMemoria: true, lingua: lingua);
  harness.room.verdictChecked = true;
  harness.room.done = terminada;
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
  sala.gravarACena(1);
  sala.gravarACena(1);
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
  await tester.ensureVisible(byLabel(rotulo));
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
  await _prontoEDeVoltaPeloPonto(tester);
}

Future<void> _prontoEDeVoltaPeloPonto(WidgetTester tester) async {
  await tester.tap(byLabel(_pronto));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(byLabel(_ponto));
  await _assentar(tester);
}

Future<void> _deVoltaATraducao(WidgetTester tester, _Sala it) async {
  it.harness.room.readsChecked = true;
  await _prontoEDeVoltaPeloPonto(tester);
  it.container.read(salaSessionProvider.notifier).startRetro();
  await _assentar(tester);
  it.harness.room.readsChecked = false;
}

Finder _recomecoArmado() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      (widget.properties.label ?? '').startsWith(
        'toque de novo para apagar as',
      ),
);

void main() {
  for (final caso in const [
    (codigo: 'playback_did_not_cover_the_clip', texto: _faltaOuvir),
    (codigo: 'untold_part', texto: _precisaConferida),
    (codigo: 'untold_stretch', texto: _precisaConferida),
  ]) {
    testWidgets(
      'a refusal naming ${caso.codigo} writes «${caso.texto}» and plays '
      'nothing, not the hole it names',
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
        it.harness.room.releaseBlockers = [caso.codigo];

        expect(find.text(caso.texto), findsNothing);
        final sons = it.harness.sounds.length;
        await pressTheApproval(tester, _aprovar);
        await tester.runAsync(() async {
          await waitFor(
            'a recusa acabar de descer',
            () => it.estado.btAprovando == null,
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(find.text(caso.texto), findsOneWidget);
        expect(
          it.harness.sounds.skip(sons),
          isNot(contains('playback:play')),
          reason:
              'a recusa punha no ar a parte ou o trecho que nomeava, e a '
              'gravação começava sozinha onde a dela só escreve o motivo',
        );
        expect(thePersonSign, findsNothing);
        closeTheRoom(it.container);
      },
    );
  }

  for (final codigo in [
    'telling_back_not_checked',
    'telling_back_never_analysed',
    'untold_stretch',
  ]) {
    testWidgets(
      'no clean check on these takes ($codigo): «$_precisaConferida»',
      (tester) async {
        final it = await _ateAConferida(tester);
        it.harness.room.releaseBlockers = [codigo];
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
    'and «$_pronto» lands on the conversation at rest',
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

      final falasAntesDoPronto = it.harness.voice.fixedLines.length;
      final tocadasAntesDoPronto = it.harness.playback.playedFrom.length;
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsNothing);
      expect(
        it.container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'o pronto deixava a equipe na retrotradução, e o dela volta à '
            'conversa',
      );
      expect(byLabel(_ouvirDeNovo), findsOneWidget);
      expect(
        it.container.read(salaSessionProvider).orangeDotLook,
        OrangeDotLook.faint,
        reason: 'a conversa que não terminou volta à vez dela, não ao fim',
      );
      expect(it.harness.voice.fixedLines, hasLength(falasAntesDoPronto));
      expect(it.harness.playback.playedFrom, hasLength(tocadasAntesDoPronto));
      expect(it.harness.emAberto.rows, contains('Ruth/P01/pt'));

      await tester.pump(it.harness.fimLinger + const Duration(seconds: 2));

      expect(it.container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(find.text(_traduzir), findsNothing);
      expect(it.harness.voice.fixedLines, hasLength(falasAntesDoPronto));

      final aberturasAntes = it.harness.room.calls
          .where((call) => call == 'openSession')
          .length;
      final tocadasAntes = it.harness.voice.played.length;
      await tester.tap(byLabel(_ouvirDeNovo));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.harness.room.calls.where((call) => call == 'openSession'),
        hasLength(aberturasAntes),
        reason: 'o clipe do Guia está no tablet: a sala não é chamada',
      );
      expect(
        it.harness.voice.played.skip(tocadasAntes),
        [turnoUrl],
        reason:
            'o ouvir de novo da conversa repetia a fala da aprovação, não a '
            'última do Guia',
      );
      expect(
        it.harness.voice.fixedLines.skip(falasAntesDoPronto),
        isNot(contains(('P3', testLanguage))),
      );
      closeTheRoom(it.container);
    },
  );

  testWidgets('«Done» lands on the conversation, never on the Choice, in '
      'English too', (tester) async {
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
    expect(it.container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(byLabel('Hear that again'), findsOneWidget);
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
      await _prontoEDeVoltaPeloPonto(tester);
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
      it.harness.room.readsChecked = true;
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

  testWidgets('«Pronto» over a conversation the room had ended lands on it at '
      'done, with the orange dot bright', (tester) async {
    final it = await _ateAConferida(tester, terminada: true);
    it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
    await _tocar(tester, _aprovar);
    await tester.tap(byLabel(_pronto));
    await tester.pump(const Duration(milliseconds: 300));

    expect(it.container.read(salaSessionProvider).stage, SalaStage.conversa);
    expect(
      it.container.read(salaSessionProvider).orangeDotLook,
      OrangeDotLook.bright,
      reason:
          'a conversa que a sala já tinha terminado voltava à vez dela, e a '
          'dela volta ao fim',
    );
    closeTheRoom(it.container);
  });

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
        it.harness.room.readsChecked = true;
        await tester.tap(byLabel(pronto));
        await tester.pump(const Duration(milliseconds: 300));
        final sala = it.container.read(salaSessionProvider.notifier);
        sala.openTheEnsaioFinal();
        await _assentar(tester);
        sala.startRetro();
        await _assentar(tester);

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

      await _prontoEDeVoltaPeloPonto(tester);

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

      await _prontoEDeVoltaPeloPonto(tester);

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
    await _deVoltaATraducao(tester, it);

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

  testWidgets('a refusal naming a stretch gives the gestures back', (
    tester,
  ) async {
    final it = await _ateAConferida(tester);
    it.harness.room.releaseBlockers = const ['untold_stretch'];
    await _tocar(tester);

    it.container.read(salaSessionProvider.notifier).recomecarATraducao();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_recomecoArmado(), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    closeTheRoom(it.container);
  });

  for (final (lingua, aprovar) in [
    ('pt', 'Aprovar como rascunho final'),
    ('en', 'Approve as the final draft'),
  ]) {
    testWidgets('the check screen writes «$aprovar» on its approve button, '
        'not a ✓', (tester) async {
      final it = await _ateAConferida(tester, lingua: lingua, aprovar: aprovar);

      expect(
        find.text(aprovar),
        findsOneWidget,
        reason: 'a tela de conferir só tinha um ✓ verde mudo ao lado do ouvir',
      );
      expect(
        tester.widget<Semantics>(byLabel(aprovar)).properties.button,
        isTrue,
      );
      closeTheRoom(it.container);
    });
  }

  testWidgets('with approve on its own line, the listen button sits at the '
      'middle of the check screen', (tester) async {
    final it = await _ateAConferida(tester);

    expect(
      tester.getCenter(byLabel(_ouvir)).dx,
      400,
      reason: 'o espaço do botão que saiu empurrava o ouvir para a esquerda',
    );
    closeTheRoom(it.container);
  });

  for (final (lingua, aprovar) in [
    ('pt', 'Aprovar como rascunho final'),
    ('en', 'Approve as the final draft'),
  ]) {
    testWidgets('on a screen as small as the iPhone SE the $lingua approve '
        'button keeps its margins, on the check screen and on the home', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(375, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final it = await _ateAConferida(tester, lingua: lingua, aprovar: aprovar);

      void nasMargens(String tela) {
        final pilula = tester.getRect(byLabel(aprovar));
        expect(
          pilula.left,
          greaterThanOrEqualTo(16),
          reason: 'na $tela a pílula encostava na borda da tela',
        );
        expect(pilula.right, lessThanOrEqualTo(359), reason: tela);
      }

      nasMargens('tela de conferir');
      it.harness.room.retroSoFar = const BackTranslationProgress(checked: true);
      it.container.read(salaSessionProvider.notifier).goEnsaio();
      await _assentar(tester);
      nasMargens('casa');
      closeTheRoom(it.container);
    });
  }

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

    for (final (lingua, aprovar) in [
      ('pt', 'Aprovar como rascunho final'),
      ('en', 'Approve as the final draft'),
    ]) {
      testWidgets('the home writes «$aprovar» on its approve button, not a '
          'second ✓', (tester) async {
        final it = await aCasaConferida(tester, lingua: lingua);

        expect(
          find.text(aprovar),
          findsOneWidget,
          reason: 'a casa só tinha um ✓ verde mudo ao lado do ✓ de enviar',
        );
        expect(
          tester.widget<Semantics>(byLabel(aprovar)).properties.button,
          isTrue,
        );
        closeTheRoom(it.container);
      });
    }

    testWidgets('the approve button is her pill, her light green under her '
        'white words', (tester) async {
      final it = await aCasaConferida(tester);

      final pilula = tester.widget<Container>(
        find
            .ancestor(of: find.text(_aprovar), matching: find.byType(Container))
            .first,
      );
      final fundo = pilula.decoration! as BoxDecoration;
      expect(
        fundo.color,
        const Color(0xFF777D45),
        reason: 'o botão dela é verde-claro; o nosso era o degradê do enviar',
      );
      expect(fundo.borderRadius, BorderRadius.circular(999));
      expect(
        tester.widget<Text>(find.text(_aprovar)).style?.color,
        const Color(0xFFF6F5EB),
      );
      closeTheRoom(it.container);
    });

    testWidgets('the keep button keeps its round green ✓, and it is the only ✓ '
        'on the home', (tester) async {
      final it = await aCasaConferida(tester);

      expect(
        find.byIcon(LucideIcons.check),
        findsOneWidget,
        reason: 'dois ✓ verdes iguais lado a lado, e a equipe tocava o errado',
      );
      final enviar = tester.widget<RoundActionButton>(
        find.ancestor(
          of: find.byIcon(LucideIcons.check),
          matching: find.byType(RoundActionButton),
        ),
      );
      expect(enviar.semanticLabel, 'Enviar a gravação');
      expect(enviar.gradient, BeadStyles.verde);
      closeTheRoom(it.container);
    });

    testWidgets('a VoiceOver double-tap on the approve button approves, not '
        'only announces it', (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);

      final node = tester.getSemantics(byLabel(_aprovar));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'o VoiceOver anunciava a pílula e o toque duplo não fazia nada',
      );
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          viewId: tester.view.viewId,
          nodeId: node.id,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(it.harness.room.releasesAsked, hasLength(1));
      closeTheRoom(it.container);
      semantics.dispose();
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
      sala.gravarACena(2);
      sala.gravarACena(2);
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
      closeTheRoom(it.container);
    });

    testWidgets('«$_pronto» after the approval from the home lands on the '
        'conversation at rest, not on the home', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      final falasAntesDoPronto = it.harness.voice.fixedLines.length;
      final tocadasAntesDoPronto = it.harness.playback.playedFrom.length;

      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(_ensaioSalvo), findsNothing);
      expect(
        it.container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'o pronto deixava a equipe na casa da gravação, e o dela volta '
            'à conversa',
      );
      expect(byLabel(_ouvirDeNovo), findsOneWidget);
      expect(
        it.container.read(salaSessionProvider).orangeDotLook,
        OrangeDotLook.faint,
        reason: 'a conversa que não terminou volta à vez dela, não ao fim',
      );
      expect(it.harness.voice.fixedLines, hasLength(falasAntesDoPronto));
      expect(it.harness.playback.playedFrom, hasLength(tocadasAntesDoPronto));
      closeTheRoom(it.container);
    });

    testWidgets('a VoiceOver double-tap on «$_pronto» leaves the saved screen '
        'for the conversation, as a finger does', (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);

      voiceOverTap(tester, _pronto);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        it.container.read(salaSessionProvider).stage,
        SalaStage.conversa,
        reason:
            'o VoiceOver anunciava o «Pronto» e o toque duplo deixava a '
            'equipe na tela salva',
      );
      closeTheRoom(it.container);
      semantics.dispose();
    });

    testWidgets('back by the dot after «$_pronto», the home shows its approved '
        'badge and «Checagem externa»', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await tester.tap(byLabel(_pronto));
      await tester.pump(const Duration(milliseconds: 300));
      expect(it.container.read(salaSessionProvider).stage, SalaStage.conversa);

      await tester.tap(byLabel('Gravar o ensaio de vocês'));
      await _assentar(tester);

      expect(it.container.read(salaSessionProvider).stage, SalaStage.ensaio);
      expect(
        find.text(_badge),
        findsOneWidget,
        reason: 'a casa reaberta pelo ponto perdia o selo da aprovação',
      );
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
      await _prontoEDeVoltaPeloPonto(tester);

      await tester.ensureVisible(byLabel('Checagem externa'));
      await tester.tap(byLabel('Checagem externa'));
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);

      expect(it.harness.room.externalChecksOpened, hasLength(1));
      expect(byLabel('Novo ouvinte'), findsOneWidget);
      closeTheRoom(it.container);
    });

    testWidgets('a VoiceOver double-tap on «Checagem externa» on the home '
        'opens the external check', (tester) async {
      final semantics = tester.ensureSemantics();
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await _prontoEDeVoltaPeloPonto(tester);

      voiceOverTap(tester, 'Checagem externa');
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);

      expect(
        it.harness.room.externalChecksOpened,
        hasLength(1),
        reason:
            'o VoiceOver anunciava o botão da casa e o toque duplo não abria '
            'a checagem',
      );
      closeTheRoom(it.container);
      semantics.dispose();
    });

    testWidgets('leaving the external check opened from the home returns to '
        'the home and keeps the home as the resume point', (tester) async {
      final it = await aCasaConferida(tester);
      it.harness.room.approvedDraft = const ApprovedDraft(version: 1);
      await _tocar(tester);
      await _prontoEDeVoltaPeloPonto(tester);
      await tester.ensureVisible(byLabel('Checagem externa'));
      await tester.tap(byLabel('Checagem externa'));
      await tester.pump(const Duration(milliseconds: 300));
      await _assentar(tester);
      expect(
        it.harness.room.externalChecksOpened,
        hasLength(1),
        reason:
            'o toque caía abaixo da janela e o teste passava pelas chamadas '
            'ao notifier depois dele',
      );

      it.harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      it.container.read(salaSessionProvider.notifier).leaveTheExternalCheck();
      await _assentar(tester);

      expect(
        it.harness.room.failStateOnceWith,
        isNull,
        reason:
            'a saída para a casa não relia a sessão, e a dela relê no exitExt',
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

      sala.gravarACena(2);
      sala.gravarACena(2);
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
      await _prontoEDeVoltaPeloPonto(tester);
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

      it.container.read(salaSessionProvider.notifier).gravarACena(2);
      await tester.pump(const Duration(milliseconds: 300));

      expect(byLabel(_aprovar), findsNothing);
      closeTheRoom(it.container);
    });

    testWidgets(
      'a Scene row does not record while the approval is in the air',
      (tester) async {
        final it = await aCasaConferida(tester);
        it.harness.room.holdNextRelease();
        await _tocar(tester);
        expect(
          it.harness.room.releasesAsked,
          isNotEmpty,
          reason: 'o caso só mede alguma coisa com a aprovação no ar',
        );
        final antes = it.harness.recorder.captures;
        final gravarNaCena2 = find.descendant(
          of: linhaDoEnsaio(2),
          matching: byLabel('Gravar'),
        );

        await tester.ensureVisible(gravarNaCena2);
        await tester.tap(gravarNaCena2, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        it.harness.room.finishHeldRelease();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          it.container.read(salaSessionProvider).ensaio,
          EnsaioStatus.idle,
        );
        expect(it.harness.recorder.captures, antes);
        closeTheRoom(it.container);
      },
    );

    testWidgets('a kept take takes the offer away until the room reads again', (
      tester,
    ) async {
      final it = await aCasaConferida(tester);
      final sala = it.container.read(salaSessionProvider.notifier);
      it.harness.room.holdNextState();
      sala.gravarACena(2);
      sala.gravarACena(2);
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
