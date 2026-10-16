import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'staged_write.dart';

const _folder = 'guardadas';

abstract class ChoiceLedger {
  final Future<Directory> Function() _home;
  final String fileName;
  final String key;
  String? _chosen;
  Future<void> _writes = Future<void>.value();

  ChoiceLedger({
    required this.fileName,
    required this.key,
    Future<Directory> Function()? home,
  }) : _home = home ?? getApplicationSupportDirectory;

  String? get chosen => _chosen;

  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        _chosen = json[key] as String?;
      }
    } on Object {
      _chosen = null;
    }
  }

  Future<void> choose(String value) {
    _chosen = value;
    final next = _writes.then((_) async {
      final file = await _file();
      await writeWhole(file, jsonEncode({key: value}));
    });
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<File> _file() async {
    final dir = Directory(p.join((await _home()).path, _folder));
    await dir.create(recursive: true);
    return File(p.join(dir.path, fileName));
  }
}
