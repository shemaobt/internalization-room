import 'machine.dart';
import 'session_state.dart';

part 'stations/canvas.dart';
part 'stations/convite.dart';
part 'stations/ensaio.dart';
part 'stations/fim.dart';
part 'stations/menu.dart';
part 'stations/retro.dart';

/// One of the stops a session passes through; it answers the arrivals it understands.
sealed class Station {
  const Station();

  /// The Station a stored resume point names.
  factory Station.stored(SalaStage stage) => switch (stage) {
    SalaStage.convite => const Convite(),
    SalaStage.escolha => const Menu(),
    SalaStage.conversa => const Canvas(),
    SalaStage.ensaio => const Ensaio(),
    SalaStage.retro => const Retro(),
    SalaStage.fim => const Fim(),
  };

  /// What the screen shows for this Station.
  SalaStage get stage;

  Station answer(StationEvent event);

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
