part of '../station.dart';

/// The Rehearsal; the Closing is not reached from it.
final class Ensaio extends Station {
  const Ensaio();

  @override
  SalaStage get stage => SalaStage.ensaio;

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
