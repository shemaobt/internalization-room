import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'room_answer.dart';
import 'room_repository.dart';

final thisBuildProvider = Provider<int>(
  (ref) => const int.fromEnvironment('BUILD_NUMBER'),
);

Uri? storeListingFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => Uri.parse(
    'https://play.google.com/store/apps/details?id=com.shema.internalization_room',
  ),
  TargetPlatform.iOS => Uri.parse('https://apps.apple.com/app/id6823303385'),
  _ => null,
};

final openTheStoreProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return;
    }
  },
);

class StoreBuildGate extends Notifier<bool> {
  Future<void>? _reading;

  @override
  bool build() => false;

  Future<void> look() {
    final build = ref.read(thisBuildProvider);
    if (state || build == 0) return Future.value();
    return _reading ??= _read(build).whenComplete(() => _reading = null);
  }

  Future<void> _read(int build) async {
    final answer = await ref.read(roomRepositoryProvider).minimumBuilds();
    if (answer case Answered(
      value: final minimum,
    ) when minimum.keepsOut(build, defaultTargetPlatform)) {
      state = true;
    }
  }

  Future<void> openTheStore() async {
    final listing = storeListingFor(defaultTargetPlatform);
    if (listing == null) return;
    await ref.read(openTheStoreProvider)(listing);
  }
}

final storeBuildGateProvider = NotifierProvider<StoreBuildGate, bool>(
  StoreBuildGate.new,
);
