import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/check_doctrine.dart';
import '../tool/doctrine_allowlist.dart';

void main() {
  test('the guard finds every bridgeMode site the allowlist already names',
      () {
    final hits = scan(const ['lib']);
    final result = evaluate(hits, allowlist);

    expect(
      hits.length,
      10,
      reason: 'as dez linhas de bridgeMode conhecidas hoje mudaram de número',
    );
    expect(
      result.violations,
      isEmpty,
      reason: 'um site de bridgeMode fora da allowlist deveria falhar a build',
    );
    expect(
      result.stale,
      isEmpty,
      reason: 'uma entrada da allowlist não bate mais nenhuma linha real',
    );
  });

  test(
      'an allowlist entry the scan can no longer confirm is reported stale, '
      'and the reworded line is its own new violation', () {
    final dir = Directory.systemTemp.createTempSync('doctrine_fixture_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'reworded.dart')).writeAsStringSync(
      "const _mode = 'guided_microchecks reworded';\n",
    );

    final staleEntry = AllowlistEntry(
      p.posix.joinAll(p.split(p.relative(p.join(dir.path, 'reworded.dart')))),
      Rule.mode,
      "const _mode = 'guided_microchecks';",
    );

    final result = evaluate(scan([dir.path]), [staleEntry]);

    expect(
      result.stale,
      [staleEntry],
      reason: 'a entrada antiga não bate mais nenhuma linha real, virou stale',
    );
    expect(
      result.violations,
      hasLength(1),
      reason: 'a linha reescrita é uma violação nova, não coberta pela allowlist',
    );
    expect(
      result.violations.single.text,
      "const _mode = 'guided_microchecks reworded';",
      reason: 'a violação precisa apontar para o texto atual, não o antigo',
    );
  });
}
