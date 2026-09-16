#ifndef _FSRS_DART_H
#define _FSRS_DART_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>


typedef struct fsrs_FSRS fsrs_FSRS;

typedef struct fsrs_FSRSReview {
  uint32_t rating;
  uint32_t delta_t;
} fsrs_FSRSReview;

typedef struct fsrs_FSRSItem {
  struct fsrs_FSRSReview *reviews;
  size_t len;
} fsrs_FSRSItem;

typedef struct fsrs_FsrsItems {
  struct fsrs_FSRSItem *items;
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

typedef struct fsrs_FsrsReviews {
  struct fsrs_FSRSReview *reviews;
  size_t len;
} fsrs_FsrsReviews;

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
 * Computes the parameters for a given train set.
 *
 * # Safety
 *
 * The `fsrs` pointer must be a valid pointer to an FSRS instance.
 * The `train_set` pointer must be a valid pointer to an array of FSRSItem.
 */
float *fsrs_compute_parameters(const struct fsrs_FSRS *_fsrs,
                               struct fsrs_FsrsItems *train_set,
                               bool enable_short_term,
                               int32_t num_relearning_steps);

/**
 * Computes the retrievability (probability of recall between 0.0 and 1.0)
 * for a given memory state, elapsed days, and decay parameter.
 *
 * # Safety
 *
 * The `memory_state` pointer must be a valid pointer to a MemoryState instance.
 */
float fsrs_current_retrievability(const struct fsrs_MemoryState *memory_state,
                                  float days_elapsed,
                                  float decay);

/**
 * Returns the default decay parameter (FSRS6_DEFAULT_DECAY).
 */
float fsrs_default_decay(void);

/**
 * Copies the default FSRS parameters into the provided buffer (must be at least 21 floats).
 */
void fsrs_default_parameters(float *out_params);

/**
 * Evaluates the model using the provided training set.
 *
 * # Safety
 *
 * The `fsrs` pointer must be a valid pointer to an FSRS instance.
 * The `train_set` pointer must be a valid pointer to an array of FSRSItem.
 * The `out_eval` pointer must be a valid pointer to a ModelEvaluation instance.
 */
bool fsrs_evaluate(const struct fsrs_FSRS *fsrs,
                   struct fsrs_FsrsItems *train_set,
                   struct fsrs_ModelEvaluation *out_eval);

/**
 * Frees the memory allocated for an FSRS instance.
 *
 * # Safety
 *
 * The `fsrs` pointer must be a valid pointer to an FSRS instance created by `fsrs_new`.
 */
void fsrs_free(const struct fsrs_FSRS *fsrs);

/**
 * Frees the memory allocated for an FSRSItem instance.
 *
 * # Safety
 *
 * The `item` pointer must be a valid pointer to an FSRSItem instance created by `fsrs_item_new`.
 */
void fsrs_item_free(struct fsrs_FSRSItem *item);

/**
 * Creates a new FSRSItem instance.
 *
 * # Safety
 *
 * The `reviews` pointer must be a valid pointer to an array of FSRSReview.
 */
struct fsrs_FSRSItem *fsrs_item_new(struct fsrs_FsrsReviews *reviews);

/**
 * Frees the memory allocated for a MemoryState instance.
 *
 * # Safety
 *
 * The `memory_state` pointer must be a valid pointer to a MemoryState instance created by `fsrs_memory_state_new`.
 */
void fsrs_memory_state_free(struct fsrs_MemoryState *memory_state);

/**
 * Creates a new MemoryState instance.
 */
struct fsrs_MemoryState *fsrs_memory_state_new(float stability, float difficulty);

/**
 * Creates a new FSRS instance. Returns NULL if parameters are invalid.
 */
const struct fsrs_FSRS *fsrs_new(const float *parameters, size_t len);

/**
 * Computes the next states for a card. Returns NULL if inputs are invalid.
 *
 * # Safety
 *
 * The `fsrs` pointer must be a valid pointer to an FSRS instance.
 * The `memory_state` pointer must be a valid pointer to a MemoryState instance (or NULL for a new card).
 */
struct fsrs_NextStates *fsrs_next_states(const struct fsrs_FSRS *fsrs,
                                         struct fsrs_MemoryState *memory_state,
                                         float desired_retention,
                                         uint32_t days_elapsed);

/**
 * Get the `again` state from NextStates.
 *
 * # Safety
 *
 * The `next_states` pointer must be a valid pointer to a NextStates instance.
 */
struct fsrs_ItemState fsrs_next_states_again(const struct fsrs_NextStates *next_states);

/**
 * Get the `easy` state from NextStates.
 *
 * # Safety
 *
 * The `next_states` pointer must be a valid pointer to a NextStates instance.
 */
struct fsrs_ItemState fsrs_next_states_easy(const struct fsrs_NextStates *next_states);

/**
 * Frees the memory allocated for a NextStates instance.
 *
 * # Safety
 *
 * The `next_states` pointer must be a valid pointer to a NextStates instance created by `fsrs_next_states`.
 */
void fsrs_next_states_free(struct fsrs_NextStates *next_states);

/**
 * Get the `good` state from NextStates.
 *
 * # Safety
 *
 * The `next_states` pointer must be a valid pointer to a NextStates instance.
 */
struct fsrs_ItemState fsrs_next_states_good(const struct fsrs_NextStates *next_states);

/**
 * Get the `hard` state from NextStates.
 *
 * # Safety
 *
 * The `next_states` pointer must be a valid pointer to a NextStates instance.
 */
struct fsrs_ItemState fsrs_next_states_hard(const struct fsrs_NextStates *next_states);

/**
 * Frees the memory allocated for the parameters.
 *
 * # Safety
 *
 * The `params` pointer must be a valid pointer to the parameters created by `fsrs_compute_parameters`.
 */
void fsrs_parameters_free(float *params);

/**
 * Returns the number of default parameters in FSRS (21).
 */
size_t fsrs_parameters_len(void);

/**
 * Frees the memory allocated for an FSRSReview instance.
 *
 * # Safety
 *
 * The `review` pointer must be a valid pointer to an FSRSReview instance created by `fsrs_review_new`.
 */
void fsrs_review_free(struct fsrs_FSRSReview *review);

/**
 * Creates a new FSRSReview instance.
 */
struct fsrs_FSRSReview *fsrs_review_new(uint32_t rating, uint32_t delta_t);

#endif  /* _FSRS_DART_H */
