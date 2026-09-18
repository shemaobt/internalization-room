abstract class KeptScope {
  static const whole = 'passagem-inteira';

  static String parte(int n) => 'parte-$n';

  /// Whether a scope names one of the rehearsal's own parts — never a correction's, which
  /// is a slice of one of these and not a part of the rehearsal in its own right.
  static bool isParte(String scopeId) => scopeId.startsWith('parte-');
}

class KeptTake {
  final String scopeId;
  final String path;

  /// Where the room put this recording, once it has answered for it.
  ///
  /// A told-back stretch is a slice of one file and names it, so the retro cannot send a
  /// stretch of a part the room has never seen. Null until the upload lands.
  final String? takeId;

  const KeptTake({required this.scopeId, required this.path, this.takeId});

  KeptTake withTakeId(String? id) =>
      KeptTake(scopeId: scopeId, path: path, takeId: id ?? takeId);
}
