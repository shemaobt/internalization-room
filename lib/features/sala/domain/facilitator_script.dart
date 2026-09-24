const languages = ['pt', 'en'];

const floorLanguage = 'en';

String languageFor(Iterable<String> spoken) => spoken
    .map((code) => code.toLowerCase())
    .firstWhere(languages.contains, orElse: () => floorLanguage);

String offlineNoticeAsset(String language) =>
    'assets/audio/$language/sem_conexao.mp3';

String micBlockedAsset(String language) =>
    'assets/audio/$language/microfone.mp3';

String strandedTakeAsset(String language) =>
    'assets/audio/$language/gravacao_presa.mp3';

const panoramaPericope = 'OV';

bool isThePanorama(String pericope) =>
    pericope == panoramaPericope || pericope.startsWith('$panoramaPericope-');

String fixedLineAsset(String line, String language) =>
    'assets/audio/$language/fixed/$line.mp3';

const instantAckLines = ['F0', 'F1', 'F2', 'F3'];

const inaudibleLines = ['D0', 'D1', 'D2'];

/// The fourth of Marcia's process lines, read by position: start, tell, unheard,
/// approved. The approval's is the fourth, never rotated.
const approvedLine = 'P3';

String rotated(List<String> lines, int spoken) => lines[spoken % lines.length];

const circleLabels = {
  'needsPerson': {
    'pt': 'Um momento para uma pessoa',
    'en': 'A moment for someone',
  },
  'noteMode': {'pt': 'Enviar a pergunta', 'en': 'Send the question'},
  'teamTalk': {
    'pt': 'Conversem entre vocês — tocar quando quiserem me contar',
    'en': 'Talk among yourselves — tap when you want to tell me',
  },
  'listening': {'pt': 'Tocar ao terminar', 'en': 'Tap when you are done'},
  'default': {'pt': 'Tocar para falar', 'en': 'Tap to speak'},
};

String circleLabelFor(String state, String language) =>
    circleLabels[state]![language] ?? circleLabels[state]![floorLanguage]!;

const panoramaEntryLabel = {'pt': 'Panorama do Livro', 'en': 'Book Panorama'};

String entrarLabelFor({required bool isPanorama, required String language}) =>
    isPanorama
    ? (panoramaEntryLabel[language] ?? panoramaEntryLabel[floorLanguage]!)
    : 'Entrar nesta passagem';

const recordEntryLabel = {
  'pt': 'Gravar o ensaio de vocês',
  'en': 'Record your rehearsal',
};

String recordEntryLabelFor(String language) =>
    recordEntryLabel[language] ?? recordEntryLabel[floorLanguage]!;

const ensaioLabels = {
  'ouvir': {'pt': 'Ouvir a gravação', 'en': 'Listen to the recording'},
  'gravarDeNovo': {'pt': 'Gravar de novo', 'en': 'Record again'},
  'guardar': {'pt': 'Guardar esta gravação', 'en': 'Keep this recording'},
  'irParaTraducao': {'pt': 'Ir para a tradução', 'en': 'Go to the translation'},
};

String ensaioLabelFor(String key, String language) =>
    ensaioLabels[key]![language] ?? ensaioLabels[key]![floorLanguage]!;
