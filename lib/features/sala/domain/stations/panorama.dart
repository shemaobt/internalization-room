part of '../station.dart';

/// The Station where the book's Panorama is voiced; the Closing is not reached from it.
final class Panorama extends Station {
  final String id;

  const Panorama(this.id);

  @override
  SalaStage get stage => SalaStage.panorama;

  @override
  bool operator ==(Object other) => other is Panorama && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  Station answer(StationEvent event) => switch (event) {
    TheRoomStartedOver() => const Menu(),
    ThePanoramaChosen(:final id) => Panorama(id),
    TheChoiceOpened() => const Menu(),
    PassageChosen() => const Canvas(),
    TheRehearsalOpened() => const Ensaio(),
    ThePlanOpened() => this,
    TheBackTranslationOpened() => const Retro(),
    TheSceneRehearsalOpened() || TheSceneRehearsalLeft() => this,
    TheExternalCheckOpened() ||
    TheExternalCheckLeft() ||
    TheRecordingLeft() => this,
  };
}
