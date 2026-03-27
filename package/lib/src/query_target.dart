/// The target of a get query.
///
/// Values match zenoh-c integer values: bestMatching=0, all=1, allComplete=2.
enum QueryTarget {
  /// Query the best matching queryable.
  bestMatching,

  /// Query all matching queryables.
  all,

  /// Query all matching queryables and wait for all replies.
  allComplete,
}
