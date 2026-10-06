part of '../station.dart';

/// The Closing, reached only from the Back-translation.
final class Fim extends Station {
  const Fim();

  @override
  SalaStage get stage => SalaStage.fim;

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
