abstract final class RefusalCode {
  static const unauthorized = 'UNAUTHORIZED';
  static const forbidden = 'FORBIDDEN';
  static const deviceRevoked = 'DEVICE_REVOKED';
  static const notFound = 'NOT_FOUND';
  static const stretchNoLongerCounts = 'STRETCH_NO_LONGER_COUNTS';
  static const unreadable = 'UNREADABLE';
  static const passageCannotOpen = 'PASSAGE_CANNOT_OPEN';
  static const credentialNotYet = 'CREDENTIAL_NOT_YET';
  static const credentialTaken = 'CREDENTIAL_TAKEN';
  static const nobodyToReach = 'NOBODY_TO_REACH';
  static const idempotencyKeyInFlight = 'IDEMPOTENCY_KEY_IN_FLIGHT';
  static const passageClosed = 'PASSAGE_CLOSED';
  static const wordlessTelling = 'WORDLESS_TELLING';
  static const sceneRehearsalSent = 'SCENE_REHEARSAL_SENT';
  static const restartOutOfOrder = 'RESTART_OUT_OF_ORDER';
  static const tooLarge = 'TOO_LARGE';
  static const sceneRehearsalSending = 'SCENE_REHEARSAL_SENDING';
  static const sentenceTooLong = 'SENTENCE_TOO_LONG';
  static const sentenceTooShort = 'SENTENCE_TOO_SHORT';
  static const sentenceFormatDiffers = 'SENTENCE_FORMAT_DIFFERS';
  static const anotherSentenceAwaits = 'ANOTHER_SENTENCE_AWAITS';

  static const stopsTheRoom = {unauthorized, forbidden, deviceRevoked};

  static String unnamed(int status) => 'HTTP_$status';

  static bool namesNothing(String code) => code.startsWith('HTTP_');
}
