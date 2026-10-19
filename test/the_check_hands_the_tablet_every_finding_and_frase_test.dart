import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

const _findings = [
  {'kind': 'addition', 'frase': 2, 'segment_id': 'trecho-2'},
  {'kind': 'missing', 'frase': 3, 'segment_id': 'trecho-4'},
  {'kind': 'unclear', 'frase': null, 'segment_id': null},
  {'kind': 'nuance', 'frase': 1, 'segment_id': 'trecho-1'},
];

const _read = [
  (BtFindingKind.addition, 2, 'trecho-2'),
  (BtFindingKind.missing, 3, 'trecho-4'),
  (BtFindingKind.unclear, null, null),
  (null, 1, 'trecho-1'),
];

List<(BtFindingKind?, int?, String?)> _asRead(List<BtFinding> findings) => [
  for (final finding in findings)
    (finding.kind, finding.frase, finding.segmentId),
];

void main() {
  test('the verdict answer hands over every finding of the check in its '
      'order, not only the one that leads', () {
    final verdict = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'finding_segment_id': 'trecho-2',
      'findings': _findings,
      'findings_remaining': 3,
    });

    expect(
      _asRead(verdict.findings),
      _read,
      reason:
          'o app lia só o achado que liderava, e os outros não deixavam '
          'marca nenhuma na tela',
    );
  });

  test('the session read hands over the findings that still stand, so a '
      'team that comes back sees them again', () {
    final snapshot = SessionSnapshot.fromJson(const {
      'session_id': 'sessao-1',
      'back_translation': {
        'segments': <Object>[],
        'checked': false,
        'findings': _findings,
      },
    });

    expect(
      _asRead(snapshot.backTranslation.findings),
      _read,
      reason: 'a leitura da sessão jogava fora a lista de achados',
    );
  });

  test('a server that sends no findings is an empty list, never a crash', () {
    final verdict = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': true,
      'findings_remaining': 0,
    });
    final snapshot = SessionSnapshot.fromJson(const {
      'session_id': 'sessao-1',
      'back_translation': {'segments': <Object>[]},
    });

    expect(verdict.findings, isEmpty);
    expect(snapshot.backTranslation.findings, isEmpty);
  });

  test('a stretch carries the frase number the voice says, and an untold '
      'piece carries none', () {
    final segments = SegmentView.listFrom(const {
      'segments': [
        {
          'segment_id': 'trecho-1',
          'take_id': 'parte-1',
          'starts_ms': 0,
          'ends_ms': 4000,
          'told': true,
          'frase': 1,
        },
        {
          'segment_id': 'trecho-2',
          'take_id': 'parte-1',
          'starts_ms': 4000,
          'ends_ms': 6000,
          'told': false,
          'frase': null,
        },
        {
          'segment_id': 'trecho-3',
          'take_id': 'parte-2',
          'starts_ms': 0,
          'ends_ms': 3000,
          'told': true,
          'frase': 2,
        },
      ],
    });

    expect(
      [for (final segment in segments) segment.frase],
      [1, null, 2],
      reason:
          'o app numerava as frases por conta própria, e a «frase 2» da voz '
          'podia ser outra barra na tela',
    );
  });

  test('a frase just told carries its number in the answer, before any '
      'read of the session', () {
    expect(
      BackTranslationChunk.fromJson(const {'frase': 4}).frase,
      4,
      reason: 'a resposta da frase não trazia número nenhum',
    );
    expect(BackTranslationChunk.fromJson(const {}).frase, isNull);
  });
}
