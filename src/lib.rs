use fsrs::{self, ComputeParametersInput};

// Opaque handle for FSRS - not exported to C header
pub struct FSRS(pub fsrs::FSRS);

#[repr(C)]
pub struct FsrsItems {
    pub items: *mut FSRSItem,
    pub len: usize,
}

#[repr(C)]
pub struct FsrsReviews {
    pub reviews: *mut FSRSReview,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone)]
pub struct MemoryState {
    pub stability: f32,
    pub difficulty: f32,
}

#[repr(C)]
#[derive(Clone)]
pub struct ItemState {
    pub memory: MemoryState,
    pub interval: f32,
}

#[repr(C)]
#[derive(Clone)]
pub struct NextStates {
    pub again: ItemState,
    pub hard: ItemState,
    pub good: ItemState,
    pub easy: ItemState,
}

#[repr(C)]
#[derive(Clone)]
pub struct FSRSItem {
    pub reviews: *mut FSRSReview,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct FSRSReview {
    pub rating: u32,
    pub delta_t: u32,
}

/// Returns the number of default parameters in FSRS (21).
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_parameters_len() -> usize {
    fsrs::DEFAULT_PARAMETERS.len()
}

/// Copies the default FSRS parameters into the provided buffer (must be at least 21 floats).
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

/// Returns the default decay parameter (FSRS6_DEFAULT_DECAY).
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_default_decay() -> f32 {
    fsrs::FSRS6_DEFAULT_DECAY
}

/// Computes the retrievability (probability of recall between 0.0 and 1.0)
/// for a given memory state, elapsed days, and decay parameter.
///
/// # Safety
///
/// The `memory_state` pointer must be a valid pointer to a MemoryState instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_current_retrievability(
    memory_state: *const MemoryState,
    days_elapsed: f32,
    decay: f32,
) -> f32 {
    if memory_state.is_null() {
        return 0.0;
    }
    let state = unsafe { (*memory_state).clone().into() };
    fsrs::current_retrievability(state, days_elapsed, decay)
}

/// Creates a new FSRS instance. Returns NULL if parameters are invalid.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_new(parameters: *const f32, len: usize) -> *const FSRS {
    let instance = if parameters.is_null() || len == 0 {
        fsrs::FSRS::default()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(parameters, len) };
        match fsrs::FSRS::new(slice) {
            Ok(model) => model,
            Err(_) => return std::ptr::null(),
        }
    };
    Box::into_raw(Box::new(FSRS(instance)))
}

/// Frees the memory allocated for an FSRS instance.
///
/// # Safety
///
/// The `fsrs` pointer must be a valid pointer to an FSRS instance created by `fsrs_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_free(fsrs: *const FSRS) {
    if !fsrs.is_null() {
        unsafe { drop(Box::from_raw(fsrs as *mut FSRS)) };
    }
}

/// Computes the next states for a card. Returns NULL if inputs are invalid.
///
/// # Safety
///
/// The `fsrs` pointer must be a valid pointer to an FSRS instance.
/// The `memory_state` pointer must be a valid pointer to a MemoryState instance (or NULL for a new card).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states(
    fsrs: *const FSRS,
    memory_state: *mut MemoryState,
    desired_retention: f32,
    days_elapsed: u32,
) -> *mut NextStates {
    if fsrs.is_null() {
        return std::ptr::null_mut();
    }
    let fsrs = unsafe { &*fsrs };
    let memory_state = if memory_state.is_null() {
        None
    } else {
        Some(unsafe { (*memory_state).clone().into() })
    };
    match fsrs.0.next_states(memory_state, desired_retention, days_elapsed) {
        Ok(next_states) => Box::into_raw(Box::new(next_states.into())),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Frees the memory allocated for a NextStates instance.
///
/// # Safety
///
/// The `next_states` pointer must be a valid pointer to a NextStates instance created by `fsrs_next_states`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states_free(next_states: *mut NextStates) {
    if !next_states.is_null() {
        unsafe { drop(Box::from_raw(next_states)) };
    }
}

/// Get the `again` state from NextStates.
///
/// # Safety
///
/// The `next_states` pointer must be a valid pointer to a NextStates instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states_again(next_states: *const NextStates) -> ItemState {
    unsafe { (*next_states).again.clone() }
}

/// Get the `hard` state from NextStates.
///
/// # Safety
///
/// The `next_states` pointer must be a valid pointer to a NextStates instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states_hard(next_states: *const NextStates) -> ItemState {
    unsafe { (*next_states).hard.clone() }
}

/// Get the `good` state from NextStates.
///
/// # Safety
///
/// The `next_states` pointer must be a valid pointer to a NextStates instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states_good(next_states: *const NextStates) -> ItemState {
    unsafe { (*next_states).good.clone() }
}

/// Get the `easy` state from NextStates.
///
/// # Safety
///
/// The `next_states` pointer must be a valid pointer to a NextStates instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_next_states_easy(next_states: *const NextStates) -> ItemState {
    unsafe { (*next_states).easy.clone() }
}

/// Computes the parameters for a given train set.
///
/// # Safety
///
/// The `fsrs` pointer must be a valid pointer to an FSRS instance.
/// The `train_set` pointer must be a valid pointer to an array of FSRSItem.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_compute_parameters(
    _fsrs: *const FSRS,
    train_set: *mut FsrsItems,
    enable_short_term: bool,
    num_relearning_steps: i32,
) -> *mut f32 {
    let train_set: Vec<fsrs::FSRSItem> = unsafe {
        std::slice::from_raw_parts((*train_set).items, (*train_set).len)
            .iter()
            .map(|item| (*item).clone().into())
            .collect()
    };
    if train_set.is_empty() {
        return std::ptr::null_mut();
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
        Ok(params) => Box::into_raw(params.into_boxed_slice()) as *mut f32,
        Err(_) => std::ptr::null_mut(),
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ModelEvaluation {
    pub log_loss: f32,
    pub rmse_bins: f32,
}

/// Evaluates the model using the provided training set.
///
/// # Safety
///
/// The `fsrs` pointer must be a valid pointer to an FSRS instance.
/// The `train_set` pointer must be a valid pointer to an array of FSRSItem.
/// The `out_eval` pointer must be a valid pointer to a ModelEvaluation instance.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_evaluate(
    fsrs: *const FSRS,
    train_set: *mut FsrsItems,
    out_eval: *mut ModelEvaluation,
) -> bool {
    if fsrs.is_null() || train_set.is_null() || out_eval.is_null() {
        return false;
    }
    let fsrs = unsafe { &*fsrs };
    let train_set: Vec<fsrs::FSRSItem> = unsafe {
        std::slice::from_raw_parts((*train_set).items, (*train_set).len)
            .iter()
            .map(|item| (*item).clone().into())
            .collect()
    };
    if train_set.is_empty() {
        return false;
    }
    match fsrs.0.evaluate(train_set, |_| true) {
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

/// Frees the memory allocated for the parameters.
///
/// # Safety
///
/// The `params` pointer must be a valid pointer to the parameters created by `fsrs_compute_parameters`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_parameters_free(params: *mut f32) {
    if !params.is_null() {
        unsafe { drop(Box::from_raw(params)) };
    }
}

/// Creates a new MemoryState instance.
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_memory_state_new(stability: f32, difficulty: f32) -> *mut MemoryState {
    Box::into_raw(Box::new(MemoryState {
        stability,
        difficulty,
    }))
}

/// Frees the memory allocated for a MemoryState instance.
///
/// # Safety
///
/// The `memory_state` pointer must be a valid pointer to a MemoryState instance created by `fsrs_memory_state_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_memory_state_free(memory_state: *mut MemoryState) {
    if !memory_state.is_null() {
        unsafe { drop(Box::from_raw(memory_state)) };
    }
}

/// Creates a new FSRSItem instance.
///
/// # Safety
///
/// The `reviews` pointer must be a valid pointer to an array of FSRSReview.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_item_new(reviews: *mut FsrsReviews) -> *mut FSRSItem {
    let review_slice = unsafe { std::slice::from_raw_parts((*reviews).reviews, (*reviews).len) };
    let review_vec: Vec<FSRSReview> = review_slice.to_vec();
    let review_box = review_vec.into_boxed_slice();
    let reviews_ptr = Box::into_raw(review_box) as *mut FSRSReview;
    let len = unsafe { (*reviews).len };

    Box::into_raw(Box::new(FSRSItem {
        reviews: reviews_ptr,
        len,
    }))
}

/// Frees the memory allocated for an FSRSItem instance.
///
/// # Safety
///
/// The `item` pointer must be a valid pointer to an FSRSItem instance created by `fsrs_item_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_item_free(item: *mut FSRSItem) {
    if !item.is_null() {
        let item = unsafe { Box::from_raw(item) };
        if !item.reviews.is_null() {
            unsafe {
                let _ = Box::from_raw(std::ptr::slice_from_raw_parts_mut(item.reviews, item.len));
            }
        }
    }
}

/// Creates a new FSRSReview instance.
#[unsafe(no_mangle)]
pub extern "C" fn fsrs_review_new(rating: u32, delta_t: u32) -> *mut FSRSReview {
    Box::into_raw(Box::new(FSRSReview { rating, delta_t }))
}

/// Frees the memory allocated for an FSRSReview instance.
///
/// # Safety
///
/// The `review` pointer must be a valid pointer to an FSRSReview instance created by `fsrs_review_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fsrs_review_free(review: *mut FSRSReview) {
    if !review.is_null() {
        unsafe { drop(Box::from_raw(review)) };
    }
}

// Conversion functions between internal fsrs types and C-compatible types
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

impl From<FSRSItem> for fsrs::FSRSItem {
    fn from(item: FSRSItem) -> Self {
        let reviews = unsafe {
            std::slice::from_raw_parts(item.reviews, item.len)
                .iter()
                .map(|r| (*r).into())
                .collect()
        };
        fsrs::FSRSItem { reviews }
    }
}
