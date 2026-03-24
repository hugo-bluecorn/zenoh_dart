/// The priority of a zenoh message.
///
/// Values are ordered from highest priority ([realTime]) to lowest
/// ([background]). The zenoh-c integer values are `index + 1` (1–7).
enum Priority {
  realTime,
  interactiveHigh,
  interactiveLow,
  dataHigh,
  data,
  dataLow,
  background,
}
