#ifndef _FSRS_DART_H
#define _FSRS_DART_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>


/**
 * Opaque handle for an FSRS model instance.
 */
typedef struct fsrs_FSRS fsrs_FSRS;

typedef struct fsrs_FSRSReview {
  uint32_t rating;
  uint32_t delta_t;
} fsrs_FSRSReview;

typedef struct fsrs_FSRSItem {
  const struct fsrs_FSRSReview *reviews;
  size_t len;
} fsrs_FSRSItem;

typedef struct fsrs_FsrsItems {
  const struct fsrs_FSRSItem *items;
  size_t len;
} fsrs_FsrsItems;

typedef struct fsrs_MemoryState {
  float stability;
  float difficulty;
} fsrs_MemoryState;

typedef struct fsrs_ModelEvaluation {
  float log_loss;
  float rmse_bins;
} fsrs_ModelEvaluation;

typedef struct fsrs_ItemState {
  struct fsrs_MemoryState memory;
  float interval;
} fsrs_ItemState;

typedef struct fsrs_NextStates {
  struct fsrs_ItemState again;
  struct fsrs_ItemState hard;
  struct fsrs_ItemState good;
  struct fsrs_ItemState easy;
} fsrs_NextStates;

/**
 * Computes optimized FSRS parameters for a given training set and writes them
 * into `out_params`. Returns `true` on success, `false` on error or invalid inputs.
 *
 * # Safety
 *
 * - `train_set` must be a valid non-null pointer to an `FsrsItems` struct.
 * - `out_params` must be a valid non-null pointer to a writable buffer of at least
 *   `out_len` floats (`out_len >= fsrs_parameters_len()`).
 */
bool fsrs_compute_parameters(const struct fsrs_FsrsItems *train_set,
                             bool enable_short_term,
                             int32_t num_relearning_steps,
                             float *out_params,
                             size_t out_len);

/**
 * Computes the retrievability (probability of recall between 0.0 and 1.0)
 * for a given memory state, elapsed days, and decay parameter.
 *
 * # Safety
 *
 * If non-null, `memory_state` must be a valid pointer to a `MemoryState` instance.
 */
float fsrs_current_retrievability(const struct fsrs_MemoryState *memory_state,
                                  float days_elapsed,
                                  float decay);

/**
 * Returns the decay parameter configured for this FSRS instance, or
 * `FSRS6_DEFAULT_DECAY` if `fsrs` is null.
 *
 * # Safety
 *
 * If non-null, `fsrs` must be a valid pointer to an `FSRS` instance created by `fsrs_new`.
 */
float fsrs_decay(const struct fsrs_FSRS *fsrs);

/**
 * Returns the default decay parameter (`FSRS6_DEFAULT_DECAY`).
 */
float fsrs_default_decay(void);

/**
 * Copies the default FSRS parameters into the provided buffer.
 *
 * # Safety
 *
 * If non-null, `out_params` must be valid for writes of at least
 * `fsrs_parameters_len()` contiguous `f32` values.
 */
void fsrs_default_parameters(float *out_params);

/**
 * Evaluates the model using the provided training set.
 *
 * # Safety
 *
 * - `fsrs` must be a valid non-null pointer to an `FSRS` instance.
 * - `train_set` must be a valid non-null pointer to an `FsrsItems` struct.
 * - `out_eval` must be a valid non-null pointer to a writable `ModelEvaluation` struct.
 */
bool fsrs_evaluate(const struct fsrs_FSRS *fsrs,
                   const struct fsrs_FsrsItems *train_set,
                   struct fsrs_ModelEvaluation *out_eval);

/**
 * Frees the memory allocated for an FSRS instance.
 *
 * # Safety
 *
 * If non-null, `fsrs` must be a valid pointer to an `FSRS` instance created by `fsrs_new`
 * and must not be freed more than once.
 */
void fsrs_free(struct fsrs_FSRS *fsrs);

/**
 * Creates a new FSRS instance. Returns NULL if parameters are invalid.
 *
 * # Safety
 *
 * If `parameters` is non-null and `len > 0`, `parameters` must be valid for reads
 * of `len` contiguous `f32` values.
 */
struct fsrs_FSRS *fsrs_new(const float *parameters, size_t len);

/**
 * Computes the next states for a card and writes them into `out_states`.
 * Returns `true` on success, `false` if inputs are invalid.
 *
 * # Safety
 *
 * - `fsrs` must be a valid non-null pointer to an `FSRS` instance.
 * - `memory_state` must be a valid pointer to a `MemoryState` instance, or NULL for a new card.
 * - `out_states` must be a valid non-null pointer to a writable `NextStates` struct.
 */
bool fsrs_next_states(const struct fsrs_FSRS *fsrs,
                      const struct fsrs_MemoryState *memory_state,
                      float desired_retention,
                      uint32_t days_elapsed,
                      struct fsrs_NextStates *out_states);

/**
 * Returns the number of default parameters in FSRS (21).
 */
size_t fsrs_parameters_len(void);

#endif  /* _FSRS_DART_H */
