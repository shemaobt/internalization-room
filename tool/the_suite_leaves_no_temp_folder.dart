import 'dart:io';

import 'package:path/path.dart' as p;

Set<String> tempFoldersIn(Directory temp) => {
  for (final entry in temp.listSync())
    if (p.basename(entry.path).startsWith('sala-')) p.basename(entry.path),
};

Future<int> runCountingTempFolders(
  List<String> command,
  Directory temp,
  StringSink out,
) async {
  final before = tempFoldersIn(temp);
  final process = await Process.start(
    command.first,
    command.skip(1).toList(),
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) return code;
  final outlived = tempFoldersIn(temp).difference(before);
  if (outlived.isEmpty) return 0;
  for (final name in outlived.toList()..sort()) {
    out.writeln(p.join(temp.path, name));
  }
  out.writeln('${outlived.length} temp folders outlived the run');
  return 1;
}

Future<void> main(List<String> args) async {
  exit(await runCountingTempFolders(args, Directory.systemTemp, stderr));
}
