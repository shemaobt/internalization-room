sealed class RoomAnswer<T> {
  const RoomAnswer();
}

final class Answered<T> extends RoomAnswer<T> {
  final T value;

  const Answered(this.value);
}

sealed class RoomFailure extends RoomAnswer<Never> implements Exception {
  const RoomFailure();
}

final class NetworkFailed extends RoomFailure {
  final String reason;

  const NetworkFailed(this.reason);

  @override
  String toString() => 'NetworkFailed: $reason';
}

final class Refused extends RoomFailure {
  final String code;
  final String detail;

  const Refused(this.code, [this.detail = '']);

  @override
  String toString() => 'Refused: $code $detail';
}

final class SessionGone extends RoomFailure {
  const SessionGone();

  @override
  String toString() => 'SessionGone';
}

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

  static const stopsTheRoom = {unauthorized, forbidden, deviceRevoked};

  static String unnamed(int status) => 'HTTP_$status';

  static bool namesNothing(String code) => code.startsWith('HTTP_');
}
