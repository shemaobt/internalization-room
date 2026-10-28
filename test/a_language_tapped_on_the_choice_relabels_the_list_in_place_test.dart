import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart' show Sala;

const _ruth = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
    book: 'Ruth',
  ),
  Passagem(
    pericope: 'P01',
    audioUrl: '/voice/p01',
    book: 'Ruth',
    reference: 'Ruth 1:1–5',
  ),
];

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

Future<Sala> _theListOnScreen(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);
  await it.sala.abrirEscolha();
  await waitFor('the list to stand on screen', () => it.estado.entriesOpen);
  return it;
}

Finder get _theCircle => find.descendant(
  of: find.byType(EscolhaView),
  matching: find.byType(FacilitatorCircle),
);

bool _tinted(WidgetTester tester, String words) {
  final pill = find
      .ancestor(of: find.text(words), matching: find.byType(DecoratedBox))
      .first;
  final decoration = tester.widget<DecoratedBox>(pill).decoration;
  return (decoration as BoxDecoration).color ==
      ShemaBrand.azul.withValues(alpha: 0.18);
}

void main() {
  testWidgets(
    'tapping «EN» and then «PT» rewrites the list where it stands, never behind '
    'a thinking circle',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)..room.passages = _ruth;
      await pumpSala(tester, harness);
      await _catchUp(tester);

      harness.room.holdNextBooks();
      await tester.tap(find.text('EN'));
      await tester.pump();

      expect(find.text('Choose the Passage'), findsOneWidget);
      expect(find.text('RUTH'), findsOneWidget);
      expect(find.text('◈ Book Panorama'), findsOneWidget);
      expect(
        find.text('Ruth 1:1–5'),
        findsOneWidget,
        reason:
            'a lista sumia atrás do círculo pensando enquanto a sala relia a roda '
            'na outra língua',
      );
      expect(_theCircle, findsNothing);

      harness.room.holdNextBooks();
      await tester.tap(find.text('PT'));
      await tester.pump();

      expect(find.text('Escolha a passagem'), findsOneWidget);
      expect(find.text('RUTE'), findsOneWidget);
      expect(find.text('◈ Panorama do Livro'), findsOneWidget);
      expect(find.text('Rute 1:1–5'), findsOneWidget);
      expect(_theCircle, findsNothing);
    },
  );

  test(
    'the passages started in the language chosen are read again while the list '
    'stays on screen',
    () async {
      final harness = SalaHarness();
      harness.emAberto.rows['Ruth/P02/en'] = const ResumePoint(
        sessionId: 'sessao-inglesa',
        stage: SalaStage.conversa,
      );
      harness.emAberto.rows['Ruth/P03/pt'] = const ResumePoint(
        sessionId: 'sessao-portuguesa',
        stage: SalaStage.conversa,
      );
      final it = await _theListOnScreen(harness);
      var hidden = 0;
      it.container.listen(salaSessionProvider, (_, after) {
        if (!after.entriesOpen) hidden++;
      });

      it.sala.chooseTheLanguage('en');
      await waitFor(
        'the English passages to be the started ones',
        () => it.estado.comecadas.contains('P02'),
      );
      await settle();

      expect(
        it.estado.comecadas,
        {'P02'},
        reason:
            'a passagem começada só em português continuava marcada na roda '
            'inglesa',
      );
      expect(
        hidden,
        0,
        reason: 'a lista saía da tela para reler o que estava começado',
      );
    },
  );
  test(
    'a language tapped with the room out of reach asks it nothing and raises '
    'nothing',
    () async {
      final harness = SalaHarness();
      final it = await _theListOnScreen(harness);
      final theList = it.estado.naRoda;
      final asked = harness.room.calls.length;
      harness.room.reachable = false;

      it.sala.chooseTheLanguage('en');
      await settle();

      expect(it.container.read(roomLanguageProvider), 'en');
      expect(
        harness.room.calls.skip(asked),
        isEmpty,
        reason: 'trocar a língua relia os livros e as passagens na sala',
      );
      expect(it.estado.naRoda, same(theList));
      expect(it.estado.entriesOpen, isTrue);
      expect(it.estado.needsPerson, isFalse);
    },
  );
  testWidgets(
    'the entry left loses its tint in the other language and gets it back, with '
    'the list on screen all along',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)..room.passages = _ruth;
      final container = await pumpSala(tester, harness);
      await _catchUp(tester);
      await tester.tap(find.text('Rute 1:1–5'));
      await _catchUp(tester);
      container.read(salaSessionProvider.notifier).leaveThePassage();
      await _catchUp(tester);

      expect(_tinted(tester, 'Rute 1:1–5'), isTrue);

      harness.room.holdNextBooks();
      await tester.tap(find.text('EN'));
      await tester.pump();

      expect(find.text('Ruth 1:1–5'), findsOneWidget);
      expect(
        _tinted(tester, 'Ruth 1:1–5'),
        isFalse,
        reason: 'uma sessão portuguesa não é a entrada deixada na roda inglesa',
      );

      harness.room.holdNextBooks();
      await tester.tap(find.text('PT'));
      await tester.pump();

      expect(_tinted(tester, 'Rute 1:1–5'), isTrue);
    },
  );
  test(
    'a read of the started passages that fails leaves the list and its marks as '
    'they were',
    () async {
      final harness = SalaHarness();
      harness.emAberto.rows['Ruth/P03/pt'] = const ResumePoint(
        sessionId: 'sessao-portuguesa',
        stage: SalaStage.conversa,
      );
      final it = await _theListOnScreen(harness);
      final theList = it.estado.naRoda;
      harness.emAberto.startedInFails = const FileSystemException('disco');

      it.sala.chooseTheLanguage('en');
      await settle();

      expect(
        it.estado.naRoda,
        same(theList),
        reason: 'a leitura que falhava deixava a roda vazia atrás do círculo',
      );
      expect(it.estado.comecadas, {'P03'});
      expect(it.estado.entriesOpen, isTrue);
      expect(it.estado.needsPerson, isFalse);
    },
  );
  test(
    'a language tapped on a Wheel that offers nothing asks the room nothing and '
    'never thinks',
    () async {
      final harness = SalaHarness()..room.passages = const [];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await it.sala.abrirEscolha();
      await waitFor(
        'the Wheel to offer nothing',
        () => it.estado.wheelOffersNothing,
      );
      final asked = harness.room.calls.length;
      var thought = 0;
      container.listen(salaSessionProvider, (_, after) {
        if (after.voice == VoiceState.thinking) thought++;
      });

      it.sala.chooseTheLanguage('en');
      await settle();

      expect(harness.room.calls.skip(asked), isEmpty);
      expect(
        thought,
        0,
        reason: 'a roda vazia pensava de novo a cada toque na língua',
      );
      expect(it.estado.voice, VoiceState.invite);
    },
  );
  test(
    'a passage started in English opens where the team stopped after «EN», even '
    'before the started passages are read again',
    () async {
      final harness = SalaHarness();
      harness.emAberto.rows['Ruth/P02/en'] = const ResumePoint(
        sessionId: 'sessao-inglesa',
        stage: SalaStage.conversa,
      );
      final it = await _theListOnScreen(harness);
      harness.emAberto.startedInFails = const FileSystemException('disco');
      it.sala.chooseTheLanguage('en');
      await settle();

      it.sala.openTheEntry(
        it.estado.naRoda!.firstWhere((entry) => entry.pericope == 'P02'),
      );
      await waitFor(
        'the passage to stand open',
        () => it.estado.sessionId != null,
      );

      expect(
        it.estado.sessionId,
        'sessao-inglesa',
        reason:
            'as marcas portuguesas diziam que a P02 não tinha trabalho, o disco nem '
            'era lido e a equipe recomeçava do zero',
      );
    },
  );
}
