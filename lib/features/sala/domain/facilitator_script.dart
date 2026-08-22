const offlineNoticeAsset = 'assets/audio/sem_conexao.mp3';

const inviteToStartAsset = 'assets/audio/toque_para_comecar.mp3';

const micBlockedAsset = 'assets/audio/microfone.mp3';

const strandedTakeAsset = 'assets/audio/gravacao_presa.mp3';

const panoramaPericope = 'OV';

String fixedLineAsset(String line) => 'assets/audio/fixed/$line.mp3';

const instantAckLines = ['F0', 'F1', 'F2', 'F3'];

const inaudibleLines = ['D0', 'D1', 'D2'];

const handoffLines = ['C0', 'C1'];

const needsPersonLine = 'E0';

String rotated(List<String> lines, int spoken) => lines[spoken % lines.length];

