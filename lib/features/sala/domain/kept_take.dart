abstract class KeptScope {
  static const whole = 'passagem-inteira';
}

class KeptTake {
  final String scopeId;
  final String path;

  const KeptTake({required this.scopeId, required this.path});
}
