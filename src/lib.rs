//! C ABI over the `fsrs` crate, consumed by the Dart bindings.
//!
//! Conventions:
//! - Every fallible function returns a [`Status`] and writes results through
//!   `out_*` pointers. Outputs are only written on [`Status::Ok`].
//! - Model versions cross the boundary as plain `u32` (`6` or `7`) so that an
//!   unexpected value from the caller is rejected instead of being UB.
//! - Time is always expressed in days as `f32` and may be fractional.

use fsrs::{ComputeParametersInput, ComputeParametersVersion, FSRSError, ModelVersion};

const FSRS6: u32 = 6;
const FSRS7: u32 = 7;

/// Opaque handle for an FSRS model instance.
pub struct FSRS {
    inner: fsrs::FSRS,
    /// After `check_and_fill_parameters`.
    parameters: Vec<f32>,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Ok = 0,
    /// A required pointer argument was NULL.
    NullPointer = 1,
    /// Model parameters are malformed (wrong count, non-finite values, ...).
    InvalidParameters = 2,
    /// Some other argument is out of range (retention, elapsed days, rating, ...).
    InvalidInput = 3,
    /// The training set is empty or has too few usable reviews.
    NotEnoughData = 4,
    /// The output buffer is shorter than the result.
    BufferTooSmall = 5,
    /// Any other failure inside the FSRS engine.
    Failed = 6,
}

impl From<FSRSError> for Status {
    fn from(error: FSRSError) -> Self {
        match error {
            FSRSError::InvalidParameters => Status::InvalidParameters,
            FSRSError::InvalidInput | FSRSError::InvalidDeckSize => Status::InvalidInput,
            FSRSError::NotEnoughData => Status::NotEnoughData,
            FSRSError::Interrupted | FSRSError::OptimalNotFound => Status::Failed,
        }
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MemoryState {
    pub stability: f32,
    pub difficulty: f32,
    /// The fast stability trace of FSRS-7. Ignored by FSRS-6 models, which
    /// always report it equal to `stability`.
    pub stability_fast: f32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ItemState {
    pub memory: MemoryState,
    /// Interval in days (fractional).
    pub interval: f32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct NextStates {
    pub again: ItemState,
    pub hard: ItemState,
    pub good: ItemState,
    pub easy: ItemState,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct Review {
    /// 1 = again, 2 = hard, 3 = good, 4 = easy.
    pub rating: u32,
    /// Days since the previous review (fractional). Must be 0 for the first review.
    pub delta_t: f32,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct TrainingItem {
    pub reviews: *const Review,
    pub len: usize,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct TrainingSet {
    pub items: *const TrainingItem,
    pub len: usize,
    /// NULL or `len` values.
    pub card_ids: *const i64,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ModelEvaluation {
    pub log_loss: f32,
    pub rmse_bins: f32,
}

fn default_parameters(version: u32) -> Option<&'static [f32]> {
    match version {
        FSRS6 => Some(&fsrs::FSRS6_DEFAULT_PARAMETERS),
        FSRS7 => Some(&fsrs::DEFAULT_PARAMETERS),
        _ => None,
    }
}

fn version_number(version: ModelVersion) -> u32 {
    match version {
        ModelVersion::Fsrs6 => FSRS6,
        ModelVersion::Fsrs7 => FSRS7,
    }
}

fn is_retention(value: f32) -> bool {
    value.is_finite() && value > 0.0 && value < 1.0
}

fn is_days(value: f32) -> bool {
    value.is_finite() && value >= 0.0
}

unsafe fn write_floats(
    values: &[f32],
    out: *mut f32,
    out_len: usize,
    out_written: *mut usize,
) -> Status {
    if out.is_null() || out_written.is_null() {
        return Status::NullPointer;
    }
    if out_len < values.len() {
        return Status::BufferTooSmall;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(values.as_ptr(), out, values.len());
        *out_written = values.len();
    }
    Status::Ok
}

unsafe fn handle<'a>(fsrs: *const FSRS) -> Option<&'a FSRS> {
    unsafe { fsrs.as_ref() }
}

impl FSRS {
    /// Validates `state` and sets `stability_fast = stability` for FSRS-6.
    fn memory(&self, state: &MemoryState) -> Result<fsrs::MemoryState, Status> {
        let valid = state.stability.is_finite()
            && state.stability > 0.0
            && state.difficulty.is_finite()
            && state.stability_fast.is_finite()
            && state.stability_fast > 0.0;
        if !valid {
            return Err(Status::InvalidInput);
        }
        let stability_fast = match self.inner.version() {
            ModelVersion::Fsrs6 => state.stability,
            ModelVersion::Fsrs7 => state.stability_fast,
        };
        Ok(fsrs::MemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
            stability_fast,
        })
    }

    unsafe fn optional_memory(
        &self,
        state: *const MemoryState,
    ) -> Result<Option<fsrs::MemoryState>, Status> {
        match unsafe { state.as_ref() } {
            None => Ok(None),
            Some(state) => self.memory(state).map(Some),
        }
    }
}

unsafe fn read_reviews(
    reviews: *const Review,
    len: usize,
) -> Result<Vec<fsrs::FSRSReview>, Status> {
    if len == 0 {
        return Ok(Vec::new());
    }
    if reviews.is_null() {
        return Err(Status::NullPointer);
    }
    unsafe { std::slice::from_raw_parts(reviews, len) }
        .iter()
        .map(|review| {
            if !(1..=4).contains(&review.rating) || !is_days(review.delta_t) {
                return Err(Status::InvalidInput);
            }
            Ok(fsrs::FSRSReview {
                rating: review.rating,
                delta_t: review.delta_t,
            })
        })
        .collect()
}

struct ReadTrainingSet {
    items: Vec<fsrs::FSRSItem>,
    card_ids: Option<Vec<i64>>,
}

unsafe fn read_training_set(set: *const TrainingSet) -> Result<ReadTrainingSet, Status> {
    let Some(set) = (unsafe { set.as_ref() }) else {
        return Err(Status::NullPointer);
    };
    if set.len == 0 {
        return Err(Status::NotEnoughData);
    }
    if set.items.is_null() {
        return Err(Status::NullPointer);
    }
    let raw_items = unsafe { std::slice::from_raw_parts(set.items, set.len) };
    let mut items = Vec::with_capacity(raw_items.len());
    for item in raw_items {
        let reviews = unsafe { read_reviews(item.reviews, item.len) }?;
        if reviews.is_empty() {
            return Err(Status::InvalidInput);
        }
        items.push(fsrs::FSRSItem { reviews });
    }
    let card_ids = if set.card_ids.is_null() {
        None
    } else {
        Some(unsafe { std::slice::from_raw_parts(set.card_ids, set.len) }.to_vec())
    };
    Ok(ReadTrainingSet { items, card_ids })
}

/// Returns the number of parameters of a model version (21 for 6, 34 for 7),
/// or 0 for an unknown version.
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_parameters_len(version: u32) -> usize {
    default_parameters(version).map_or(0, <[f32]>::len)
}

/// Copies the default parameters of `version` into `out_params`.
///
/// # Safety
///
/// `out_params` must be valid for writes of `out_len` `f32` values and
/// `out_written` must be valid for one `usize` write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_default_parameters(
    version: u32,
    out_params: *mut f32,
    out_len: usize,
    out_written: *mut usize,
) -> Status {
    let Some(defaults) = default_parameters(version) else {
        return Status::InvalidInput;
    };
    unsafe { write_floats(defaults, out_params, out_len, out_written) }
}

/// Creates a model. Empty parameters select the FSRS-7 defaults; 17, 19 or 21
/// parameters select FSRS-6; 34 select FSRS-7.
///
/// # Safety
///
/// If `len > 0`, `parameters` must be valid for reads of `len` `f32` values.
/// `out_fsrs` must be valid for one pointer write. The returned handle must
/// be released with `fsrs_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_new(
    parameters: *const f32,
    len: usize,
    out_fsrs: *mut *mut FSRS,
) -> Status {
    if out_fsrs.is_null() || (len > 0 && parameters.is_null()) {
        return Status::NullPointer;
    }
    let input: &[f32] = if len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(parameters, len) }
    };
    let filled = match fsrs::check_and_fill_parameters(input) {
        Ok(filled) => filled,
        Err(error) => return error.into(),
    };
    let inner = match fsrs::FSRS::new(&filled) {
        Ok(inner) => inner,
        Err(error) => return error.into(),
    };
    let handle = Box::new(FSRS {
        inner,
        parameters: filled,
    });
    unsafe { *out_fsrs = Box::into_raw(handle) };
    Status::Ok
}

/// Releases a model created by `fsrs_new`. NULL is ignored.
///
/// # Safety
///
/// `fsrs` must be NULL or a handle from `fsrs_new` that was not freed yet.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_free(fsrs: *mut FSRS) {
    if !fsrs.is_null() {
        unsafe { drop(Box::from_raw(fsrs)) };
    }
}

/// Returns the model version (6 or 7), or 0 for a NULL handle.
///
/// # Safety
///
/// `fsrs` must be NULL or a live handle from `fsrs_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_version(fsrs: *const FSRS) -> u32 {
    unsafe { handle(fsrs) }.map_or(0, |fsrs| version_number(fsrs.inner.version()))
}

/// Copies the model's canonical parameters (filled to the version's full
/// length) into `out_params`.
///
/// # Safety
///
/// `fsrs` must be a live handle; `out_params` must be valid for `out_len`
/// writes and `out_written` for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_parameters(
    fsrs: *const FSRS,
    out_params: *mut f32,
    out_len: usize,
    out_written: *mut usize,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    unsafe { write_floats(&fsrs.parameters, out_params, out_len, out_written) }
}

/// Computes the memory states and intervals for all four ratings.
///
/// # Safety
///
/// `fsrs` must be a live handle, `memory_state` NULL (new card) or valid for
/// reads, and `out_states` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states(
    fsrs: *const FSRS,
    memory_state: *const MemoryState,
    desired_retention: f32,
    days_elapsed: f32,
    out_states: *mut NextStates,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    if out_states.is_null() {
        return Status::NullPointer;
    }
    if !is_retention(desired_retention) || !is_days(days_elapsed) {
        return Status::InvalidInput;
    }
    let memory = match unsafe { fsrs.optional_memory(memory_state) } {
        Ok(memory) => memory,
        Err(status) => return status,
    };
    match fsrs
        .inner
        .next_states_with_elapsed_days(memory, desired_retention, days_elapsed)
    {
        Ok(states) => {
            unsafe { *out_states = states.into() };
            Status::Ok
        }
        Err(error) => error.into(),
    }
}

/// Computes the probability of recall after `days_elapsed` days.
///
/// # Safety
///
/// `fsrs` must be a live handle, `memory_state` valid for reads and
/// `out_retrievability` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_retrievability(
    fsrs: *const FSRS,
    memory_state: *const MemoryState,
    days_elapsed: f32,
    out_retrievability: *mut f32,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    let Some(state) = (unsafe { memory_state.as_ref() }) else {
        return Status::NullPointer;
    };
    if out_retrievability.is_null() {
        return Status::NullPointer;
    }
    if !is_days(days_elapsed) {
        return Status::InvalidInput;
    }
    let memory = match fsrs.memory(state) {
        Ok(memory) => memory,
        Err(status) => return status,
    };
    let retrievability = match fsrs.inner.version() {
        // `fsrs::FSRS::current_retrievability` rounds elapsed time to whole
        // days for FSRS-6 (legacy training semantics). Use the continuous
        // curve instead so that recall decays smoothly within a day, as in 0.2.
        ModelVersion::Fsrs6 => {
            let decay = fsrs.parameters[20].clamp(0.1, 0.8);
            fsrs::current_retrievability(memory, days_elapsed, decay)
        }
        ModelVersion::Fsrs7 => fsrs.inner.current_retrievability(memory, days_elapsed),
    };
    unsafe { *out_retrievability = retrievability };
    Status::Ok
}

/// Computes the interval in days at which recall drops to `desired_retention`.
///
/// # Safety
///
/// `fsrs` must be a live handle, `memory_state` valid for reads and
/// `out_days` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_interval(
    fsrs: *const FSRS,
    memory_state: *const MemoryState,
    desired_retention: f32,
    out_days: *mut f32,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    let Some(state) = (unsafe { memory_state.as_ref() }) else {
        return Status::NullPointer;
    };
    if out_days.is_null() {
        return Status::NullPointer;
    }
    if !is_retention(desired_retention) {
        return Status::InvalidInput;
    }
    let memory = match fsrs.memory(state) {
        Ok(memory) => memory,
        Err(status) => return status,
    };
    unsafe {
        *out_days = fsrs
            .inner
            .next_interval_for_state(memory, desired_retention)
    };
    Status::Ok
}

/// Replays a review history and returns the resulting memory state.
///
/// `starting_state` may be NULL (the first review starts a new card) or the
/// state of a truncated history, e.g. from `fsrs_memory_state_from_sm2`.
///
/// # Safety
///
/// `fsrs` must be a live handle, `reviews` valid for `len` reads,
/// `starting_state` NULL or valid for reads, `out_state` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_memory_state(
    fsrs: *const FSRS,
    reviews: *const Review,
    len: usize,
    starting_state: *const MemoryState,
    out_state: *mut MemoryState,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    if out_state.is_null() {
        return Status::NullPointer;
    }
    let reviews = match unsafe { read_reviews(reviews, len) } {
        Ok(reviews) if reviews.is_empty() => return Status::InvalidInput,
        Ok(reviews) => reviews,
        Err(status) => return status,
    };
    let start = match unsafe { fsrs.optional_memory(starting_state) } {
        Ok(start) => start,
        Err(status) => return status,
    };
    match fsrs.inner.memory_state(fsrs::FSRSItem { reviews }, start) {
        Ok(state) => {
            unsafe { *out_state = state.into() };
            Status::Ok
        }
        Err(error) => error.into(),
    }
}

/// Converts an SM-2 card (ease factor, interval in days) into a memory state.
/// FSRS-7 ignores `ease_factor`.
///
/// # Safety
///
/// `fsrs` must be a live handle and `out_state` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_memory_state_from_sm2(
    fsrs: *const FSRS,
    ease_factor: f32,
    interval: f32,
    sm2_retention: f32,
    out_state: *mut MemoryState,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    if out_state.is_null() {
        return Status::NullPointer;
    }
    let valid = ease_factor.is_finite()
        && ease_factor > 0.0
        && interval.is_finite()
        && interval > 0.0
        && is_retention(sm2_retention);
    if !valid {
        return Status::InvalidInput;
    }
    match fsrs
        .inner
        .memory_state_from_sm2(ease_factor, interval, sm2_retention)
    {
        Ok(state) => {
            unsafe { *out_state = state.into() };
            Status::Ok
        }
        Err(error) => error.into(),
    }
}

/// Optimizes parameters of `version` (6 or 7) for a training set.
///
/// `num_relearning_steps < 0` means "unknown". On success writes the
/// parameters (21 or 34 values) and their count.
///
/// # Safety
///
/// `training_set` must point to a valid `TrainingSet` whose pointers are valid
/// for the declared lengths; `out_params` must be valid for `out_len` writes
/// and `out_written` for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_compute_parameters(
    training_set: *const TrainingSet,
    version: u32,
    enable_short_term: bool,
    num_relearning_steps: i32,
    out_params: *mut f32,
    out_len: usize,
    out_written: *mut usize,
) -> Status {
    let model_version = match version {
        FSRS6 => ComputeParametersVersion::Fsrs6,
        FSRS7 => ComputeParametersVersion::Fsrs7,
        _ => return Status::InvalidInput,
    };
    if out_params.is_null() || out_written.is_null() {
        return Status::NullPointer;
    }
    if out_len < fsrs_parameters_len(version) {
        return Status::BufferTooSmall;
    }
    let set = match unsafe { read_training_set(training_set) } {
        Ok(set) => set,
        Err(status) => return status,
    };
    let input = ComputeParametersInput {
        train_set: set.items,
        card_ids: set.card_ids,
        enable_short_term,
        model_version,
        num_relearning_steps: usize::try_from(num_relearning_steps).ok(),
        ..Default::default()
    };
    match fsrs::compute_parameters(input) {
        Ok(params) => unsafe { write_floats(&params, out_params, out_len, out_written) },
        Err(error) => error.into(),
    }
}

/// Measures how well the model predicts the recalls in a training set.
///
/// # Safety
///
/// `fsrs` must be a live handle, `training_set` as in
/// `fsrs_compute_parameters`, and `out_eval` valid for one write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_evaluate(
    fsrs: *const FSRS,
    training_set: *const TrainingSet,
    out_eval: *mut ModelEvaluation,
) -> Status {
    let Some(fsrs) = (unsafe { handle(fsrs) }) else {
        return Status::NullPointer;
    };
    if out_eval.is_null() {
        return Status::NullPointer;
    }
    let set = match unsafe { read_training_set(training_set) } {
        Ok(set) => set,
        Err(status) => return status,
    };
    let result = match set.card_ids {
        Some(card_ids) => fsrs
            .inner
            .evaluate_with_card_ids(set.items, card_ids, |_| true),
        None => fsrs.inner.evaluate(set.items, |_| true),
    };
    match result {
        Ok(eval) => {
            unsafe {
                *out_eval = ModelEvaluation {
                    log_loss: eval.log_loss,
                    rmse_bins: eval.rmse_bins,
                };
            }
            Status::Ok
        }
        Err(error) => error.into(),
    }
}

impl From<fsrs::MemoryState> for MemoryState {
    fn from(state: fsrs::MemoryState) -> Self {
        MemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
            stability_fast: state.stability_fast,
        }
    }
}

impl From<fsrs::ItemState> for ItemState {
    fn from(state: fsrs::ItemState) -> Self {
        ItemState {
            memory: state.memory.into(),
            interval: state.interval,
        }
    }
}

impl From<fsrs::NextStates> for NextStates {
    fn from(states: fsrs::NextStates) -> Self {
        NextStates {
            again: states.again.into(),
            hard: states.hard.into(),
            good: states.good.into(),
            easy: states.easy.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr::{null, null_mut};

    struct Model(*mut FSRS);

    impl Model {
        fn new(params: &[f32]) -> Result<Self, Status> {
            let mut ptr = null_mut();
            match unsafe { fsrs_new(params.as_ptr(), params.len(), &mut ptr) } {
                Status::Ok => Ok(Model(ptr)),
                status => Err(status),
            }
        }

        fn next_states(
            &self,
            memory: Option<MemoryState>,
            days: f32,
        ) -> Result<NextStates, Status> {
            let mut out = std::mem::MaybeUninit::<NextStates>::uninit();
            let memory_ptr = memory.as_ref().map_or(null(), |m| m as *const _);
            match unsafe { fsrs_next_states(self.0, memory_ptr, 0.9, days, out.as_mut_ptr()) } {
                Status::Ok => Ok(unsafe { out.assume_init() }),
                status => Err(status),
            }
        }

        fn parameters(&self) -> Vec<f32> {
            let mut out = [0.0f32; 64];
            let mut written = 0;
            let status =
                unsafe { fsrs_parameters(self.0, out.as_mut_ptr(), out.len(), &mut written) };
            assert_eq!(status, Status::Ok);
            out[..written].to_vec()
        }
    }

    impl Drop for Model {
        fn drop(&mut self) {
            unsafe { fsrs_free(self.0) };
        }
    }

    fn reviews(pairs: &[(u32, f32)]) -> Vec<Review> {
        pairs
            .iter()
            .map(|&(rating, delta_t)| Review { rating, delta_t })
            .collect()
    }

    #[test]
    fn parameter_lengths_and_defaults() {
        assert_eq!(fsrs_parameters_len(6), 21);
        assert_eq!(fsrs_parameters_len(7), 34);
        assert_eq!(fsrs_parameters_len(5), 0);

        let mut out = [0.0f32; 34];
        let mut written = 0;
        unsafe {
            assert_eq!(
                fsrs_default_parameters(7, out.as_mut_ptr(), out.len(), &mut written),
                Status::Ok
            );
            assert_eq!(&out[..written], &fsrs::DEFAULT_PARAMETERS[..]);
            assert_eq!(
                fsrs_default_parameters(6, out.as_mut_ptr(), 20, &mut written),
                Status::BufferTooSmall
            );
            assert_eq!(
                fsrs_default_parameters(8, out.as_mut_ptr(), out.len(), &mut written),
                Status::InvalidInput
            );
        }
    }

    #[test]
    fn version_follows_parameter_count() {
        let v7 = Model::new(&[]).unwrap();
        assert_eq!(unsafe { fsrs_version(v7.0) }, 7);
        assert_eq!(v7.parameters(), fsrs::DEFAULT_PARAMETERS.to_vec());

        let v6 = Model::new(&fsrs::FSRS6_DEFAULT_PARAMETERS).unwrap();
        assert_eq!(unsafe { fsrs_version(v6.0) }, 6);

        let v5 = Model::new(&fsrs::FSRS6_DEFAULT_PARAMETERS[..19]).unwrap();
        assert_eq!(unsafe { fsrs_version(v5.0) }, 6);
        assert_eq!(v5.parameters().len(), 21);

        assert_eq!(Model::new(&[1.0; 5]).err(), Some(Status::InvalidParameters));
        let mut nan = fsrs::DEFAULT_PARAMETERS;
        nan[3] = f32::NAN;
        assert_eq!(Model::new(&nan).err(), Some(Status::InvalidParameters));
    }

    #[test]
    fn null_pointers_are_rejected() {
        unsafe {
            assert_eq!(fsrs_new(null(), 3, &mut null_mut()), Status::NullPointer);
            assert_eq!(fsrs_new(null(), 0, null_mut()), Status::NullPointer);
            assert_eq!(fsrs_version(null()), 0);
            fsrs_free(null_mut());

            let mut states = std::mem::MaybeUninit::<NextStates>::uninit();
            assert_eq!(
                fsrs_next_states(null(), null(), 0.9, 0.0, states.as_mut_ptr()),
                Status::NullPointer
            );
            let model = Model::new(&[]).unwrap();
            let mut r = 0.0;
            assert_eq!(
                fsrs_retrievability(model.0, null(), 1.0, &mut r),
                Status::NullPointer
            );
            let mut eval = ModelEvaluation {
                log_loss: 0.0,
                rmse_bins: 0.0,
            };
            assert_eq!(
                fsrs_evaluate(model.0, null(), &mut eval),
                Status::NullPointer
            );
        }
    }

    #[test]
    fn invalid_inputs_are_rejected() {
        let model = Model::new(&[]).unwrap();
        let state = MemoryState {
            stability: 3.0,
            difficulty: 5.0,
            stability_fast: 2.0,
        };
        let mut out = std::mem::MaybeUninit::<NextStates>::uninit();
        unsafe {
            for retention in [0.0, 1.0, f32::NAN] {
                assert_eq!(
                    fsrs_next_states(model.0, null(), retention, 0.0, out.as_mut_ptr()),
                    Status::InvalidInput
                );
            }
            for days in [-1.0, f32::INFINITY] {
                assert_eq!(
                    fsrs_next_states(model.0, &state, 0.9, days, out.as_mut_ptr()),
                    Status::InvalidInput
                );
            }
            let bad = MemoryState {
                stability: 0.0,
                ..state
            };
            assert_eq!(
                fsrs_next_states(model.0, &bad, 0.9, 1.0, out.as_mut_ptr()),
                Status::InvalidInput
            );
        }
    }

    #[test]
    fn fractional_elapsed_days_matter_for_fsrs7() {
        let model = Model::new(&[]).unwrap();
        let first = model.next_states(None, 0.0).unwrap().good.memory;
        let same_day = model.next_states(Some(first), 0.0).unwrap().good.memory;
        let six_hours = model.next_states(Some(first), 0.25).unwrap().good.memory;
        assert_ne!(same_day, six_hours);
        assert!(model.next_states(None, 0.0).unwrap().good.interval.fract() != 0.0);
    }

    #[test]
    fn fsrs6_ignores_stability_fast() {
        let model = Model::new(&fsrs::FSRS6_DEFAULT_PARAMETERS).unwrap();
        let a = MemoryState {
            stability: 5.0,
            difficulty: 5.0,
            stability_fast: 5.0,
        };
        let b = MemoryState {
            stability_fast: 1.0,
            ..a
        };
        let sa = model.next_states(Some(a), 3.0).unwrap();
        let sb = model.next_states(Some(b), 3.0).unwrap();
        assert_eq!(sa.good.memory, sb.good.memory);
        assert_eq!(sa.good.memory.stability, sa.good.memory.stability_fast);
    }

    #[test]
    fn retrievability_and_interval_agree() {
        for params in [&[][..], &fsrs::FSRS6_DEFAULT_PARAMETERS[..]] {
            let model = Model::new(params).unwrap();
            let memory = model.next_states(None, 0.0).unwrap().good.memory;
            let mut days = 0.0;
            let mut r = 0.0;
            unsafe {
                assert_eq!(
                    fsrs_next_interval(model.0, &memory, 0.9, &mut days),
                    Status::Ok
                );
                assert_eq!(
                    fsrs_retrievability(model.0, &memory, days, &mut r),
                    Status::Ok
                );
            }
            assert!((r - 0.9).abs() < 1e-3, "r = {r}, days = {days}");

            let mut r0 = 0.0;
            unsafe { fsrs_retrievability(model.0, &memory, 0.0, &mut r0) };
            // FSRS-7 caps retrievability at 0.99999.
            assert!((r0 - 1.0).abs() < 1e-4, "r0 = {r0}");
        }
    }

    /// Guards the hardcoded FSRS-6 decay bounds against changes in the fsrs
    /// parameter clipper.
    #[test]
    fn fsrs6_retrievability_matches_engine_on_whole_days() {
        for decay in [0.05, 0.1542, 0.35, 0.95] {
            let mut params = fsrs::FSRS6_DEFAULT_PARAMETERS;
            params[20] = decay;
            let model = Model::new(&params).unwrap();
            let engine = fsrs::FSRS::new(&params).unwrap();
            let memory = MemoryState {
                stability: 7.5,
                difficulty: 5.0,
                stability_fast: 7.5,
            };
            for days in [0.0f32, 1.0, 3.0, 10.0, 100.0] {
                let mut ours = 0.0;
                unsafe { fsrs_retrievability(model.0, &memory, days, &mut ours) };
                let expected = engine.current_retrievability(
                    fsrs::MemoryState {
                        stability: 7.5,
                        difficulty: 5.0,
                        stability_fast: 7.5,
                    },
                    days,
                );
                assert!(
                    (ours - expected).abs() < 1e-6,
                    "decay {decay}, day {days}: {ours} vs {expected}"
                );
            }
            let (mut a, mut b) = (0.0, 0.0);
            unsafe {
                fsrs_retrievability(model.0, &memory, 3.1, &mut a);
                fsrs_retrievability(model.0, &memory, 3.4, &mut b);
            }
            assert!(b < a);
        }
    }

    #[test]
    fn memory_state_matches_replayed_next_states() {
        let model = Model::new(&[]).unwrap();
        let first = model.next_states(None, 0.0).unwrap().good.memory;
        let second = model.next_states(Some(first), 2.5).unwrap().hard.memory;

        let history = reviews(&[(3, 0.0), (2, 2.5)]);
        let mut out = MemoryState {
            stability: 0.0,
            difficulty: 0.0,
            stability_fast: 0.0,
        };
        unsafe {
            assert_eq!(
                fsrs_memory_state(model.0, history.as_ptr(), history.len(), null(), &mut out),
                Status::Ok
            );
            assert_eq!(
                fsrs_memory_state(model.0, history.as_ptr(), 0, null(), &mut out),
                Status::InvalidInput
            );
            let bad = reviews(&[(5, 0.0)]);
            assert_eq!(
                fsrs_memory_state(model.0, bad.as_ptr(), bad.len(), null(), &mut out),
                Status::InvalidInput
            );
        }
        let close = |a: f32, b: f32| (a - b).abs() <= 1e-4 * a.abs().max(1.0);
        assert!(
            close(out.stability, second.stability),
            "{out:?} vs {second:?}"
        );
        assert!(close(out.difficulty, second.difficulty));
        assert!(close(out.stability_fast, second.stability_fast));
    }

    #[test]
    fn sm2_import_works_for_both_versions() {
        for params in [&[][..], &fsrs::FSRS6_DEFAULT_PARAMETERS[..]] {
            let model = Model::new(params).unwrap();
            let mut out = MemoryState {
                stability: 0.0,
                difficulty: 0.0,
                stability_fast: 0.0,
            };
            unsafe {
                assert_eq!(
                    fsrs_memory_state_from_sm2(model.0, 2.5, 30.0, 0.9, &mut out),
                    Status::Ok
                );
                assert_eq!(
                    fsrs_memory_state_from_sm2(model.0, 2.5, 0.0, 0.9, &mut out),
                    Status::InvalidInput
                );
            }
            assert!(out.stability > 1.0);
        }
    }

    fn sample_training_set() -> (Vec<Vec<Review>>, Vec<i64>) {
        let cards = [
            reviews(&[(3, 0.0), (3, 2.0), (3, 6.0), (4, 15.0)]),
            reviews(&[(2, 0.0), (1, 1.0), (3, 0.5), (3, 3.0)]),
            reviews(&[(3, 0.0), (1, 4.0), (3, 1.0), (3, 5.0)]),
            reviews(&[(4, 0.0), (3, 8.0), (3, 20.0), (2, 40.0)]),
        ];
        let mut items = Vec::new();
        let mut ids = Vec::new();
        for (id, card) in cards.iter().enumerate() {
            for end in 2..=card.len() {
                items.push(card[..end].to_vec());
                ids.push(id as i64);
            }
        }
        (items, ids)
    }

    fn training_set(
        items: &[Vec<Review>],
        card_ids: Option<&[i64]>,
    ) -> (Vec<TrainingItem>, TrainingSet) {
        let raw: Vec<TrainingItem> = items
            .iter()
            .map(|r| TrainingItem {
                reviews: r.as_ptr(),
                len: r.len(),
            })
            .collect();
        let set = TrainingSet {
            items: raw.as_ptr(),
            len: raw.len(),
            card_ids: card_ids.map_or(null(), <[i64]>::as_ptr),
        };
        (raw, set)
    }

    #[test]
    fn compute_parameters_for_both_versions() {
        let (items, ids) = sample_training_set();
        let (_raw, set) = training_set(&items, Some(&ids));
        for (version, expected) in [(6, 21), (7, 34)] {
            let mut out = [0.0f32; 34];
            let mut written = 0;
            let status = unsafe {
                fsrs_compute_parameters(
                    &set,
                    version,
                    true,
                    -1,
                    out.as_mut_ptr(),
                    out.len(),
                    &mut written,
                )
            };
            assert_eq!(status, Status::Ok, "version {version}");
            assert_eq!(written, expected);
            assert!(out[..written].iter().all(|v| v.is_finite()));
            let model = Model::new(&out[..written]).unwrap();
            assert_eq!(unsafe { fsrs_version(model.0) }, version);
        }
    }

    #[test]
    fn compute_parameters_rejects_bad_requests() {
        let (items, _) = sample_training_set();
        let (_raw, set) = training_set(&items, None);
        let mut out = [0.0f32; 34];
        let mut written = 0;
        unsafe {
            assert_eq!(
                fsrs_compute_parameters(&set, 7, true, -1, out.as_mut_ptr(), 21, &mut written),
                Status::BufferTooSmall
            );
            assert_eq!(
                fsrs_compute_parameters(&set, 5, true, -1, out.as_mut_ptr(), 34, &mut written),
                Status::InvalidInput
            );
            let empty = TrainingSet {
                items: null(),
                len: 0,
                card_ids: null(),
            };
            assert_eq!(
                fsrs_compute_parameters(&empty, 7, true, -1, out.as_mut_ptr(), 34, &mut written),
                Status::NotEnoughData
            );
            let empty_item = [TrainingItem {
                reviews: null(),
                len: 0,
            }];
            let with_empty = TrainingSet {
                items: empty_item.as_ptr(),
                len: 1,
                card_ids: null(),
            };
            assert_eq!(
                fsrs_compute_parameters(
                    &with_empty,
                    7,
                    true,
                    -1,
                    out.as_mut_ptr(),
                    34,
                    &mut written
                ),
                Status::InvalidInput
            );
        }
    }

    #[test]
    fn evaluate_with_and_without_card_ids() {
        let (items, ids) = sample_training_set();
        let model = Model::new(&[]).unwrap();
        for card_ids in [None, Some(&ids[..])] {
            let (_raw, set) = training_set(&items, card_ids);
            let mut eval = ModelEvaluation {
                log_loss: 0.0,
                rmse_bins: 0.0,
            };
            assert_eq!(
                unsafe { fsrs_evaluate(model.0, &set, &mut eval) },
                Status::Ok
            );
            assert!(eval.log_loss.is_finite() && eval.log_loss > 0.0);
            assert!(eval.rmse_bins.is_finite());
        }
    }
}
