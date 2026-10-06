part of '../station.dart';

/// The Invitation, wrapped unchanged until its own slice.
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
