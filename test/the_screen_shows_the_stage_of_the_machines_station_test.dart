import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

SalaStage _shownAt(Station station) =>
    SalaSessionState(machine: Machine(station: station)).stage;

void main() {
  test('the screen shows the stage of the machine\'s Station', () {
    expect(_shownAt(const Panorama('OV-Ruth')), SalaStage.panorama);
    expect(_shownAt(const Menu()), SalaStage.escolha);
    expect(_shownAt(const Canvas()), SalaStage.conversa);
    expect(_shownAt(const Ensaio()), SalaStage.ensaio);
    expect(_shownAt(const Retro()), SalaStage.retro);
    expect(_shownAt(const Fim()), SalaStage.fim);
    expect(_shownAt(const ChecagemExterna(1)), SalaStage.checagem);
    expect(const SalaSessionState().stage, SalaStage.escolha);
  });

  test('a stored Panorama names no Panorama, and is read as the Choice', () {
    expect(Station.stored(SalaStage.panorama), isA<Menu>());
  });
}
