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

const retroLabels = {
  'record': {
    'pt': 'Tocar para gravar a tradução deste trecho',
    'en': 'Tap to record this stretch\'s translation',
  },
  'recordAgain': {
    'pt': 'Tocar para gravar a tradução de novo',
    'en': 'Tap to record the translation again',
  },
  'recording': {'pt': 'Tocar ao terminar', 'en': 'Tap when you finish'},
  'listen': {'pt': 'Ouvir', 'en': 'Listen'},
  'listenToTheTranslation': {
    'pt': 'Ouvir a tradução',
    'en': 'Listen to the translation',
  },
  'pause': {'pt': 'Pausar', 'en': 'Pause'},
  'cut': {'pt': 'Cortar aqui', 'en': 'Cut here'},
  'confirm': {
    'pt': 'Confirmar a tradução e seguir',
    'en': 'Confirm the translation and go on',
  },
  'advance': {'pt': 'Conferir a tradução', 'en': 'Check the translation'},
  'stretch': {'pt': 'Trecho', 'en': 'Stretch'},
  'listenToTheRecording': {
    'pt': 'Ouvir a gravação',
    'en': 'Listen to the recording',
  },
  'approve': {
    'pt': 'Aprovar como rascunho final',
    'en': 'Approve as the final draft',
  },
};

String retroLabelFor(String control, String language) =>
    retroLabels[control]![language] ?? retroLabels[control]![floorLanguage]!;

const rehearsalLabels = {
  'firstPart': {
    'pt': 'Tocar para gravar o ensaio',
    'en': 'Tap to record the rehearsal',
  },
  'nextPart': {
    'pt': 'Tocar para gravar a próxima parte',
    'en': 'Tap to record the next part',
  },
  'recording': {'pt': 'Tocar ao terminar', 'en': 'Tap when you finish'},
  'pending': {
    'pt': 'Tocar para gravar esta parte de novo',
    'en': 'Tap to record this part again',
  },
  'partAgain': {
    'pt': 'Gravar a parte {n} de novo',
    'en': 'Record part {n} again',
  },
  'play': {'pt': 'Ouvir o ensaio até aqui', 'en': 'Hear the rehearsal so far'},
  'pause': {'pt': 'Pausar o ensaio', 'en': 'Pause the rehearsal'},
  'check': {'pt': 'Confirmar esta parte', 'en': 'Confirm this part'},
  'advance': {'pt': 'Ir para a tradução', 'en': 'Go to the translation'},
  'part': {'pt': 'Parte {n}', 'en': 'Part {n}'},
};

String rehearsalLabelFor(String state, String language, {int? part}) =>
    (rehearsalLabels[state]![language] ??
            rehearsalLabels[state]![floorLanguage]!)
        .replaceAll('{n}', '$part');

const findingLabels = {
  'circle': {'pt': 'Ouvir o achado de novo', 'en': 'Hear the finding again'},
  'play': {
    'pt': 'Ouvir o trecho e a tradução',
    'en': 'Hear the stretch and its translation',
  },
  'recordThePart': {
    'pt': 'Gravar a parte de novo na língua materna',
    'en': 'Record the part again in the mother tongue',
  },
  'translateTheStretch': {
    'pt': 'Traduzir este trecho de novo',
    'en': 'Translate this stretch again',
  },
  'continue': {'pt': 'Continuar o ensaio', 'en': 'Continue the rehearsal'},
};

String findingLabelFor(String control, String language) =>
    findingLabels[control]![language] ??
    findingLabels[control]![floorLanguage]!;

const panoramaEntryLabel = {'pt': 'Panorama do Livro', 'en': 'Book Panorama'};

String entrarLabelFor({required bool isPanorama, required String language}) =>
    isPanorama
    ? (panoramaEntryLabel[language] ?? panoramaEntryLabel[floorLanguage]!)
    : 'Entrar nesta passagem';
