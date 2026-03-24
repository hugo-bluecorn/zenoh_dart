/// The type of a zenoh entity (router, peer, or client).
///
/// Values correspond to zenoh-c bitmask values:
/// router=1, peer=2, client=4.
enum WhatAmI {
  /// A zenoh router.
  router,

  /// A zenoh peer.
  peer,

  /// A zenoh client.
  client;

  /// Maps a zenoh-c integer bitmask value to a [WhatAmI] enum value.
  ///
  /// Throws [ArgumentError] if [value] is not 1, 2, or 4.
  static WhatAmI fromInt(int value) {
    switch (value) {
      case 1:
        return WhatAmI.router;
      case 2:
        return WhatAmI.peer;
      case 4:
        return WhatAmI.client;
      default:
        throw ArgumentError('Invalid WhatAmI value: $value');
    }
  }
}
