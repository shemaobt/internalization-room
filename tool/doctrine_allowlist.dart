enum Rule { mode, ceiling, probe, memoryWindow, sayLess, model }

class AllowlistEntry {
  final String file;
  final Rule rule;
  final String text;

  const AllowlistEntry(this.file, this.rule, this.text);
}

const allowlist = <AllowlistEntry>[
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
    'const _turnTimeout = Duration(seconds: 305);',
  ),
  AllowlistEntry(
    'lib/features/sala/data/session_notifier.dart',
    Rule.ceiling,
    'final busyStateCeilingProvider = Provider<Duration?>(',
  ),
];
