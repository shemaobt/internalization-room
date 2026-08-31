import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

void main() {
  test('every wire name the server can send resolves to a kind', () {
    const wire = {
      'missing': BtFindingKind.missing,
      'addition': BtFindingKind.addition,
      'meaning_change': BtFindingKind.meaningChange,
      'wrong_relation': BtFindingKind.wrongRelation,
      'reordered_event': BtFindingKind.reorderedEvent,
      'preservation_violation': BtFindingKind.preservationViolation,
      'insufficient_evidence': BtFindingKind.insufficientEvidence,
      'unclear': BtFindingKind.unclear,
    };
    wire.forEach((raw, kind) {
      expect(btFindingKindFrom(raw), kind);
    });
  });

  test('a kind this build does not know yet degrades to null, not a crash', () {
    expect(btFindingKindFrom('algo_novo_do_servidor'), isNull);
    expect(btFindingKindFrom(null), isNull);
  });

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
