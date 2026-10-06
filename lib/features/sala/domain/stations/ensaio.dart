part of '../station.dart';

/// The Rehearsal, wrapped unchanged until its own slice.
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
