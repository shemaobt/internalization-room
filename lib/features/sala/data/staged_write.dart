import 'dart:io';

const staleStagingAge = Duration(minutes: 10);

Future<void> writeWhole(File file, String contents) async {
  final staging = File('${file.path}.novo');
  await staging.writeAsString(contents, flush: true);
  await staging.rename(file.path);
}
