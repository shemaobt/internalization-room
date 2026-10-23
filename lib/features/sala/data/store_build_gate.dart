import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/minimum_build.dart';
import 'device_link_notifier.dart';
import 'room_answer.dart';
import 'room_repository.dart';
import 'session_notifier.dart';

final thisBuildProvider = Provider<int>(
  (ref) => const int.fromEnvironment('BUILD_NUMBER'),
);

Uri? storeListingFor(TargetPlatform platform) => switch (storeOf(platform)) {
  Store.googlePlay => Uri.parse(
    'https://play.google.com/store/apps/details?id=com.shema.internalization_room',
  ),
  Store.appStore => Uri.parse('https://apps.apple.com/app/id6823303385'),
  null => null,
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
  bool _kept = false;
  bool _shown = false;

  @override
  bool build() {
    final arrived = ref.watch(
      salaSessionProvider.select((s) => s.arrivedAtTheChoice),
    );
    final unlinked = ref.watch(
      deviceLinkProvider.select((l) => l.team == null && l.code != null),
    );
    if (_kept && (arrived || unlinked)) _shown = true;
    return _shown;
  }

  Future<void> look() {
    final build = ref.read(thisBuildProvider);
    if (_kept || build == 0) return Future.value();
    return _reading ??= _read(build).whenComplete(() => _reading = null);
  }

  Future<void> _read(int build) async {
    final answer = await ref.read(roomRepositoryProvider).minimumBuilds();
    if (answer case Answered(
      value: final minimum,
    ) when minimum.keepsOut(build, defaultTargetPlatform)) {
      _kept = true;
      ref.invalidateSelf();
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
