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
  const TheOpening();
}

/// The room's last line, said again on the team's tap.
final class TheLineSaidAgain extends Kept {
  const TheLineSaidAgain();
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
  final bool warningBeneath;
  final bool reachesNoRoom;

  const Blocking({this.warningBeneath = false, this.reachesNoRoom = false});

  @override
  bool operator ==(Object other) =>
      other is Blocking &&
      other.warningBeneath == warningBeneath &&
      other.reachesNoRoom == reachesNoRoom;

  @override
  int get hashCode => Object.hash(warningBeneath, reachesNoRoom);
}
