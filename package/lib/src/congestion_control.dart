/// Controls the behavior when the outgoing buffer is full.
enum CongestionControl {
  /// Block the publisher until space is available.
  block,

  /// Drop the message if the buffer is full.
  drop,
}
