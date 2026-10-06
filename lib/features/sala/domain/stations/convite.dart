part of '../station.dart';

/// The Invitation; the Closing is not reached from it.
final class Convite extends Station {
  const Convite();

  @override
  SalaStage get stage => SalaStage.convite;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Convite(),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() => const Retro(),
    TheNecklaceClosed() => this,
  };
}
