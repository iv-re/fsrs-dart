use fsrs::{self, ComputeParametersInput};

/// Opaque handle for an FSRS model instance.
pub struct FSRS {
    inner: fsrs::FSRS,
    decay: f32,
}

#[repr(C)]
pub struct FsrsItems {
    pub items: *const FSRSItem,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MemoryState {
    pub stability: f32,
    pub difficulty: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ItemState {
    pub memory: MemoryState,
    pub interval: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct NextStates {
    pub again: ItemState,
    pub hard: ItemState,
    pub good: ItemState,
    pub easy: ItemState,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct FSRSItem {
    pub reviews: *const FSRSReview,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct FSRSReview {
    pub rating: u32,
    pub delta_t: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ModelEvaluation {
    pub log_loss: f32,
    pub rmse_bins: f32,
}

/// Safely reads an `FsrsItems` C struct into owned `Vec<fsrs::FSRSItem>`,
/// returning `None` if any required pointer is null when `len > 0`.
unsafe fn read_train_set(train_set: *const FsrsItems) -> Option<Vec<fsrs::FSRSItem>> {
    if train_set.is_null() {
        return None;
    }
    let items_ref = unsafe { &*train_set };
    if items_ref.len == 0 {
        return Some(Vec::new());
    }
    if items_ref.items.is_null() {
        return None;
    }

    let raw_items = unsafe { std::slice::from_raw_parts(items_ref.items, items_ref.len) };
    let mut result = Vec::with_capacity(raw_items.len());
    for item in raw_items {
        let reviews = if item.len == 0 {
            Vec::new()
        } else {
            if item.reviews.is_null() {
                return None;
            }
            unsafe { std::slice::from_raw_parts(item.reviews, item.len) }
                .iter()
                .map(|r| (*r).into())
                .collect()
        };
        result.push(fsrs::FSRSItem { reviews });
    }
    Some(result)
}

/// Returns the number of default parameters in FSRS (21).
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_parameters_len() -> usize {
    fsrs::DEFAULT_PARAMETERS.len()
}

/// Copies the default FSRS parameters into the provided buffer.
///
/// # Safety
///
/// If non-null, `out_params` must be valid for writes of at least
/// `fsrs_parameters_len()` contiguous `f32` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_default_parameters(out_params: *mut f32) {
    if !out_params.is_null() {
        unsafe {
            std::ptr::copy_nonoverlapping(
                fsrs::DEFAULT_PARAMETERS.as_ptr(),
                out_params,
                fsrs::DEFAULT_PARAMETERS.len(),
            );
        }
    }
}

/// Returns the default decay parameter (`FSRS6_DEFAULT_DECAY`).
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_default_decay() -> f32 {
    fsrs::FSRS6_DEFAULT_DECAY
}

/// Returns the decay parameter configured for this FSRS instance, or
/// `FSRS6_DEFAULT_DECAY` if `fsrs` is null.
///
/// # Safety
///
/// If non-null, `fsrs` must be a valid pointer to an `FSRS` instance created by `fsrs_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_decay(fsrs: *const FSRS) -> f32 {
    if fsrs.is_null() {
        return fsrs::FSRS6_DEFAULT_DECAY;
    }
    unsafe { (*fsrs).decay }
}

/// Computes the retrievability (probability of recall between 0.0 and 1.0)
/// for a given memory state, elapsed days, and decay parameter.
///
/// # Safety
///
/// If non-null, `memory_state` must be a valid pointer to a `MemoryState` instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_current_retrievability(
    memory_state: *const MemoryState,
    days_elapsed: f32,
    decay: f32,
) -> f32 {
    if memory_state.is_null() {
        return 0.0;
    }
    let state = unsafe { (*memory_state).into() };
    fsrs::current_retrievability(state, days_elapsed, decay)
}

/// Creates a new FSRS instance. Returns NULL if parameters are invalid.
///
/// # Safety
///
/// If `parameters` is non-null and `len > 0`, `parameters` must be valid for reads
/// of `len` contiguous `f32` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_new(parameters: *const f32, len: usize) -> *mut FSRS {
    let (inner, decay) = if parameters.is_null() || len == 0 {
        (fsrs::FSRS::default(), fsrs::FSRS6_DEFAULT_DECAY)
    } else {
        let slice = unsafe { std::slice::from_raw_parts(parameters, len) };
        let filled = match fsrs::check_and_fill_parameters(slice) {
            Ok(params) => params,
            Err(_) => return std::ptr::null_mut(),
        };
        // Match fsrs::FSRS::new parameter clipping for w[20] (decay).
        let decay = filled[20].clamp(0.1, 0.8);
        match fsrs::FSRS::new(&filled) {
            Ok(model) => (model, decay),
            Err(_) => return std::ptr::null_mut(),
        }
    };
    Box::into_raw(Box::new(FSRS { inner, decay }))
}

/// Frees the memory allocated for an FSRS instance.
///
/// # Safety
///
/// If non-null, `fsrs` must be a valid pointer to an `FSRS` instance created by `fsrs_new`
/// and must not be freed more than once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_free(fsrs: *mut FSRS) {
    if !fsrs.is_null() {
        unsafe { drop(Box::from_raw(fsrs)) };
    }
}

/// Computes the next states for a card and writes them into `out_states`.
/// Returns `true` on success, `false` if inputs are invalid.
///
/// # Safety
///
/// - `fsrs` must be a valid non-null pointer to an `FSRS` instance.
/// - `memory_state` must be a valid pointer to a `MemoryState` instance, or NULL for a new card.
/// - `out_states` must be a valid non-null pointer to a writable `NextStates` struct.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states(
    fsrs: *const FSRS,
    memory_state: *const MemoryState,
    desired_retention: f32,
    days_elapsed: u32,
    out_states: *mut NextStates,
) -> bool {
    if fsrs.is_null() || out_states.is_null() {
        return false;
    }
    let fsrs = unsafe { &*fsrs };
    let memory_state = if memory_state.is_null() {
        None
    } else {
        Some(unsafe { (*memory_state).into() })
    };
    match fsrs
        .inner
        .next_states(memory_state, desired_retention, days_elapsed)
    {
        Ok(next_states) => {
            unsafe { *out_states = next_states.into() };
            true
        }
        Err(_) => false,
    }
}

/// Computes optimized FSRS parameters for a given training set and writes them
/// into `out_params`. Returns `true` on success, `false` on error or invalid inputs.
///
/// # Safety
///
/// - `train_set` must be a valid non-null pointer to an `FsrsItems` struct.
/// - `out_params` must be a valid non-null pointer to a writable buffer of at least
///   `out_len` floats (`out_len >= fsrs_parameters_len()`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_compute_parameters(
    train_set: *const FsrsItems,
    enable_short_term: bool,
    num_relearning_steps: i32,
    out_params: *mut f32,
    out_len: usize,
) -> bool {
    if out_params.is_null() || out_len < fsrs::DEFAULT_PARAMETERS.len() {
        return false;
    }
    let Some(train_set) = (unsafe { read_train_set(train_set) }) else {
        return false;
    };
    if train_set.is_empty() {
        return false;
    }
    let num_relearning_steps = if num_relearning_steps >= 0 {
        Some(num_relearning_steps as usize)
    } else {
        None
    };
    match fsrs::compute_parameters(ComputeParametersInput {
        train_set,
        enable_short_term,
        num_relearning_steps,
        ..Default::default()
    }) {
        Ok(params) if params.len() <= out_len => {
            unsafe {
                std::ptr::copy_nonoverlapping(params.as_ptr(), out_params, params.len());
            }
            true
        }
        _ => false,
    }
}

/// Evaluates the model using the provided training set.
///
/// # Safety
///
/// - `fsrs` must be a valid non-null pointer to an `FSRS` instance.
/// - `train_set` must be a valid non-null pointer to an `FsrsItems` struct.
/// - `out_eval` must be a valid non-null pointer to a writable `ModelEvaluation` struct.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_evaluate(
    fsrs: *const FSRS,
    train_set: *const FsrsItems,
    out_eval: *mut ModelEvaluation,
) -> bool {
    if fsrs.is_null() || out_eval.is_null() {
        return false;
    }
    let fsrs = unsafe { &*fsrs };
    let Some(train_set) = (unsafe { read_train_set(train_set) }) else {
        return false;
    };
    if train_set.is_empty() {
        return false;
    }
    match fsrs.inner.evaluate(train_set, |_| true) {
        Ok(eval) => {
            unsafe {
                (*out_eval).log_loss = eval.log_loss;
                (*out_eval).rmse_bins = eval.rmse_bins;
            }
            true
        }
        Err(_) => false,
    }
}

impl From<fsrs::MemoryState> for MemoryState {
    fn from(state: fsrs::MemoryState) -> Self {
        MemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
        }
    }
}

impl From<MemoryState> for fsrs::MemoryState {
    fn from(state: MemoryState) -> Self {
        fsrs::MemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
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

impl From<FSRSReview> for fsrs::FSRSReview {
    fn from(review: FSRSReview) -> Self {
        fsrs::FSRSReview {
            rating: review.rating,
            delta_t: review.delta_t,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn handles_null_and_empty_inputs_safely() {
        unsafe {
            assert_eq!(fsrs_decay(std::ptr::null()), fsrs::FSRS6_DEFAULT_DECAY);
            assert_eq!(
                fsrs_current_retrievability(std::ptr::null(), 1.0, 0.1542),
                0.0
            );
            assert!(!fsrs_next_states(
                std::ptr::null(),
                std::ptr::null(),
                0.9,
                0,
                std::ptr::null_mut(),
            ));

            let mut out = [0.0f32; 21];
            assert!(!fsrs_compute_parameters(
                std::ptr::null(),
                true,
                -1,
                out.as_mut_ptr(),
                out.len(),
            ));
            let empty_items = FsrsItems {
                items: std::ptr::null(),
                len: 0,
            };
            assert!(!fsrs_compute_parameters(
                &empty_items,
                true,
                -1,
                out.as_mut_ptr(),
                out.len(),
            ));

            let fsrs = fsrs_new(std::ptr::null(), 0);
            assert!(!fsrs.is_null());
            let mut eval = ModelEvaluation {
                log_loss: 0.0,
                rmse_bins: 0.0,
            };
            assert!(!fsrs_evaluate(fsrs, &empty_items, &mut eval));
            fsrs_free(fsrs);
        }
    }

    #[test]
    fn exposes_custom_and_fsrs5_decay() {
        unsafe {
            let mut params21 = fsrs::DEFAULT_PARAMETERS;
            params21[20] = 0.35;
            let f21 = fsrs_new(params21.as_ptr(), params21.len());
            assert!(!f21.is_null());
            assert!((fsrs_decay(f21) - 0.35).abs() < 1e-6);
            fsrs_free(f21);

            let params19 = &fsrs::DEFAULT_PARAMETERS[..19];
            let f19 = fsrs_new(params19.as_ptr(), params19.len());
            assert!(!f19.is_null());
            assert!((fsrs_decay(f19) - fsrs::FSRS5_DEFAULT_DECAY).abs() < 1e-6);
            fsrs_free(f19);
        }
    }

    #[test]
    fn compute_parameters_writes_into_caller_buffer() {
        unsafe {
            let reviews1 = [
                FSRSReview { rating: 3, delta_t: 0 },
                FSRSReview { rating: 3, delta_t: 2 },
                FSRSReview { rating: 4, delta_t: 5 },
            ];
            let reviews2 = [
                FSRSReview { rating: 2, delta_t: 0 },
                FSRSReview { rating: 1, delta_t: 1 },
                FSRSReview { rating: 3, delta_t: 3 },
            ];
            let items = [
                FSRSItem {
                    reviews: reviews1.as_ptr(),
                    len: reviews1.len(),
                },
                FSRSItem {
                    reviews: reviews2.as_ptr(),
                    len: reviews2.len(),
                },
            ];
            let train_set = FsrsItems {
                items: items.as_ptr(),
                len: items.len(),
            };
            let mut out = [0.0f32; 21];
            assert!(fsrs_compute_parameters(
                &train_set,
                true,
                -1,
                out.as_mut_ptr(),
                out.len(),
            ));
            assert!(out.iter().all(|v| v.is_finite()));

            // Buffer too small returns false
            let mut small = [0.0f32; 5];
            assert!(!fsrs_compute_parameters(
                &train_set,
                true,
                -1,
                small.as_mut_ptr(),
                small.len(),
            ));
        }
    }
}
