part of '../station.dart';

/// The Station that holds the Choice.
final class Menu extends Station {
  const Menu();

  @override
  SalaStage get stage => SalaStage.escolha;

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
