#ifndef _FSRS_DART_H
#define _FSRS_DART_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>


typedef enum fsrs_Status {
  fsrs_Status_Ok = 0,
  /**
   * A required pointer argument was NULL.
   */
  fsrs_Status_NullPointer = 1,
  /**
   * Model parameters are malformed (wrong count, non-finite values, ...).
   */
  fsrs_Status_InvalidParameters = 2,
  /**
   * Some other argument is out of range (retention, elapsed days, rating, ...).
   */
  fsrs_Status_InvalidInput = 3,
  /**
   * The training set is empty or has too few usable reviews.
   */
  fsrs_Status_NotEnoughData = 4,
  /**
   * The output buffer is shorter than the result.
   */
  fsrs_Status_BufferTooSmall = 5,
  /**
   * Any other failure inside the FSRS engine.
   */
  fsrs_Status_Failed = 6,
} fsrs_Status;

/**
 * Opaque handle for an FSRS model instance.
 */
typedef struct fsrs_FSRS fsrs_FSRS;

typedef struct fsrs_Review {
  /**
   * 1 = again, 2 = hard, 3 = good, 4 = easy.
   */
  uint32_t rating;
  /**
   * Days since the previous review (fractional). Must be 0 for the first review.
   */
  float delta_t;
} fsrs_Review;

typedef struct fsrs_TrainingItem {
  const struct fsrs_Review *reviews;
  size_t len;
} fsrs_TrainingItem;

typedef struct fsrs_TrainingSet {
  const struct fsrs_TrainingItem *items;
  size_t len;
  /**
   * NULL or `len` values.
   */
  const int64_t *card_ids;
} fsrs_TrainingSet;

typedef struct fsrs_ModelEvaluation {
  float log_loss;
  float rmse_bins;
} fsrs_ModelEvaluation;

typedef struct fsrs_MemoryState {
  float stability;
  float difficulty;
  /**
   * The fast stability trace of FSRS-7. Ignored by FSRS-6 models, which
   * always report it equal to `stability`.
   */
  float stability_fast;
} fsrs_MemoryState;

typedef struct fsrs_ItemState {
  struct fsrs_MemoryState memory;
  /**
   * Interval in days (fractional).
   */
  float interval;
} fsrs_ItemState;

typedef struct fsrs_NextStates {
  struct fsrs_ItemState again;
  struct fsrs_ItemState hard;
  struct fsrs_ItemState good;
  struct fsrs_ItemState easy;
} fsrs_NextStates;

/**
 * Optimizes parameters of `version` (6 or 7) for a training set.
 *
 * `num_relearning_steps < 0` means "unknown". On success writes the
 * parameters (21 or 34 values) and their count.
 *
 * # Safety
 *
 * `training_set` must point to a valid `TrainingSet` whose pointers are valid
 * for the declared lengths; `out_params` must be valid for `out_len` writes
 * and `out_written` for one write.
 */
enum fsrs_Status fsrs_compute_parameters(const struct fsrs_TrainingSet *training_set,
                                         uint32_t version,
                                         bool enable_short_term,
                                         int32_t num_relearning_steps,
                                         float *out_params,
                                         size_t out_len,
                                         size_t *out_written);

/**
 * Copies the default parameters of `version` into `out_params`.
 *
 * # Safety
 *
 * `out_params` must be valid for writes of `out_len` `f32` values and
 * `out_written` must be valid for one `usize` write.
 */
enum fsrs_Status fsrs_default_parameters(uint32_t version,
                                         float *out_params,
                                         size_t out_len,
                                         size_t *out_written);

/**
 * Measures how well the model predicts the recalls in a training set.
 *
 * # Safety
 *
 * `fsrs` must be a live handle, `training_set` as in
 * `fsrs_compute_parameters`, and `out_eval` valid for one write.
 */
enum fsrs_Status fsrs_evaluate(const struct fsrs_FSRS *fsrs,
                               const struct fsrs_TrainingSet *training_set,
                               struct fsrs_ModelEvaluation *out_eval);

/**
 * Releases a model created by `fsrs_new`. NULL is ignored.
 *
 * # Safety
 *
 * `fsrs` must be NULL or a handle from `fsrs_new` that was not freed yet.
 */
void fsrs_free(struct fsrs_FSRS *fsrs);

/**
 * Replays a review history and returns the resulting memory state.
 *
 * `starting_state` may be NULL (the first review starts a new card) or the
 * state of a truncated history, e.g. from `fsrs_memory_state_from_sm2`.
 *
 * # Safety
 *
 * `fsrs` must be a live handle, `reviews` valid for `len` reads,
 * `starting_state` NULL or valid for reads, `out_state` valid for one write.
 */
enum fsrs_Status fsrs_memory_state(const struct fsrs_FSRS *fsrs,
                                   const struct fsrs_Review *reviews,
                                   size_t len,
                                   const struct fsrs_MemoryState *starting_state,
                                   struct fsrs_MemoryState *out_state);

/**
 * Converts an SM-2 card (ease factor, interval in days) into a memory state.
 * FSRS-7 ignores `ease_factor`.
 *
 * # Safety
 *
 * `fsrs` must be a live handle and `out_state` valid for one write.
 */
enum fsrs_Status fsrs_memory_state_from_sm2(const struct fsrs_FSRS *fsrs,
                                            float ease_factor,
                                            float interval,
                                            float sm2_retention,
                                            struct fsrs_MemoryState *out_state);

/**
 * Creates a model. Empty parameters select the FSRS-7 defaults; 17, 19 or 21
 * parameters select FSRS-6; 34 select FSRS-7.
 *
 * # Safety
 *
 * If `len > 0`, `parameters` must be valid for reads of `len` `f32` values.
 * `out_fsrs` must be valid for one pointer write. The returned handle must
 * be released with `fsrs_free`.
 */
enum fsrs_Status fsrs_new(const float *parameters, size_t len, struct fsrs_FSRS **out_fsrs);

/**
 * Computes the interval in days at which recall drops to `desired_retention`.
 *
 * # Safety
 *
 * `fsrs` must be a live handle, `memory_state` valid for reads and
 * `out_days` valid for one write.
 */
enum fsrs_Status fsrs_next_interval(const struct fsrs_FSRS *fsrs,
                                    const struct fsrs_MemoryState *memory_state,
                                    float desired_retention,
                                    float *out_days);

/**
 * Computes the memory states and intervals for all four ratings.
 *
 * # Safety
 *
 * `fsrs` must be a live handle, `memory_state` NULL (new card) or valid for
 * reads, and `out_states` valid for one write.
 */
enum fsrs_Status fsrs_next_states(const struct fsrs_FSRS *fsrs,
                                  const struct fsrs_MemoryState *memory_state,
                                  float desired_retention,
                                  float days_elapsed,
                                  struct fsrs_NextStates *out_states);

/**
 * Copies the model's canonical parameters (filled to the version's full
 * length) into `out_params`.
 *
 * # Safety
 *
 * `fsrs` must be a live handle; `out_params` must be valid for `out_len`
 * writes and `out_written` for one write.
 */
enum fsrs_Status fsrs_parameters(const struct fsrs_FSRS *fsrs,
                                 float *out_params,
                                 size_t out_len,
                                 size_t *out_written);

/**
 * Returns the number of parameters of a model version (21 for 6, 34 for 7),
 * or 0 for an unknown version.
 */
size_t fsrs_parameters_len(uint32_t version);

/**
 * Computes the probability of recall after `days_elapsed` days.
 *
 * # Safety
 *
 * `fsrs` must be a live handle, `memory_state` valid for reads and
 * `out_retrievability` valid for one write.
 */
enum fsrs_Status fsrs_retrievability(const struct fsrs_FSRS *fsrs,
                                     const struct fsrs_MemoryState *memory_state,
                                     float days_elapsed,
                                     float *out_retrievability);

/**
 * Returns the model version (6 or 7), or 0 for a NULL handle.
 *
 * # Safety
 *
 * `fsrs` must be NULL or a live handle from `fsrs_new`.
 */
uint32_t fsrs_version(const struct fsrs_FSRS *fsrs);

#endif  /* _FSRS_DART_H */
