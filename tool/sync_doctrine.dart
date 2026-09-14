/// Vendor Marcia's doctrine at a pinned commit, or check it for drift.
///
/// `docs/DOCTRINE.md` is binding on every change to this repository, and its header says to read
/// it before touching a prompt, the turn loop, the model seam or the canvas. Neither repo carried
/// it, so the sentence `tool/check_doctrine.dart` prints pointed at a document a developer here
/// could not open.
///
/// It is vendored, not forked. The pin records repo, branch, commit and a sha256 per file, an
/// edit to the vendored bytes is a merge conflict rather than a decision, and a pin moved with no
/// ruling beside it is refused — a re-sync rewrites every sha, so the commit is the only thing
/// that cannot move quietly.
///
/// `--sync` reads her working tree rather than the network: the repository is private, and a
/// token in CI would be a second way in for something meant to move by hand, when she has ruled.
/// The prompts are not vendored here — they run in `tripod-backend`, and so does their record.
///
///     dart run tool/sync_doctrine.dart --check
///     dart run tool/sync_doctrine.dart --sync --from ~/src/Tripod-Internalization
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const repo = 'shemaobt/Tripod-Internalization';
const branch = 'fia/pilot-2026-09';

/// Her path in `Tripod-Internalization` → the path it is vendored to here.
const vendored = {'docs/DOCTRINE.md': 'docs/doctrine/vendor/DOCTRINE.md'};
const vendoredDoctrine = 'docs/doctrine/vendor/DOCTRINE.md';

const pinPath = 'docs/doctrine/DOCTRINE_PIN';
const rulingsPath = 'docs/doctrine/rulings';
const barPath = 'docs/doctrine/ACCEPTANCE_BAR';

/// A bar row this repo does not hold today, counted out loud rather than left out.
const pending = 'PENDING';

/// A bar row `tripod-backend` holds: the line is on §4, and the test that holds it is there.
const backend = 'BACKEND';

const ownership =
    "DOCTRINE.md §5.1 — prompts/*.md, the model ladder and its parameters are Marcia's "
    'artifacts: any change is a ruling with her word, never an engineering default.';
const notAFork =
    'DOCTRINE.md is vendored, not forked: a vendored artefact is re-synced, never edited. '
    'Restore the bytes, or re-pin with --sync and record her ruling.';
const theBar =
    'DOCTRINE.md §4 — what must not regress. Every line of it is claimed by a test that '
    'names it, or recorded as PENDING or BACKEND.';

class Pin {
  final String repo;
  final String branch;
  final String commit;
  final Map<String, String> digests;

  const Pin(this.repo, this.branch, this.commit, this.digests);
}

class Ruling {
  final String slug;
  final String pin;
  final String word;
  final String written;

  const Ruling(this.slug, this.pin, this.word, this.written);
}

String digestOf(String body) => sha256.convert(utf8.encode(body)).toString();

Pin readPin([File? pinFile]) {
  final fields = <String, String>{};
  final digests = <String, String>{};
  for (final line in (pinFile ?? File(pinPath)).readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final at = line.indexOf(' ');
    final head = line.substring(0, at);
    final rest = line.substring(at).trim();
    if (head == 'repo' || head == 'branch' || head == 'commit') {
      fields[head] = rest;
    } else {
      digests[rest] = head;
    }
  }
  return Pin(
    fields['repo'] ?? '',
    fields['branch'] ?? '',
    fields['commit'] ?? '',
    digests,
  );
}

void writePin(String commit, Map<String, String> digests, [File? pinFile]) {
  final paths = digests.keys.toList()..sort();
  final lines = [
    'repo $repo',
    'branch $branch',
    'commit $commit',
    '',
    for (final path in paths) '${digests[path]}  $path',
  ];
  (pinFile ?? File(pinPath)).writeAsStringSync('${lines.join('\n')}\n');
}

/// Every vendored path whose bytes are not the ones the pin recorded.
///
/// Walked over [vendored] rather than over the pin, because the pin is the thing being checked:
/// dropping a row and its file together is otherwise an artefact that silently stops being
/// vendored, with the comparison green for having nothing left to compare.
List<String> drift(Pin pin, [String root = '.']) {
  final drifted = <String>[];
  final paths = vendored.values.toList()..sort();
  for (final path in paths) {
    final local = File(p.join(root, path));
    if (!pin.digests.containsKey(path)) {
      drifted.add('unpinned: $path');
    } else if (!local.existsSync()) {
      drifted.add('missing: $path');
    } else if (digestOf(local.readAsStringSync()) != pin.digests[path]) {
      drifted.add('edited: $path');
    }
  }
  return drifted;
}

List<Ruling> readRulings([String? dir]) {
  final directory = Directory(dir ?? rulingsPath);
  if (!directory.existsSync()) return const [];
  final files = directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      () {
        final fields = <String, String>{};
        for (final line in file.readAsLinesSync()) {
          final at = line.indexOf(':');
          if (at < 0) continue;
          final key = line.substring(0, at).trim();
          if (key == 'pin' || key == 'word' || key == 'written') {
            fields[key] = line.substring(at + 1).trim();
          }
        }
        return Ruling(
          p.basenameWithoutExtension(file.path),
          fields['pin'] ?? '',
          fields['word'] ?? '',
          fields['written'] ?? '',
        );
      }(),
  ];
}

/// What the pin and the rulings beside it fail to account for.
List<String> unruled(Pin pin, List<Ruling> rulings) {
  final faults = <String>[];
  if (!rulings.any((r) => r.pin == pin.commit)) {
    faults.add('no ruling records the pin ${pin.commit.substring(0, 12)}');
  }
  for (final ruling in rulings) {
    if (ruling.word.isEmpty || ruling.written.isEmpty) {
      faults.add('${ruling.slug}: a ruling carries her sentence and where it is written');
    }
  }
  return faults;
}

/// §4's lines, read out of the vendored doctrine rather than transcribed beside it.
///
/// Her first bullet is one sentence carrying twelve rules, so the bullet is not the line: the
/// semicolon is. Parsed on every run, so a line she adds on the next re-pin arrives as a red
/// build instead of as a line nobody remembered to copy.
List<String> acceptanceBar([String root = '.']) {
  final text = File(p.join(root, vendoredDoctrine)).readAsStringSync();
  var section = text.substring(text.indexOf('## 4. What must not regress'));
  section = section.substring(0, section.indexOf('\n## ', 1));
  final lines = <String>[];
  for (final bullet in section.split('\n- ').skip(1)) {
    final unwrapped = bullet.split(RegExp(r'\s+')).join(' ').trim();
    for (final clause in unwrapped.split(';')) {
      lines.add(clause.trim());
    }
  }
  return lines;
}

/// The bar as rows: a fragment of one §4 line, two spaces, then the claims, `\u007c`-separated.
///
/// Separated by a pipe and not by whitespace, because a claim here ends in a Dart test
/// description and every one of those has spaces in it.
Map<String, List<String>> readBarRecord([String root = '.']) {
  final record = <String, List<String>>{};
  for (final line in File(p.join(root, barPath)).readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final at = line.indexOf('  ');
    record[line.substring(0, at).trim()] = line.substring(at).trim().split(' | ');
  }
  return record;
}

bool _testExists(String claim, String root) {
  final parts = claim.split('::');
  final file = File(p.join(root, parts.first));
  if (!file.existsSync()) return false;
  return file.readAsStringSync().contains("'${parts.last}'");
}

/// Where §4 and the record disagree: a line unclaimed, a fragment stale, a test gone.
///
/// The fragment is matched against the line rather than compared to it. A guard on her wording
/// would go red for a rename that leaves the ruling untouched.
List<String> barFaults(
  List<String> lines,
  Map<String, List<String>> record, {
  String root = '.',
  bool testsExist = true,
}) {
  final faults = <String>[];
  for (final line in lines) {
    if (!record.keys.any(line.contains)) faults.add('unclaimed: $line');
  }
  for (final entry in record.entries) {
    if (!lines.any((line) => line.contains(entry.key))) {
      faults.add('stale: ${entry.key}');
      continue;
    }
    if (!testsExist) continue;
    for (final claim in entry.value) {
      if (claim == pending || claim == backend) continue;
      if (!_testExists(claim, root)) faults.add('no such test: $claim');
    }
  }
  return faults;
}

int sync(String source) {
  final commit = Process.runSync('git', ['-C', source, 'rev-parse', 'HEAD'])
      .stdout
      .toString()
      .trim();
  final digests = <String, String>{};
  for (final entry in vendored.entries) {
    final body = File(p.join(source, entry.key)).readAsStringSync();
    final target = File(entry.value);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(body);
    digests[entry.value] = digestOf(body);
    stdout.writeln('  ${entry.value}');
  }
  writePin(commit, digests);
  stdout.writeln('pinned at $commit');
  return 0;
}

int check() {
  final pin = readPin();
  final drifted = drift(pin);
  if (drifted.isNotEmpty) {
    stderr.writeln('the vendored doctrine drifted from pin ${pin.commit.substring(0, 12)}:');
    for (final line in drifted) {
      stderr.writeln('  $line');
    }
    stderr.writeln(notAFork);
    return 1;
  }

  final missing = unruled(pin, readRulings());
  if (missing.isNotEmpty) {
    for (final line in missing) {
      stderr.writeln('  $line');
    }
    stderr.writeln(ownership);
    return 1;
  }

  final bar = readBarRecord();
  final lines = acceptanceBar();
  final faults = barFaults(lines, bar);
  if (faults.isNotEmpty) {
    for (final line in faults) {
      stderr.writeln('  $line');
    }
    stderr.writeln(theBar);
    return 1;
  }

  final held = bar.values.where((c) => c.first != pending && c.first != backend).length;
  stdout.writeln('the vendored doctrine matches pin ${pin.commit.substring(0, 12)}');
  stdout.writeln(
    'the acceptance bar is ${lines.length} lines — $held held here, '
    '${bar.values.where((c) => c.first == pending).length} still PENDING',
  );
  return 0;
}

void main(List<String> args) {
  if (args.contains('--sync')) {
    final at = args.indexOf('--from');
    if (at < 0 || at + 1 >= args.length) {
      stderr.writeln('--sync needs --from <checkout of Tripod-Internalization>');
      exit(2);
    }
    exit(sync(args[at + 1]));
  }
  if (args.contains('--check')) exit(check());
  stderr.writeln('usage: dart run tool/sync_doctrine.dart --check | --sync --from <path>');
  exit(2);
}
