const languages = ['pt', 'en'];

const floorLanguage = 'en';

String languageFor(Iterable<String> spoken) => spoken
    .map((code) => code.toLowerCase())
    .firstWhere(languages.contains, orElse: () => floorLanguage);

String offlineNoticeAsset(String language) =>
    'assets/audio/$language/sem_conexao.mp3';

String inviteToStartAsset(String language) =>
    'assets/audio/$language/toque_para_comecar.mp3';

String micBlockedAsset(String language) =>
    'assets/audio/$language/microfone.mp3';

String strandedTakeAsset(String language) =>
    'assets/audio/$language/gravacao_presa.mp3';

const panoramaPericope = 'OV';

String fixedLineAsset(String line, String language) =>
    'assets/audio/$language/fixed/$line.mp3';

const instantAckLines = ['F0', 'F1', 'F2', 'F3'];

const inaudibleLines = ['D0', 'D1', 'D2'];

const handoffLines = ['C0', 'C1'];

const needsPersonLine = 'E0';

String rotated(List<String> lines, int spoken) => lines[spoken % lines.length];
