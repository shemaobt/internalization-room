import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/check_doctrine.dart';
import '../tool/doctrine_allowlist.dart';

void _expectAFixtureViolatingOneRule(
  String label,
  Rule rule,
  String triggerLine,
) {
  test(
      'a $label mechanism reintroduced outside the allowlist fails with '
      "its doctrine sentence", () {
    final dir = Directory.systemTemp.createTempSync('doctrine_fixture_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'reintroduced.dart'))
        .writeAsStringSync('$triggerLine\n');

    final result = evaluate(scan([dir.path]), allowlist);

    expect(
      result.violations,
      hasLength(1),
      reason: 'o gatilho de $label deveria bater uma vez, nenhuma allowlist cobre um arquivo novo',
    );
    expect(
      result.violations.single.rule,
      rule,
      reason: 'a violação precisa vir da regra $label, não de outra',
    );
  });
}

void main() {
  test('the guard finds every bridgeMode site the allowlist already names',
      () {
    final hits = scan(const ['lib']);
    final result = evaluate(hits, allowlist);
    final modeHits = hits.where((h) => h.rule == Rule.mode).toList();

    expect(
      modeHits,
      hasLength(10),
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

  test('the guard finds the two turn-clock declarations, matching the allowlist',
      () {
    final result = evaluate(scan(const ['lib']), allowlist);
    final ceilingHits =
        scan(const ['lib']).where((h) => h.rule == Rule.ceiling).toList();

    expect(
      ceilingHits,
      hasLength(2),
      reason: 'só _turnTimeout e busyStateCeilingProvider são o relógio do turno',
    );
    expect(
      ceilingHits.any((h) => h.text.contains('_stateTimeout')),
      isFalse,
      reason: '_stateTimeout não é o caminho do turno, não deveria bater',
    );
    expect(
      result.violations,
      isEmpty,
      reason: 'um relógio de turno fora da allowlist deveria falhar a build',
    );
    expect(
      result.stale,
      isEmpty,
      reason: 'as duas entradas de ceiling ainda batem o código real',
    );
  });

  _expectAFixtureViolatingOneRule(
    'probe',
    Rule.probe,
    'const _kind = ProbePurpose.processOnly;',
  );

  test(
      'a sublist cut into the conversation fails, and the audio cache limit '
      'does not', () {
    final dir = Directory.systemTemp.createTempSync('doctrine_fixture_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'reintroduced.dart')).writeAsStringSync(
      'final recent = turns.sublist(turns.length - 5);\n',
    );

    final result = evaluate(scan([dir.path]), allowlist);
    final realHits = scan(const ['lib']);

    expect(
      result.violations,
      hasLength(1),
      reason: 'sublist() num arquivo novo não está em nenhuma allowlist',
    );
    expect(
      result.violations.single.rule,
      Rule.memoryWindow,
      reason: 'a violação precisa vir da regra de janela de memória',
    );
    expect(
      realHits.any((h) =>
          h.rule == Rule.memoryWindow &&
          h.file.endsWith('facilitator_voice_service.dart')),
      isFalse,
      reason: 'clips.take() apaga arquivos de áudio velhos, não corta o histórico da conversa',
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
