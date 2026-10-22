abstract class KeptScope {
  static const whole = 'passagem-inteira';

  static String parte(int n) => 'parte-$n';

  /// Whether a scope names one of the rehearsal's own parts — never a correction's, which
  /// is a slice of one of these and not a part of the rehearsal in its own right.
  static bool isParte(String scopeId) => scopeId.startsWith('parte-');

  /// The N of `parte-N`, the Scene the part answers for; null for any other scope.
  static int? numberOf(String scopeId) => isParte(scopeId)
      ? int.tryParse(scopeId.substring('parte-'.length))
      : null;

  /// The lowest part number not in [used].
  static int firstFree(Set<int> used) {
    var number = 1;
    while (used.contains(number)) {
      number++;
    }
    return number;
  }
}

class UnsentPart {
  final bool fromAnEarlierVisit;
  final bool failed;
  final Duration? length;

  const UnsentPart({
    required this.fromAnEarlierVisit,
    required this.failed,
    this.length,
  });
}

class KeptTake {
  final String scopeId;
  final String path;

  /// Where the room put this recording, once it has answered for it.
  ///
  /// A told-back stretch is a slice of one file and names it, so the retro cannot send a
  /// stretch of a part the room has never seen. Null until the upload lands.
  final String? takeId;

  /// Which of this part's own recordings this one is: 1 for the first, and one more for
  /// each time the team recorded the part again.
  ///
  /// The room decides which recording of a part is the part by this count and then by
  /// arrival, so two recordings the tablet counted alike are separated by nothing but
  /// the order they happened to land in.
  final int pass;

  /// The Scene rehearsal this part was laid in from, as the room names it; null for a part
  /// recorded as itself.
  final String? origin;

  const KeptTake({
    required this.scopeId,
    required this.path,
    this.takeId,
    this.pass = 1,
    this.origin,
  });

  KeptTake withTakeId(String? id) => KeptTake(
    scopeId: scopeId,
    path: path,
    takeId: id ?? takeId,
    pass: pass,
    origin: origin,
  );
}
