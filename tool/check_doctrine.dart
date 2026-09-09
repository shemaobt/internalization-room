import 'dart:io';

import 'package:path/path.dart' as p;

import 'doctrine_allowlist.dart';

class DoctrineRule {
  final Rule id;
  final RegExp pattern;
  final String message;

  const DoctrineRule(this.id, this.pattern, this.message);
}

final rules = <DoctrineRule>[
  DoctrineRule(
    Rule.mode,
    RegExp(r'bridgeMode|bridge_mode|guided_microchecks|full_retell'),
    'no app-owned bridge-language modes',
  ),
  DoctrineRule(
    Rule.ceiling,
    RegExp(
      r'MAX_SPOKEN_[A-Z_]*|SpeechBudget|overSpeechBudget|_brokenCeiling'
      r'|speechBudgetFor|[A-Z][A-Z_]*_BUDGET'
      r'|_turnTimeout\s*=|busyStateCeilingProvider\s*=',
    ),
    'no speech ceilings in code — length is prompt style, never a reject',
  ),
  DoctrineRule(
    Rule.probe,
    RegExp(
      r'PROCESS_ONLY|ProbePurpose|MOTHER_TONGUE_PRACTICE|SCENE_OPENING'
      r'|planNextProbe|renderActiveProbeContract|isProcessOnly'
      r'|ACTIVE COMPREHENSION PROBE|BRIDGE MODE',
    ),
    'no probe/station contracts that forbid the Guide content',
  ),
  DoctrineRule(
    Rule.memoryWindow,
    RegExp(r'_RECENT_TURNS|MAX_MESSAGES|\.sublist\(|takeLast'),
    'whole conversation in context — no memory window',
  ),
  DoctrineRule(
    Rule.sayLess,
    RegExp(
      r'say less|saying less|dizendo menos|diga menos',
      caseSensitive: false,
    ),
    "no 'say less' notes — a request to understand is answered fully",
  ),
  DoctrineRule(
    Rule.model,
    RegExp(r'gemini_\w+|ThinkingLevel\.LOW|thinkingBudget|maxTokens|tokenBudget'),
    'frontier Claude with adaptive thinking on the voice',
  ),
];

class Hit {
  final String file;
  final int line;
  final Rule rule;
  final String text;
  final String message;

  const Hit({
    required this.file,
    required this.line,
    required this.rule,
    required this.text,
    required this.message,
  });
}

List<Hit> scan(Iterable<String> roots) {
  final hits = <Hit>[];
  for (final root in roots) {
    final files = Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final rel = p.posix.joinAll(p.split(p.relative(file.path)));
      final lines = file.readAsStringSync().split('\n');
      for (final rule in rules) {
        for (var i = 0; i < lines.length; i++) {
          if (rule.pattern.hasMatch(lines[i])) {
            hits.add(Hit(
              file: rel,
              line: i + 1,
              rule: rule.id,
              text: lines[i].trim(),
              message: rule.message,
            ));
          }
        }
      }
    }
  }
  return hits;
}

({List<Hit> violations, List<AllowlistEntry> stale}) evaluate(
  List<Hit> hits,
  List<AllowlistEntry> allowlist,
) {
  final allowedLeft = <(String, Rule, String), int>{};
  for (final e in allowlist) {
    final key = (e.file, e.rule, e.text);
    allowedLeft[key] = (allowedLeft[key] ?? 0) + 1;
  }
  final foundLeft = <(String, Rule, String), int>{};
  for (final h in hits) {
    final key = (h.file, h.rule, h.text);
    foundLeft[key] = (foundLeft[key] ?? 0) + 1;
  }

  final violations = <Hit>[];
  for (final h in hits) {
    final key = (h.file, h.rule, h.text);
    final left = allowedLeft[key] ?? 0;
    if (left > 0) {
      allowedLeft[key] = left - 1;
    } else {
      violations.add(h);
    }
  }

  final stale = <AllowlistEntry>[];
  for (final e in allowlist) {
    final key = (e.file, e.rule, e.text);
    final left = foundLeft[key] ?? 0;
    if (left > 0) {
      foundLeft[key] = left - 1;
    } else {
      stale.add(e);
    }
  }

  return (violations: violations, stale: stale);
}

void main() {
  final result = evaluate(scan(const ['lib']), allowlist);
  if (result.violations.isEmpty && result.stale.isEmpty) {
    stdout.writeln(
      'doctrine guard passed — every hit is on the allowlist, every entry still matches',
    );
    exit(0);
  }
  for (final hit in result.violations) {
    stdout.writeln('✗ ${hit.file}:${hit.line}  [${hit.rule.name}] ${hit.message}');
  }
  for (final entry in result.stale) {
    stdout.writeln(
      "✗ ${entry.file}  [${entry.rule.name}] allowlist entry no longer matches any hit: "
      "'${entry.text}' — remove it or the mechanism it named moved without the list updating",
    );
  }
  exit(1);
}
