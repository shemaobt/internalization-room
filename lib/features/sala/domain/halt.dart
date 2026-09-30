sealed class Kept {
  const Kept();
}

final class NothingKept extends Kept {
  const NothingKept();
}

final class ThePart extends Kept {
  const ThePart();
}

final class TheOpening extends Kept {
  final String failedTurnId;

  const TheOpening(this.failedTurnId);

  @override
  bool operator ==(Object other) =>
      other is TheOpening && other.failedTurnId == failedTurnId;

  @override
  int get hashCode => failedTurnId.hashCode;
}

final class TheResume extends Kept {
  const TheResume();
}

final class TheWheel extends Kept {
  const TheWheel();
}

sealed class Halt {
  const Halt();
}

final class NoHalt extends Halt {
  const NoHalt();
}

final class Warning extends Halt {
  const Warning();
}

final class Blocking extends Halt {
  final Kept kept;
  final bool warningBeneath;
  final bool serverKnows;

  const Blocking(
    this.kept, {
    this.warningBeneath = false,
    this.serverKnows = false,
  });

  @override
  bool operator ==(Object other) =>
      other is Blocking &&
      other.kept == kept &&
      other.warningBeneath == warningBeneath &&
      other.serverKnows == serverKnows;

  @override
  int get hashCode => Object.hash(kept, warningBeneath, serverKnows);
}
