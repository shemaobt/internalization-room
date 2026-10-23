import 'package:flutter/foundation.dart';

class MinimumBuilds {
  final int ios;
  final int android;

  const MinimumBuilds({required this.ios, required this.android});

  factory MinimumBuilds.fromJson(Map<String, dynamic> json) {
    final minimum = json['minimum_app'] as Map<String, dynamic>;
    return MinimumBuilds(
      ios: minimum['ios'] as int,
      android: minimum['android'] as int,
    );
  }

  bool keepsOut(int build, TargetPlatform platform) {
    final minimum = switch (platform) {
      TargetPlatform.iOS => ios,
      TargetPlatform.android => android,
      _ => 0,
    };
    return build > 0 && build < minimum;
  }
}
