class MeaningMapElement {
  final String name;
  final bool isAbsence;

  const MeaningMapElement(this.name, {this.isAbsence = false});
}

abstract class RuthOneMeaningMap {
  static const elements = <MeaningMapElement>[
    MeaningMapElement('A fome na terra'),
    MeaningMapElement('Elimeleque parte para Moabe'),
    MeaningMapElement('Noemi'),
    MeaningMapElement('Malom e Quiliom'),
    MeaningMapElement('As mortes em Moabe'),
    MeaningMapElement('Orfa'),
    MeaningMapElement('Rute'),
    MeaningMapElement('A decisão de voltar'),
    MeaningMapElement('A despedida de Orfa'),
    MeaningMapElement('O apego de Rute'),
    MeaningMapElement('Belém — “Chamai-me Mara”'),
    MeaningMapElement('AUSÊNCIA: por que foram a Moabe?', isAbsence: true),
  ];

  static int get count => elements.length;
  static const absenceIndex = 11;
  static const segmentCount = 5;
}
