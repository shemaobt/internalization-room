import 'dart:async';

import 'support/temp.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    underOneTempRoot(testMain);
