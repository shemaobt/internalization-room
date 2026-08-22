/// How far a request would get right now.
///
/// The check has always computed this — radio first, then the room — and then threw the
/// answer away one line before anyone could be told. A wrong address on a perfect wi-fi
/// and a tablet with no network at all produced the same face, and the room said the
/// internet had gone.
enum RoomReach { fine, noNetwork, roomSilent }
