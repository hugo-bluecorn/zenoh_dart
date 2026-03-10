//
// Copyright (c) 2024 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//
// clang-format off
#ifdef DOCS
#define ALIGN(n)
#define ZENOHC_API
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Status of SHM buffer allocation operation.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef enum zc_buf_alloc_status_t {
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Allocation ok
   */
  ZC_BUF_ALLOC_STATUS_OK = 0,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Allocation error
   */
  ZC_BUF_ALLOC_STATUS_ALLOC_ERROR = 1,
#endif
} zc_buf_alloc_status_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Allocation errors
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef enum z_alloc_error_t {
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Defragmentation needed.
   */
  Z_ALLOC_ERROR_NEED_DEFRAGMENT,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * The provider is out of memory.
   */
  Z_ALLOC_ERROR_OUT_OF_MEMORY,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Other error.
   */
  Z_ALLOC_ERROR_OTHER,
#endif
} z_alloc_error_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Status of SHM buffer layouting + allocation operation.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef enum zc_buf_layout_alloc_status_t {
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Allocation ok
   */
  ZC_BUF_LAYOUT_ALLOC_STATUS_OK = 0,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Allocation error
   */
  ZC_BUF_LAYOUT_ALLOC_STATUS_ALLOC_ERROR = 1,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Layouting error
   */
  ZC_BUF_LAYOUT_ALLOC_STATUS_LAYOUT_ERROR = 2,
#endif
} zc_buf_layout_alloc_status_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Layouting errors
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef enum z_layout_error_t {
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Layout arguments are incorrect.
   */
  Z_LAYOUT_ERROR_INCORRECT_LAYOUT_ARGS,
#endif
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
  /**
   * Layout incompatible with provider.
   */
  Z_LAYOUT_ERROR_PROVIDER_INCOMPATIBLE_LAYOUT,
#endif
} z_layout_error_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned ZShmMut slice.
 */
typedef struct ALIGN(8) z_owned_shm_mut_t {
  uint8_t _0[80];
} z_owned_shm_mut_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A result of SHM buffer allocation operation.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_buf_alloc_result_t {
  enum zc_buf_alloc_status_t status;
  struct z_owned_shm_mut_t buf;
  enum z_alloc_error_t error;
} z_buf_alloc_result_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned ShmProvider's PrecomputedLayout.
 */
typedef struct ALIGN(8) z_loaned_precomputed_layout_t {
  uint8_t _0[40];
} z_loaned_precomputed_layout_t;
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_loaned_precomputed_layout_t z_loaned_alloc_layout_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned ShmProvider's PrecomputedLayout.
 */
typedef struct ALIGN(8) z_owned_precomputed_layout_t {
  uint8_t _0[40];
} z_owned_precomputed_layout_t;
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_owned_precomputed_layout_t z_owned_alloc_layout_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned ShmProvider.
 */
typedef struct ALIGN(8) z_loaned_shm_provider_t {
  uint8_t _0[104];
} z_loaned_shm_provider_t;
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_threadsafe_context_data_t {
  void *ptr;
} zc_threadsafe_context_data_t;
#endif
/**
 * A tread-safe droppable context.
 * Contexts are idiomatically used in C together with callback interfaces to deliver associated state
 * information to each callback.
 *
 * This is a thread-safe context - the associated callbacks may be executed concurrently with the same
 * zc_context_t instance. In other words, all the callbacks associated with this context data MUST be
 * thread-safe.
 *
 * Once moved to zenoh-c ownership, this context is guaranteed to execute delete_fn when deleted.The
 * delete_fn is guaranteed to be executed only once at some point of time after the last associated
 * callback call returns.
 * NOTE: if user doesn't pass the instance of this context to zenoh-c, the delete_fn callback won't
 * be executed.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_threadsafe_context_t {
  struct zc_threadsafe_context_data_t context;
  void (*delete_fn)(void*);
} zc_threadsafe_context_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An AllocAlignment.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_alloc_alignment_t {
  uint8_t pow;
} z_alloc_alignment_t;
#endif
/**
 * A loaned Zenoh data.
 */
typedef struct ALIGN(8) z_loaned_bytes_t {
  uint8_t _0[40];
} z_loaned_bytes_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned ZShm slice.
 */
typedef struct ALIGN(8) z_loaned_shm_t {
  uint8_t _0[80];
} z_loaned_shm_t;
/**
 * A Zenoh data.
 *
 * To minimize copies and reallocations, Zenoh may provide data in several separate buffers.
 */
typedef struct ALIGN(8) z_owned_bytes_t {
  uint8_t _0[40];
} z_owned_bytes_t;
/**
 * A loaned sequence of bytes.
 */
typedef struct ALIGN(8) z_loaned_slice_t {
  uint8_t _0[32];
} z_loaned_slice_t;
/**
 * A loaned string.
 */
typedef struct ALIGN(8) z_loaned_string_t {
  uint8_t _0[32];
} z_loaned_string_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned ZShm slice.
 */
typedef struct ALIGN(8) z_owned_shm_t {
  uint8_t _0[80];
} z_owned_shm_t;
typedef struct ALIGN(8) z_owned_slice_t {
  uint8_t _0[32];
} z_owned_slice_t;
/**
 * The wrapper type for strings allocated by Zenoh.
 */
typedef struct ALIGN(8) z_owned_string_t {
  uint8_t _0[32];
} z_owned_string_t;
/**
 * A contiguous sequence of bytes owned by some other entity.
 */
typedef struct ALIGN(8) z_view_slice_t {
  uint8_t _0[32];
} z_view_slice_t;
/**
 * A reader for payload.
 */
typedef struct ALIGN(8) z_bytes_reader_t {
  uint8_t _0[24];
} z_bytes_reader_t;
/**
 * An loaned writer for payload.
 */
typedef struct ALIGN(8) z_loaned_bytes_writer_t {
  uint8_t _0[64];
} z_loaned_bytes_writer_t;
/**
 * An owned writer for payload.
 */
typedef struct ALIGN(8) z_owned_bytes_writer_t {
  uint8_t _0[64];
} z_owned_bytes_writer_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned cancellation token, which can be used to interrupt GET queries.
 */
typedef struct ALIGN(8) z_loaned_cancellation_token_t {
  uint8_t _0[24];
} z_loaned_cancellation_token_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned cancellation token, which can be used to interrupt GET queries.
 */
typedef struct ALIGN(8) z_owned_cancellation_token_t {
  uint8_t _0[24];
} z_owned_cancellation_token_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned ChunkAllocResult.
 */
typedef struct ALIGN(8) z_owned_chunk_alloc_result_t {
  uint8_t _0[48];
} z_owned_chunk_alloc_result_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Unique segment identifier.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef uint32_t z_segment_id_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Chunk id within it's segment.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef uint32_t z_chunk_id_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A ChunkDescriptor.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_chunk_descriptor_t {
  z_segment_id_t segment;
  z_chunk_id_t chunk;
  size_t len;
} z_chunk_descriptor_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A pointer in SHM Segment.
 */
typedef struct ALIGN(8) z_owned_ptr_in_segment_t {
  uint8_t _0[24];
} z_owned_ptr_in_segment_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An AllocatedChunk.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_allocated_chunk_t {
  struct z_chunk_descriptor_t descriptpr;
  struct z_moved_ptr_in_segment_t *ptr;
} z_allocated_chunk_t;
#endif
/**
 * A loaned Zenoh session.
 */
typedef struct ALIGN(8) z_loaned_session_t {
  uint8_t _0[8];
} z_loaned_session_t;
/**
 * An owned Close handle
 */
typedef struct ALIGN(8) zc_owned_concurrent_close_handle_t {
  uint8_t _0[16];
} zc_owned_concurrent_close_handle_t;
/**
 * A loaned hello message.
 */
typedef struct ALIGN(8) z_loaned_hello_t {
  uint8_t _0[48];
} z_loaned_hello_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_hello_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_hello_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Loaned closure.
 */
typedef struct z_loaned_closure_matching_status_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_matching_status_t;
/**
 * A loaned Zenoh query.
 */
typedef struct ALIGN(8) z_loaned_query_t {
  uint8_t _0[144];
} z_loaned_query_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_query_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_query_t;
/**
 * A loaned reply.
 */
typedef struct ALIGN(8) z_loaned_reply_t {
  uint8_t _0[248];
} z_loaned_reply_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_reply_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_reply_t;
/**
 * A loaned Zenoh sample.
 */
typedef struct ALIGN(8) z_loaned_sample_t {
  uint8_t _0[224];
} z_loaned_sample_t;
/**
 * Loaned closure.
 */
typedef struct z_loaned_closure_sample_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_sample_t;
/**
 * @brief A Zenoh ID.
 *
 * In general, valid Zenoh IDs are LSB-first 128bit unsigned and non-zero integers.
 */
typedef struct ALIGN(1) z_id_t {
  uint8_t id[16];
} z_id_t;
/**
 * @brief Loaned closure.
 */
typedef struct z_loaned_closure_zid_t {
  size_t _0;
  size_t _1;
  size_t _2;
} z_loaned_closure_zid_t;
/**
 * An owned conditional variable.
 *
 * Used in combination with `z_owned_mutex_t` to wake up thread when certain conditions are met.
 */
typedef struct ALIGN(4) z_owned_condvar_t {
  uint8_t _0[8];
} z_owned_condvar_t;
/**
 * A loaned conditional variable.
 */
typedef struct ALIGN(4) z_loaned_condvar_t {
  uint8_t _0[4];
} z_loaned_condvar_t;
/**
 * A loaned mutex.
 */
typedef struct ALIGN(8) z_loaned_mutex_t {
  uint8_t _0[24];
} z_loaned_mutex_t;
/**
 * An owned Zenoh configuration.
 */
typedef struct ALIGN(8) z_owned_config_t {
  uint8_t _0[2008];
} z_owned_config_t;
/**
 * A loaned Zenoh configuration.
 */
typedef struct ALIGN(8) z_loaned_config_t {
  uint8_t _0[2008];
} z_loaned_config_t;
/**
 * A loaned key expression.
 *
 * Key expressions can identify a single key or a set of keys.
 *
 * Examples :
 *    - ``"key/expression"``.
 *    - ``"key/ex*"``.
 *
 * Using `z_declare_keyexpr` allows Zenoh to optimize a key expression,
 * both for local processing and network-wise.
 */
typedef struct ALIGN(8) z_loaned_keyexpr_t {
  uint8_t _0[32];
} z_loaned_keyexpr_t;
/**
 * A Zenoh-allocated <a href="https://zenoh.io/docs/manual/abstractions/#key-expression"> key expression </a>.
 *
 * Key expressions can identify a single key or a set of keys.
 *
 * Examples :
 *    - ``"key/expression"``.
 *    - ``"key/ex*"``.
 *
 * Key expressions can be mapped to numerical ids through `z_declare_keyexpr`
 * for wire and computation efficiency.
 *
 * Internally key expressiobn can be either:
 *   - A plain string expression.
 *   - A pure numerical id.
 *   - The combination of a numerical prefix and a string suffix.
 */
typedef struct ALIGN(8) z_owned_keyexpr_t {
  uint8_t _0[32];
} z_owned_keyexpr_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#publisher"> publisher </a>.
 */
typedef struct ALIGN(8) z_owned_publisher_t {
  uint8_t _0[112];
} z_owned_publisher_t;
/**
 * The <a href="https://zenoh.io/docs/manual/abstractions/#encoding"> encoding </a> of Zenoh data.
 */
typedef struct ALIGN(8) z_owned_encoding_t {
  uint8_t _0[48];
} z_owned_encoding_t;
/**
 * An owned Zenoh querier.
 *
 * Sends queries to matching queryables.
 */
typedef struct ALIGN(8) z_owned_querier_t {
  uint8_t _0[80];
} z_owned_querier_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#queryable"> queryable </a>.
 *
 * Responds to queries sent via `z_get()` with intersecting key expression.
 */
typedef struct ALIGN(8) z_owned_queryable_t {
  uint8_t _0[48];
} z_owned_queryable_t;
/**
 * An owned Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#subscriber"> subscriber </a>.
 *
 * Receives data from publication on intersecting key expressions.
 * Destroying the subscriber cancels the subscription.
 */
typedef struct ALIGN(8) z_owned_subscriber_t {
  uint8_t _0[48];
} z_owned_subscriber_t;
/**
 * A Zenoh <a href="https://zenoh.io/docs/manual/abstractions/#timestamp"> timestamp </a>.
 *
 * It consists of a time generated by a Hybrid Logical Clock (HLC) in NPT64 format and a unique zenoh identifier.
 */
typedef struct ALIGN(8) z_timestamp_t {
  uint8_t _0[24];
} z_timestamp_t;
/**
 * A loaned Zenoh encoding.
 */
typedef struct ALIGN(8) z_loaned_encoding_t {
  uint8_t _0[48];
} z_loaned_encoding_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An entity gloabal id.
 */
typedef struct ALIGN(4) z_entity_global_id_t {
  uint8_t _0[20];
} z_entity_global_id_t;
/**
 * An owned Zenoh fifo query handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_query_t {
  uint8_t _0[8];
} z_owned_fifo_handler_query_t;
/**
 * An owned Zenoh fifo reply handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_reply_t {
  uint8_t _0[8];
} z_owned_fifo_handler_reply_t;
/**
 * An owned Zenoh fifo sample handler.
 */
typedef struct ALIGN(8) z_owned_fifo_handler_sample_t {
  uint8_t _0[8];
} z_owned_fifo_handler_sample_t;
/**
 * An loaned Zenoh fifo query handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_query_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_query_t;
/**
 * An owned Zenoh query received by a queryable.
 *
 * Queries are atomically reference-counted, letting you extract them from the callback that handed them to you by cloning.
 */
typedef struct ALIGN(8) z_owned_query_t {
  uint8_t _0[144];
} z_owned_query_t;
/**
 * An loaned Zenoh fifo reply handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_reply_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_reply_t;
/**
 * An owned reply from a Queryable to a `z_get()`.
 */
typedef struct ALIGN(8) z_owned_reply_t {
  uint8_t _0[248];
} z_owned_reply_t;
/**
 * An loaned Zenoh fifo sample handler.
 */
typedef struct ALIGN(8) z_loaned_fifo_handler_sample_t {
  uint8_t _0[8];
} z_loaned_fifo_handler_sample_t;
/**
 * An owned Zenoh sample.
 *
 * This is a read only type that can only be constructed by cloning a `z_loaned_sample_t`.
 * Like all owned types, it should be freed using z_drop or z_sample_drop.
 */
typedef struct ALIGN(8) z_owned_sample_t {
  uint8_t _0[224];
} z_owned_sample_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A source info.
 */
typedef struct ALIGN(4) z_source_info_t {
  uint8_t _0[24];
} z_source_info_t;
/**
 * An owned Zenoh-allocated hello message returned by a Zenoh entity to a scout message sent with `z_scout()`.
 */
typedef struct ALIGN(8) z_owned_hello_t {
  uint8_t _0[48];
} z_owned_hello_t;
/**
 * An array of maybe-owned non-null terminated strings.
 *
 */
typedef struct ALIGN(8) z_owned_string_array_t {
  uint8_t _0[24];
} z_owned_string_array_t;
/**
 * @brief A liveliness token that can be used to provide the network with information about connectivity to its
 * declarer: when constructed, a PUT sample will be received by liveliness subscribers on intersecting key
 * expressions.
 *
 * A DELETE on the token's key expression will be received by subscribers if the token is destroyed, or if connectivity between the subscriber and the token's creator is lost.
 */
typedef struct ALIGN(8) z_owned_liveliness_token_t {
  uint8_t _0[16];
} z_owned_liveliness_token_t;
/**
 * @brief An owned Zenoh matching listener.
 *
 * A listener that sends notifications when the [`MatchingStatus`] of a publisher or querier changes.
 * Dropping the corresponding publisher, also drops matching listener.
 */
typedef struct ALIGN(8) z_owned_matching_listener_t {
  uint8_t _0[24];
} z_owned_matching_listener_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned MemoryLayout.
 */
typedef struct ALIGN(8) z_owned_memory_layout_t {
  uint8_t _0[16];
} z_owned_memory_layout_t;
/**
 * An owned mutex.
 */
typedef struct ALIGN(8) z_owned_mutex_t {
  uint8_t _0[24];
} z_owned_mutex_t;
/**
 * A Zenoh reply error - a combination of reply error payload and its encoding.
 */
typedef struct ALIGN(8) z_owned_reply_err_t {
  uint8_t _0[88];
} z_owned_reply_err_t;
/**
 * An owned Zenoh ring query handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_query_t {
  uint8_t _0[8];
} z_owned_ring_handler_query_t;
/**
 * An owned Zenoh ring reply handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_reply_t {
  uint8_t _0[8];
} z_owned_ring_handler_reply_t;
/**
 * An owned Zenoh ring sample handler.
 */
typedef struct ALIGN(8) z_owned_ring_handler_sample_t {
  uint8_t _0[8];
} z_owned_ring_handler_sample_t;
/**
 * An owned Zenoh session.
 */
typedef struct ALIGN(8) z_owned_session_t {
  uint8_t _0[8];
} z_owned_session_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned shared ShmProvider.
 */
typedef struct ALIGN(8) z_owned_shared_shm_provider_t {
  uint8_t _0[104];
} z_owned_shared_shm_provider_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned SHM Client.
 */
typedef struct ALIGN(8) z_owned_shm_client_t {
  uint8_t _0[16];
} z_owned_shm_client_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned SHM Client Storage
 */
typedef struct ALIGN(8) z_owned_shm_client_storage_t {
  uint8_t _0[8];
} z_owned_shm_client_storage_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned ShmProvider.
 */
typedef struct ALIGN(8) z_owned_shm_provider_t {
  uint8_t _0[104];
} z_owned_shm_provider_t;
/**
 * An owned Zenoh task.
 */
typedef struct ALIGN(8) z_owned_task_t {
  uint8_t _0[24];
} z_owned_task_t;
/**
 * The view over a string.
 */
typedef struct ALIGN(8) z_view_string_t {
  uint8_t _0[32];
} z_view_string_t;
typedef struct ALIGN(8) z_loaned_liveliness_token_t {
  uint8_t _0[16];
} z_loaned_liveliness_token_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned MemoryLayout.
 */
typedef struct ALIGN(8) z_loaned_memory_layout_t {
  uint8_t _0[16];
} z_loaned_memory_layout_t;
/**
 * A loaned SHM Client Storage.
 */
typedef struct ALIGN(8) z_loaned_shm_client_storage_t {
  uint8_t _0[8];
} z_loaned_shm_client_storage_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned pointer in SHM Segment.
 */
typedef struct ALIGN(8) z_loaned_ptr_in_segment_t {
  uint8_t _0[24];
} z_loaned_ptr_in_segment_t;
/**
 * A loaned Zenoh publisher.
 */
typedef struct ALIGN(8) z_loaned_publisher_t {
  uint8_t _0[112];
} z_loaned_publisher_t;
/**
 * A loaned Zenoh queryable.
 */
typedef struct ALIGN(8) z_loaned_querier_t {
  uint8_t _0[80];
} z_loaned_querier_t;
/**
 * A loaned Zenoh queryable.
 */
typedef struct ALIGN(8) z_loaned_queryable_t {
  uint8_t _0[48];
} z_loaned_queryable_t;
/**
 * A loaned Zenoh reply error.
 */
typedef struct ALIGN(8) z_loaned_reply_err_t {
  uint8_t _0[88];
} z_loaned_reply_err_t;
/**
 * An loaned Zenoh ring query handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_query_t {
  uint8_t _0[8];
} z_loaned_ring_handler_query_t;
/**
 * An loaned Zenoh ring reply handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_reply_t {
  uint8_t _0[8];
} z_loaned_ring_handler_reply_t;
/**
 * An loaned Zenoh ring sample handler.
 */
typedef struct ALIGN(8) z_loaned_ring_handler_sample_t {
  uint8_t _0[8];
} z_loaned_ring_handler_sample_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned shared ShmProvider.
 */
typedef struct ALIGN(8) z_loaned_shared_shm_provider_t {
  uint8_t _0[104];
} z_loaned_shared_shm_provider_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Callbacks for ShmSegment.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_shm_segment_callbacks_t {
  /**
   * Obtain the actual region of memory identified by it's id.
   */
  uint8_t *(*map_fn)(z_chunk_id_t chunk_id, void *context);
} zc_shm_segment_callbacks_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An ShmSegment.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_shm_segment_t {
  struct zc_threadsafe_context_t context;
  struct zc_shm_segment_callbacks_t callbacks;
} z_shm_segment_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Unique protocol identifier.
 * Here is a contract: it is up to user to make sure that incompatible ShmClient
 * and ShmProviderBackend implementations will never use the same ProtocolID.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef uint32_t z_protocol_id_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Callback for ShmClient.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_shm_client_callbacks_t {
  /**
   * Attach to particular shared memory segment
   */
  bool (*attach_fn)(struct z_shm_segment_t *out_segment, z_segment_id_t segment_id, void *context);
  /**
   * ID of SHM Protocol this client implements
   */
  z_protocol_id_t (*id_fn)(void *context);
} zc_shm_client_callbacks_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned list of SHM Clients.
 */
typedef struct ALIGN(8) zc_loaned_shm_client_list_t {
  uint8_t _0[24];
} zc_loaned_shm_client_list_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned ZShmMut slice.
 */
typedef struct ALIGN(8) z_loaned_shm_mut_t {
  uint8_t _0[80];
} z_loaned_shm_mut_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A result of SHM buffer layouting + allocation operation.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct z_buf_layout_alloc_result_t {
  enum zc_buf_layout_alloc_status_t status;
  struct z_owned_shm_mut_t buf;
  enum z_alloc_error_t alloc_error;
  enum z_layout_error_t layout_error;
} z_buf_layout_alloc_result_t;
#endif
/**
 * A non-tread-safe droppable context.
 * Contexts are idiomatically used in C together with callback interfaces to deliver associated state
 * information to each callback.
 *
 * This is a non-thread-safe context - zenoh-c guarantees that associated callbacks that share the same
 * zc_context_t instance will never be executed concurrently. In other words, all the callbacks associated
 * with this context data are not required to be thread-safe.
 *
 * NOTE: Remember that the same callback interfaces associated with different zc_context_t instances can
 * still be executed concurrently. The exact behavior depends on user's application, but we strongly
 * discourage our users from pinning to some specific behavior unless they _really_ understand what they
 * are doing.
 *
 * Once moved to zenoh-c ownership, this context is guaranteed to execute delete_fn when deleted. The
 * delete_fn is guaranteed to be executed only once at some point of time after the last associated
 * callback call returns.
 * NOTE: if user doesn't pass the instance of this context to zenoh-c, the delete_fn callback won't
 * be executed.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_context_t {
  void *context;
  void (*delete_fn)(void*);
} zc_context_t;
#endif
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief Callbacks for ShmProviderBackend.
 */
#if (defined(Z_FEATURE_SHARED_MEMORY) && defined(Z_FEATURE_UNSTABLE_API))
typedef struct zc_shm_provider_backend_callbacks_t {
  void (*alloc_fn)(struct z_owned_chunk_alloc_result_t *out_result,
                   const struct z_loaned_memory_layout_t *layout,
                   void *context);
  void (*free_fn)(const struct z_chunk_descriptor_t *chunk, void *context);
  size_t (*defragment_fn)(void *context);
  size_t (*available_fn)(void *context);
  void (*layout_for_fn)(struct z_owned_memory_layout_t *layout, void *context);
  z_protocol_id_t (*id_fn)(void *context);
} zc_shm_provider_backend_callbacks_t;
#endif
/**
 * A loaned string array.
 */
typedef struct ALIGN(8) z_loaned_string_array_t {
  uint8_t _0[24];
} z_loaned_string_array_t;
/**
 * A loaned Zenoh subscriber.
 */
typedef struct ALIGN(8) z_loaned_subscriber_t {
  uint8_t _0[48];
} z_loaned_subscriber_t;
/**
 * A user allocated string, viewed as a key expression.
 */
typedef struct ALIGN(8) z_view_keyexpr_t {
  uint8_t _0[32];
} z_view_keyexpr_t;
/**
 * Loaned closure.
 */
typedef struct zc_loaned_closure_log_t {
  size_t _0;
  size_t _1;
  size_t _2;
} zc_loaned_closure_log_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned list of SHM Clients.
 */
typedef struct ALIGN(8) zc_owned_shm_client_list_t {
  uint8_t _0[24];
} zc_owned_shm_client_list_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned Zenoh advanced publisher.
 */
typedef struct ALIGN(8) ze_loaned_advanced_publisher_t {
  uint8_t _0[232];
} ze_loaned_advanced_publisher_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned Zenoh advanced publisher.
 *
 * In addition to publishing the data,
 * it also maintains the storage, allowing matching subscribers to retrive missed samples.
 */
typedef struct ALIGN(8) ze_owned_advanced_publisher_t {
  uint8_t _0[232];
} ze_owned_advanced_publisher_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned Zenoh advanced subscriber.
 */
typedef struct ALIGN(8) ze_loaned_advanced_subscriber_t {
  uint8_t _0[152];
} ze_loaned_advanced_subscriber_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned Zenoh advanced subscriber.
 *
 * In addition to receiving the data it is subscribed to,
 * it is also able to receive notifications regarding missed samples and/or automatically recover them.
 */
typedef struct ALIGN(8) ze_owned_advanced_subscriber_t {
  uint8_t _0[152];
} ze_owned_advanced_subscriber_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned Zenoh publication cache.
 *
 * Used to store publications on intersecting key expressions. Can be queried later via `z_get()` to retrieve this data
 * (for example by `ze_owned_querying_subscriber_t`).
 */
typedef struct ALIGN(8) ze_owned_publication_cache_t {
  uint8_t _0[128];
} ze_owned_publication_cache_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief An owned Zenoh querying subscriber.
 *
 * In addition to receiving the data it is subscribed to,
 * it also will fetch data from a Queryable at startup and peridodically (using  `ze_querying_subscriber_get()`).
 */
typedef struct ALIGN(8) ze_owned_querying_subscriber_t {
  uint8_t _0[88];
} ze_owned_querying_subscriber_t;
/**
 * @brief A Zenoh serializer.
 */
typedef struct ALIGN(8) ze_deserializer_t {
  uint8_t _0[24];
} ze_deserializer_t;
/**
 * @brief An owned Zenoh serializer.
 */
typedef struct ALIGN(8) ze_owned_serializer_t {
  uint8_t _0[64];
} ze_owned_serializer_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned Zenoh publication cache.
 */
typedef struct ALIGN(8) ze_loaned_publication_cache_t {
  uint8_t _0[128];
} ze_loaned_publication_cache_t;
/**
 * @warning This API has been marked as unstable: it works as advertised, but it may be changed in a future release.
 * @brief A loaned Zenoh querying subscriber.
 */
typedef struct ALIGN(8) ze_loaned_querying_subscriber_t {
  uint8_t _0[88];
} ze_loaned_querying_subscriber_t;
/**
 * @brief A loaned Zenoh serializer.
 */
typedef struct ALIGN(8) ze_loaned_serializer_t {
  uint8_t _0[64];
} ze_loaned_serializer_t;
