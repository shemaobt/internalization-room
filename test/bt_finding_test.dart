import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

void main() {
  test('every wire name the server can send resolves to a kind', () {
    const wire = {
      'missing': BtFindingKind.missing,
      'addition': BtFindingKind.addition,
      'unclear': BtFindingKind.unclear,
    };
    wire.forEach((raw, kind) {
      expect(btFindingKindFrom(raw), kind);
    });
  });

  test('the enum and the wire map are the same three members', () {
    expect(BtFindingKind.values, [
      BtFindingKind.missing,
      BtFindingKind.addition,
      BtFindingKind.unclear,
    ]);
  });

  test('a kind this build does not know yet degrades to null, not a crash', () {
    expect(btFindingKindFrom('algo_novo_do_servidor'), isNull);
    expect(btFindingKindFrom(null), isNull);
  });

  for (final retired in [
    'meaning_change',
    'wrong_relation',
    'reordered_event',
    'preservation_violation',
    'insufficient_evidence',
  ]) {
    test('a retired wire name, $retired, resolves to no kind', () {
      expect(btFindingKindFrom(retired), isNull);

      final verdict = BackTranslationVerdict.fromJson({
        'checked': false,
        'finding_kind': retired,
        'finding_segment_id': 'trecho-2',
        'findings_remaining': 1,
      });

      expect(verdict.findingKind, isNull);
      expect(verdict.findingSegmentId, 'trecho-2');
    });
  }

  test('a verdict with an unknown kind still enters the findings phase', () {
    final verdict = BackTranslationVerdict.fromJson(const {
      'checked': false,
      'finding_kind': 'algo_novo_do_servidor',
      'finding_segment_id': 'trecho-2',
      'findings_remaining': 1,
    });

    expect(verdict.checked, isFalse);
    expect(verdict.findingKind, isNull);
    expect(verdict.findingSegmentId, 'trecho-2');
  });
}
