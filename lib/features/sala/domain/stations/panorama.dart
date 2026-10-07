part of '../station.dart';

/// The Station where the book's Panorama is voiced; the Closing is not reached from it.
final class Panorama extends Station {
  const Panorama();

  @override
  SalaStage get stage => SalaStage.panorama;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen() => const Panorama(),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() => const Retro(),
    TheNecklaceClosed() => this,
  };
}
