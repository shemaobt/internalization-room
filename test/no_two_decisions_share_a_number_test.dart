import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('every decision in docs/adr carries a number no other one carries', () {
    final byNumber = <String, List<String>>{};
    for (final file in Directory('docs/adr').listSync().whereType<File>()) {
      final name = p.basename(file.path);
      byNumber.putIfAbsent(name.substring(0, 4), () => []).add(name);
    }

    final shared = {
      for (final entry in byNumber.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };

    expect(
      shared,
      isEmpty,
      reason:
          'mais de uma decisão levou ${shared.keys.join(', ')}, e cada referência '
          'apontava para duas; a que chegou depois à main toma o próximo número '
          'livre, e cada referência a ela passa a nomeá-lo',
    );
  });
}
