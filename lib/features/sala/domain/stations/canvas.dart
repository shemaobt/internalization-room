part of '../station.dart';

/// The Station that holds the Conversation.
final class Canvas extends Station {
  const Canvas();

  @override
  SalaStage get stage => SalaStage.conversa;

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
