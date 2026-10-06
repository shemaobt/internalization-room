part of '../station.dart';

/// The Back-translation, wrapped unchanged until its own slice.
final class Retro extends Station {
  const Retro();

  @override
  SalaStage get stage => SalaStage.retro;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Convite(),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    TheBackTranslationOpened() => const Retro(),
    TheNecklaceClosed() => const Fim(),
  };
}
