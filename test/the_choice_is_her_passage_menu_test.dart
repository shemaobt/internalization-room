import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/book_names.dart';
import 'package:internalization_room/features/sala/domain/device_link.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

const _ruthPanorama = Passagem(
  pericope: 'panorama',
  audioUrl: '/voice/panorama',
  kind: PassagemKind.panorama,
  book: 'Ruth',
);
const _p01 = Passagem(
  pericope: 'P01',
  audioUrl: '/voice/p01',
  book: 'Ruth',
  reference: 'Ruth 1:1–5',
);
const _p02 = Passagem(
  pericope: 'P02',
  audioUrl: '/voice/p02',
  book: 'Ruth',
  reference: 'Ruth 1:6–14',
);
const _p03 = Passagem(
  pericope: 'P03',
  audioUrl: '/voice/p03',
  book: 'Ruth',
  reference: 'Ruth 1:15–18',
);
const _ruth = [_ruthPanorama, _p01, _p02, _p03];

const _panoramaPt = '◈ Panorama do Livro';

Future<ProviderContainer> _theChoice(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await pumpSala(tester, harness);
  await _catchUp(tester);
  return container;
}

Future<void> _catchUp(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(milliseconds: 1500));
}

SalaHarness _aRoomListing(List<Passagem> entries) =>
    SalaHarness(filaEmMemoria: true)..room.passages = entries;

Finder _pill(String words) => find
    .ancestor(
      of: find.text(words),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).border != null,
      ),
    )
    .first;

bool _tinted(WidgetTester tester, String words) {
  final decoration =
      tester.widget<DecoratedBox>(_pill(words)).decoration as BoxDecoration;
  return decoration.color == ShemaBrand.azul.withValues(alpha: 0.18);
}

List<String> _everyPill(WidgetTester tester) => [
  for (final words in [_panoramaPt, '◈ Book Panorama', ..._references])
    if (find.text(words).evaluate().isNotEmpty) words,
];

const _references = [
  'Rute 1:1–5',
  'Rute 1:6–14',
  'Rute 1:15–18',
  'Ruth 1:1–5',
  'Ruth 1:6–14',
  'Ruth 1:15–18',
];

Future<void> _leave(WidgetTester tester, ProviderContainer container) async {
  container.read(salaSessionProvider.notifier).leaveThePassage();
  await _catchUp(tester);
}

void menuTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      final voiceOver = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        voiceOver.dispose();
      }
    });

void main() {
  menuTest(
    'the Choice shows «Escolha a passagem» and one block per book, headed «Ester», '
    '«Jonas», «Rute», each starting with «◈ Panorama do Livro»',
    (tester) async {
      await _theChoice(
        tester,
        _aRoomListing(const [
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/esther',
            kind: PassagemKind.panorama,
            book: 'Esther',
          ),
          Passagem(
            pericope: 'E01',
            audioUrl: '/voice/e01',
            book: 'Esther',
            reference: 'Esther 1:1-9',
          ),
          Passagem(
            pericope: 'panorama',
            audioUrl: '/voice/jonah',
            kind: PassagemKind.panorama,
            book: 'Jonah',
          ),
          Passagem(
            pericope: 'J01',
            audioUrl: '/voice/j01',
            book: 'Jonah',
            reference: 'Jonah 1:1-3',
          ),
          _ruthPanorama,
          _p01,
        ]),
      );

      final panoramas = find.text(_panoramaPt);
      final topToBottom = [
        find.text('Escolha a passagem'),
        find.text('ESTER'),
        panoramas.at(0),
        find.text('Ester 1:1-9'),
        find.text('JONAS'),
        panoramas.at(1),
        find.text('Jonas 1:1-3'),
        find.text('RUTE'),
        panoramas.at(2),
        find.text('Rute 1:1–5'),
      ];
      final heights = [
        for (final words in topToBottom) tester.getTopLeft(words).dy,
      ];
      expect(heights, orderedEquals([...heights]..sort()));
      expect(
        heights.toSet(),
        hasLength(heights.length),
        reason: 'cada linha do menu fica abaixo da anterior',
      );
      for (final book in ['Ester', 'Jonas', 'Rute']) {
        expect(find.bySemanticsLabel(book), findsOneWidget);
      }
    },
  );

  menuTest(
    'a book\'s block lists its passages in story order with the reference only',
    (tester) async {
      await _theChoice(tester, _aRoomListing(_ruth));

      final places = [
        for (final words in ['Rute 1:1–5', 'Rute 1:6–14', 'Rute 1:15–18'])
          tester.getTopLeft(find.text(words)),
      ];
      final readingOrder = [...places]
        ..sort(
          (a, b) => a.dy != b.dy ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
        );
      expect(places, readingOrder, reason: 'as passagens na ordem da história');
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        unorderedEquals([
          'Escolha a passagem',
          'RUTE',
          _panoramaPt,
          'Rute 1:1–5',
          'Rute 1:6–14',
          'Rute 1:15–18',
          'PT',
          'EN',
        ]),
      );
    },
  );

  menuTest(
    'a passage approved as the final draft wears «●», read «tem um ensaio salvo»',
    (tester) async {
      await _theChoice(
        tester,
        _aRoomListing(const [
          _ruthPanorama,
          Passagem(
            pericope: 'P01',
            audioUrl: '/voice/p01',
            book: 'Ruth',
            reference: 'Ruth 1:1–5',
            approved: true,
          ),
          _p02,
          _p03,
        ]),
      );

      expect(
        find.descendant(of: _pill('Rute 1:1–5'), matching: find.text('●')),
        findsOneWidget,
      );
      expect(find.text('●'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('tem um ensaio salvo')),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: _pill('Rute 1:1–5'),
          matching: find.bySemanticsLabel(RegExp('tem um ensaio salvo')),
        ),
        findsOneWidget,
      );
    },
  );

  menuTest('a passage begun but not approved wears no mark', (tester) async {
    final harness = _aRoomListing(_ruth);
    harness.emAberto.rows['Ruth/P02/pt'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.conversa,
    );
    final container = await _theChoice(tester, harness);

    expect(container.read(salaSessionProvider).comecadas, contains('P02'));
    expect(
      find.descendant(of: _pill('Rute 1:6–14'), matching: find.text('●')),
      findsNothing,
    );
    expect(_tinted(tester, 'Rute 1:6–14'), isFalse);
  });

  menuTest('one tap on «Rute 1:6–14» opens that passage\'s session at once', (
    tester,
  ) async {
    final harness = _aRoomListing(_ruth);
    final container = await _theChoice(tester, harness);

    await tester.tap(find.text('Rute 1:6–14'));
    await tester.pump();

    expect(container.read(salaSessionProvider).stage, isNot(SalaStage.escolha));

    await _catchUp(tester);

    expect(harness.room.pericopesAsked, ['P02']);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);
  });

  menuTest('one tap on «◈ Panorama do Livro» opens the book\'s Panorama', (
    tester,
  ) async {
    final container = await _theChoice(tester, _aRoomListing(_ruth));

    await tester.tap(find.text(_panoramaPt));
    await _catchUp(tester);

    expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
  });

  menuTest(
    'the entry left wears the tint when its Session language is the Room language',
    (tester) async {
      final container = await _theChoice(tester, _aRoomListing(_ruth));

      await tester.tap(find.text('Rute 1:6–14'));
      await _catchUp(tester);
      await _leave(tester, container);

      expect(_everyPill(tester).where((words) => _tinted(tester, words)), [
        'Rute 1:6–14',
      ]);

      await tester.tap(find.text(_panoramaPt));
      await _catchUp(tester);
      await _leave(tester, container);

      expect(_everyPill(tester).where((words) => _tinted(tester, words)), [
        _panoramaPt,
      ]);
    },
  );

  menuTest(
    'a Portuguese entry left keeps its tint when the team taps «EN», the '
    'Panorama too',
    (tester) async {
      final container = await _theChoice(tester, _aRoomListing(_ruth));
      await tester.tap(find.text('Rute 1:6–14'));
      await _catchUp(tester);
      await _leave(tester, container);

      await tester.tap(find.text('EN'));
      await _catchUp(tester);

      expect(
        _everyPill(tester).where((words) => _tinted(tester, words)),
        ['Ruth 1:6–14'],
        reason: 'a passagem deixada em português perdia a cor na lista inglesa',
      );

      await tester.tap(find.text('PT'));
      await _catchUp(tester);
      await tester.tap(find.text(_panoramaPt));
      await _catchUp(tester);
      await _leave(tester, container);
      await tester.tap(find.text('EN'));
      await _catchUp(tester);

      expect(
        _everyPill(tester).where((words) => _tinted(tester, words)),
        ['◈ Book Panorama'],
        reason: 'o panorama deixado em português perdia a cor na lista inglesa',
      );
    },
  );

  menuTest(
    'an English entry left keeps its tint while the Room language is Portuguese',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true, lingua: null)
        ..room.passages = _ruth;
      final container = await _theChoice(tester, harness);
      await tester.tap(find.text('EN'));
      await _catchUp(tester);
      await tester.tap(find.text('Ruth 1:6–14'));
      await _catchUp(tester);
      await _leave(tester, container);

      await tester.tap(find.text('PT'));
      await _catchUp(tester);

      expect(
        _everyPill(tester).where((words) => _tinted(tester, words)),
        ['Rute 1:6–14'],
        reason: 'a passagem deixada em inglês perdia a cor na lista portuguesa',
      );
      expect(byLabel(roomLabelFor('backToPassage', 'pt')), findsOneWidget);

      await tester.tap(find.text('EN'));
      await _catchUp(tester);

      expect(_everyPill(tester).where((words) => _tinted(tester, words)), [
        'Ruth 1:6–14',
      ]);
    },
  );

  menuTest('the menu speaks the Room language in her words', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: null)
      ..room.passages = const [
        _ruthPanorama,
        Passagem(
          pericope: 'P01',
          audioUrl: '/voice/p01',
          book: 'Ruth',
          reference: 'Ruth 1:1–5',
          approved: true,
        ),
      ];
    await _theChoice(tester, harness);

    await tester.tap(find.text('EN'));
    await _catchUp(tester);

    expect(find.text('Choose the Passage'), findsOneWidget);
    expect(find.text('RUTH'), findsOneWidget);
    expect(find.bySemanticsLabel('Ruth'), findsOneWidget);
    expect(find.text('◈ Book Panorama'), findsOneWidget);
    expect(find.text('Ruth 1:1–5'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('has a saved rehearsal')),
      findsOneWidget,
    );
  });

  menuTest('the menu offers exactly the entries the room lists', (
    tester,
  ) async {
    await _theChoice(
      tester,
      _aRoomListing(const [
        _p01,
        Passagem(
          pericope: 'P05',
          audioUrl: '/voice/p05',
          book: 'Ruth',
          reference: 'Ruth 2:1–7',
        ),
      ]),
    );

    expect(find.text('Rute 1:1–5'), findsOneWidget);
    expect(find.text('Rute 2:1–7'), findsOneWidget);
    expect(find.textContaining('Panorama'), findsNothing);
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => text.data!.startsWith('Rute ')),
      hasLength(2),
    );
  });

  menuTest('a reference written with a hyphen is shown as written', (
    tester,
  ) async {
    await _theChoice(
      tester,
      _aRoomListing(const [
        Passagem(
          pericope: 'P06',
          audioUrl: '/voice/p06',
          book: 'Ruth',
          reference: 'Ruth 2:8-16',
        ),
      ]),
    );

    expect(find.text('Rute 2:8-16'), findsOneWidget);
  });

  group('a book\'s name is hers in the Room language, and a book she never '
      'named keeps the room\'s name', () {
    test('Esther is «Ester» in Portuguese and Esther in English', () {
      expect(bookNameFor('Esther', 'pt'), 'Ester');
      expect(bookNameFor('Esther', 'en'), 'Esther');
    });

    test('Jonah is «Jonas» and Song is «Cânticos»', () {
      expect(bookNameFor('Jonah', 'pt'), 'Jonas');
      expect(bookNameFor('Song', 'pt'), 'Cânticos');
    });

    test('Tobit stays Tobit in both languages', () {
      expect(bookNameFor('Tobit', 'pt'), 'Tobit');
      expect(bookNameFor('Tobit', 'en'), 'Tobit');
    });

    test('a reference renames only its book', () {
      expect(referenceFor('Song 2:1-7', 'pt'), 'Cânticos 2:1-7');
      expect(referenceFor('Ruth 1:6–14', 'en'), 'Ruth 1:6–14');
    });
  });

  menuTest('opening the Choice says no passage aloud', (tester) async {
    final harness = _aRoomListing(_ruth);
    final container = await _theChoice(tester, harness);

    expect(container.read(salaSessionProvider).naRoda, _ruth);
    expect(harness.voice.played, isEmpty);
    expect(harness.voice.fetched, isEmpty);
    expect(byLabel('Entrar nesta passagem'), findsNothing);
    expect(byLabel('Ouvir esta passagem de novo'), findsNothing);
  });

  menuTest(
    'while the Wheel cannot be read, the mark and the title stand over an empty '
    'list, and the next open of the Choice fills it in place',
    (tester) async {
      final harness =
          SalaHarness(
              filaEmMemoria: true,
              retryBackoff: const [Duration(hours: 1)],
              linkedAs: const RememberedLink(
                deviceId: 'aparelho-1',
                team: TeamLink(projectId: 'equipe-1'),
                credential: 'credencial-1',
              ),
            )
            ..room.passages = _ruth
            ..room.reachable = false;
      final container = await _theChoice(tester, harness);

      expect(find.text('Rute 1:1–5'), findsNothing);
      expect(find.text('Escolha a passagem'), findsOneWidget);
      expect(find.byType(FacilitatorCircle), findsNothing);

      harness.room.reachable = true;
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await _catchUp(tester);

      expect(find.text('Rute 1:1–5'), findsOneWidget);
    },
  );

  menuTest('under a call for a person the books give way', (tester) async {
    final harness = _aRoomListing(_ruth);
    final container = await _theChoice(tester, harness);
    final where = tester.getCenter(find.text('Rute 1:6–14'));

    container.read(salaSessionProvider.notifier).haltForABrokenBuild();
    await _catchUp(tester);

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(find.text('Rute 1:6–14'), findsNothing);

    await tester.tapAt(where);
    await _catchUp(tester);

    expect(harness.room.pericopesAsked, isEmpty);
    expect(harness.room.calls, isNot(contains('createSession')));
  });

  menuTest('nothing is tinted after the tablet is relaunched', (tester) async {
    final harness = _aRoomListing(_ruth);
    final container = await _theChoice(tester, harness);
    await tester.tap(find.text('Rute 1:15–18'));
    await _catchUp(tester);
    await _leave(tester, container);
    expect(_tinted(tester, 'Rute 1:15–18'), isTrue);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await _theChoice(tester, harness);

    expect(
      _everyPill(tester).where((words) => _tinted(tester, words)),
      isEmpty,
    );
  });

  menuTest('a zeroed passage loses its mark at the next load', (tester) async {
    final harness = _aRoomListing(const [
      Passagem(
        pericope: 'P01',
        audioUrl: '/voice/p01',
        book: 'Ruth',
        reference: 'Ruth 1:1–5',
        approved: true,
      ),
      _p02,
    ]);
    final container = await _theChoice(tester, harness);
    expect(find.text('●'), findsOneWidget);

    harness.room.passages = const [_p01, _p02];
    await tester.runAsync(
      () => container.read(salaSessionProvider.notifier).abrirEscolha(),
    );
    await _catchUp(tester);

    expect(find.text('●'), findsNothing);
    expect(find.text('Rute 1:1–5'), findsOneWidget);
  });

  menuTest('a tap on the tinted Panorama comes back to it without asking its '
      'opening again', (tester) async {
    final harness = _aRoomListing(_ruth)..room.resumesTheLatest = true;
    final container = await _theChoice(tester, harness);
    await tester.tap(find.text(_panoramaPt));
    await _catchUp(tester);
    await _leave(tester, container);
    final spokenTo = harness.room.sessionsSpokenTo.length;

    await tester.tap(find.text(_panoramaPt));
    await _catchUp(tester);

    expect(container.read(salaSessionProvider).stage, SalaStage.panorama);
    expect(
      harness.room.sessionsSpokenTo,
      hasLength(spokenTo),
      reason: 'voltar ao panorama já ouvido não pede a abertura de novo',
    );
  });

  menuTest('VoiceOver on the Panorama pill reads her words without the glyph', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: null)
      ..room.passages = _ruth;
    await _theChoice(tester, harness);

    expect(find.text(_panoramaPt), findsOneWidget);
    expect(find.bySemanticsLabel('Panorama do Livro'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('◈')), findsNothing);

    await tester.tap(find.text('EN'));
    await _catchUp(tester);

    expect(find.bySemanticsLabel('Book Panorama'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('◈')), findsNothing);
  });
}
