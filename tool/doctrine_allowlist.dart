enum Rule { mode, ceiling, probe, memoryWindow }

class AllowlistEntry {
  final String file;
  final Rule rule;
  final String text;

  const AllowlistEntry(this.file, this.rule, this.text);
}

const allowlist = <AllowlistEntry>[
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.mode,
    'String? _bridgeMode;',
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.mode,
    'if (turn.bridgeMode.isEmpty) {',
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.mode,
    "if (turn.bridgeMode == 'calibration_pending') {",
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.mode,
    '_bridgeMode = turn.bridgeMode;',
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.mode,
    'bridgeMode: _bridgeMode,',
  ),
  AllowlistEntry(
    'lib/features/sala/data/room_repository.dart',
    Rule.mode,
    'String? bridgeMode,',
  ),
  AllowlistEntry(
    'lib/features/sala/data/room_repository.dart',
    Rule.mode,
    "'bridge_mode': ?bridgeMode,",
  ),
  AllowlistEntry(
    'lib/features/sala/domain/turn_result.dart',
    Rule.mode,
    'final String bridgeMode;',
  ),
  AllowlistEntry(
    'lib/features/sala/domain/turn_result.dart',
    Rule.mode,
    "this.bridgeMode = '',",
  ),
  AllowlistEntry(
    'lib/features/sala/domain/turn_result.dart',
    Rule.mode,
    "bridgeMode: json['bridge_mode'] as String? ?? '',",
  ),
  AllowlistEntry(
    'lib/features/sala/data/room_repository.dart',
    Rule.ceiling,
    'const _turnTimeout = Duration(seconds: 90);',
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.ceiling,
    'final busyStateCeilingProvider = Provider<Duration?>(',
  ),
];
