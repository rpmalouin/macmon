//! C ABI over the macmon sampler, for UIs that are not Rust.
//!
//! The contract lives in `include/macmon.h`: one sampler object per thread, JSON out, and no
//! panics — every failure is a null return with the reason in [`macmon_last_error`].

use std::cell::RefCell;
use std::ffi::{CString, c_char, c_void};
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

use macmon::procs::ProcSampler;
use macmon::{Metrics, Sampler};

/// Shortest polling interval the sampler accepts, as in the CLI.
const MIN_DURATION_MS: u32 = 100;

thread_local! {
  /// Last error of this thread, NUL-terminated for the C side.
  static LAST_ERROR: RefCell<CString> = RefCell::new(cstring(""));
}

/// A `CString` of `text`, with interior NULs replaced by spaces so the conversion can't fail.
fn cstring(text: &str) -> CString {
  let bytes: Vec<u8> = text.bytes().map(|b| if b == 0 { b' ' } else { b }).collect();
  // SAFETY: `bytes` holds no NUL, which is the invariant `from_vec_unchecked` requires.
  unsafe { CString::from_vec_unchecked(bytes) }
}

/// Record the reason the last call failed, for [`macmon_last_error`].
fn set_error(message: &str) {
  LAST_ERROR.with(|slot| {
    // try_borrow_mut: a panic here would abort a release build, and the message is only a hint.
    if let Ok(mut value) = slot.try_borrow_mut() {
      *value = cstring(message);
    }
  });
}

/// Drop the error of the last call, so a stale message doesn't outlive its failure.
fn clear_error() {
  set_error("");
}

/// The metrics of one sample, with the time they were taken.
#[derive(serde::Serialize)]
struct Sample<'a> {
  /// Unix epoch seconds.
  timestamp: f64,
  #[serde(flatten)]
  metrics: &'a Metrics,
}

/// Now as Unix epoch seconds, 0.0 if the clock is before the epoch.
fn now_seconds() -> f64 {
  SystemTime::now().duration_since(UNIX_EPOCH).map(|since| since.as_secs_f64()).unwrap_or(0.0)
}

/// The sampler behind `sampler`.
///
/// # Safety
///
/// `sampler` must be null or a pointer returned by [`macmon_sampler_new`] that has not been
/// freed yet.
unsafe fn as_sampler<'a>(sampler: *mut c_void) -> Option<&'a mut Sampler> {
  if sampler.is_null() {
    set_error("sampler is null");
    return None;
  }

  Some(unsafe { &mut *sampler.cast::<Sampler>() })
}

/// Serialize `value` for the C side, or report why not.
fn into_json<T: serde::Serialize>(value: &T, what: &str) -> *mut c_char {
  match serde_json::to_string(value) {
    Ok(json) => {
      clear_error();
      cstring(&json).into_raw()
    }
    Err(error) => {
      set_error(&format!("{what}: {error}"));
      ptr::null_mut()
    }
  }
}

/// Create a sampler, or return null with the reason in [`macmon_last_error`].
#[unsafe(no_mangle)]
pub extern "C" fn macmon_sampler_new() -> *mut c_void {
  match Sampler::new() {
    Ok(sampler) => {
      clear_error();
      Box::into_raw(Box::new(sampler)).cast()
    }
    Err(error) => {
      set_error(&format!("sampler: {error}"));
      ptr::null_mut()
    }
  }
}

/// Collect one sample over `duration_ms` and return it as a JSON object, to be released with
/// [`macmon_free`]. Null on failure.
///
/// # Safety
///
/// `sampler` must be a pointer returned by [`macmon_sampler_new`] that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_sampler_next(
  sampler: *mut c_void,
  duration_ms: u32,
) -> *mut c_char {
  let Some(sampler) = (unsafe { as_sampler(sampler) }) else {
    return ptr::null_mut();
  };

  match sampler.get_metrics(duration_ms.max(MIN_DURATION_MS)) {
    Ok(metrics) => into_json(&Sample { timestamp: now_seconds(), metrics: &metrics }, "sample"),
    Err(error) => {
      set_error(&format!("sample: {error}"));
      ptr::null_mut()
    }
  }
}

/// Static machine and frequency-table information as a JSON object, to be released with
/// [`macmon_free`]. Null on failure.
///
/// # Safety
///
/// `sampler` must be a pointer returned by [`macmon_sampler_new`] that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_sampler_soc_json(sampler: *mut c_void) -> *mut c_char {
  let Some(sampler) = (unsafe { as_sampler(sampler) }) else {
    return ptr::null_mut();
  };

  into_json(sampler.get_soc_info(), "soc")
}

/// Release a sampler. Null is ignored.
///
/// # Safety
///
/// `sampler` must be null or a pointer returned by [`macmon_sampler_new`] that has not been
/// freed yet. Freeing it twice, or using it afterwards, is undefined.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_sampler_free(sampler: *mut c_void) {
  if sampler.is_null() {
    return;
  }

  unsafe { drop(Box::from_raw(sampler.cast::<Sampler>())) };
  clear_error();
}

/// The last error of the calling thread, or an empty string. Valid until the next call that
/// sets or clears an error on this thread.
#[unsafe(no_mangle)]
pub extern "C" fn macmon_last_error() -> *const c_char {
  LAST_ERROR.with(|slot| slot.try_borrow().map(|value| value.as_ptr()).unwrap_or(ptr::null()))
}

/// Release a string returned by [`macmon_sampler_next`] or [`macmon_sampler_soc_json`]. Null is
/// ignored.
///
/// # Safety
///
/// `ptr` must be null or a string this library returned, and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_free(ptr: *mut c_char) {
  if ptr.is_null() {
    return;
  }

  unsafe { drop(CString::from_raw(ptr)) };
}

/// One row of the process list, as the C side reads it.
#[derive(serde::Serialize)]
struct ProcRow<'a> {
  pid: i32,
  name: &'a str,
  user: &'a str,
  /// 100% is one busy core, as in Activity Monitor.
  cpu_pct: f32,
  mem_bytes: u64,
  /// Watts, or null when the energy counter is not readable: another user's process, or macOS
  /// before 13.
  power_w: Option<f32>,
  /// Share of the interval the GPU spent on the process.
  gpu_pct: f32,
}

/// The process sampler behind `sampler`.
///
/// # Safety
///
/// `sampler` must be null or a pointer returned by [`macmon_procs_new`] that has not been freed.
unsafe fn as_procs<'a>(sampler: *mut c_void) -> Option<&'a mut ProcSampler> {
  if sampler.is_null() {
    set_error("process sampler is null");
    return None;
  }

  Some(unsafe { &mut *sampler.cast::<ProcSampler>() })
}

/// Create a process sampler, or return null with the reason in [`macmon_last_error`].
#[unsafe(no_mangle)]
pub extern "C" fn macmon_procs_new() -> *mut c_void {
  clear_error();
  Box::into_raw(Box::new(ProcSampler::new())).cast()
}

/// Sample every process and return the busiest `top_n` as a JSON array, to be released with
/// [`macmon_free`]. `top_n` of 0 returns every process. Null on failure.
///
/// CPU and power are rates since the previous call, so a sampler's first call reports them as zero.
///
/// # Safety
///
/// `sampler` must be a pointer returned by [`macmon_procs_new`] that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_procs_next(sampler: *mut c_void, top_n: u32) -> *mut c_char {
  let Some(sampler) = (unsafe { as_procs(sampler) }) else {
    return ptr::null_mut();
  };

  let mut processes = sampler.sample();
  processes.sort_by(|a, b| b.cpu_pct.total_cmp(&a.cpu_pct));
  if top_n > 0 {
    processes.truncate(top_n as usize);
  }

  let rows: Vec<ProcRow<'_>> = processes
    .iter()
    .map(|process| ProcRow {
      pid: process.pid,
      name: &process.name,
      user: &process.user,
      cpu_pct: process.cpu_pct,
      mem_bytes: process.mem_bytes,
      power_w: process.power_w,
      gpu_pct: process.gpu_pct,
    })
    .collect();

  into_json(&rows, "processes")
}

/// Release a process sampler. Null is ignored.
///
/// # Safety
///
/// `sampler` must be null or a pointer returned by [`macmon_procs_new`] that has not been freed
/// yet.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn macmon_procs_free(sampler: *mut c_void) {
  if sampler.is_null() {
    return;
  }

  unsafe { drop(Box::from_raw(sampler.cast::<ProcSampler>())) };
  clear_error();
}

#[cfg(test)]
mod tests {
  use std::ffi::CStr;

  use super::*;

  /// The last error text of this thread.
  fn error_text() -> String {
    let raw = macmon_last_error();
    if raw.is_null() {
      "<none>".to_string()
    } else {
      unsafe { CStr::from_ptr(raw) }.to_string_lossy().into_owned()
    }
  }

  /// Take one sample, as the C side would, and hand back the decoded document.
  fn sample(sampler: *mut c_void, duration_ms: u32) -> serde_json::Value {
    let json = unsafe { macmon_sampler_next(sampler, duration_ms) };
    assert!(!json.is_null(), "no sample: {}", error_text());

    let text = unsafe { CStr::from_ptr(json) }.to_string_lossy().into_owned();
    unsafe { macmon_free(json) };
    serde_json::from_str(&text).expect("the document is JSON")
  }

  #[test]
  fn a_sample_carries_the_pipe_field_names_and_a_timestamp() {
    let sampler = macmon_sampler_new();
    assert!(!sampler.is_null(), "no sampler: {}", error_text());

    let doc = sample(sampler, 100);

    for key in
      ["cpu_power", "cpu_scaled_ratio", "cpu_tiers", "fans", "gpu_freq_mhz", "memory", "temp"]
    {
      assert!(doc.get(key).is_some(), "missing {key}: {doc}");
    }
    assert!(doc["timestamp"].as_f64().is_some_and(|value| value > 0.0), "no timestamp: {doc}");
    // The `pipe` aliases of the v0.7 names are for released consumers, not for new ones.
    assert!(doc.get("gpu_usage").is_none(), "deprecated alias present: {doc}");

    unsafe { macmon_sampler_free(sampler) };
  }

  #[test]
  fn the_soc_document_has_the_chip_and_its_tiers() {
    let sampler = macmon_sampler_new();
    assert!(!sampler.is_null(), "no sampler: {}", error_text());

    let json = unsafe { macmon_sampler_soc_json(sampler) };
    assert!(!json.is_null(), "no soc info: {}", error_text());
    let text = unsafe { CStr::from_ptr(json) }.to_string_lossy().into_owned();
    unsafe { macmon_free(json) };

    let doc: serde_json::Value = serde_json::from_str(&text).expect("the document is JSON");
    assert!(doc["chip_name"].as_str().is_some_and(|name| !name.is_empty()), "no chip: {doc}");
    assert!(doc["cpu_tiers"].as_array().is_some_and(|tiers| !tiers.is_empty()), "no tiers: {doc}");

    unsafe { macmon_sampler_free(sampler) };
  }

  #[test]
  fn consecutive_samples_share_the_sampler_state() {
    let sampler = macmon_sampler_new();
    assert!(!sampler.is_null(), "no sampler: {}", error_text());

    // Two intervals in a row: the second reads the baseline the first left behind.
    let first = sample(sampler, 100);
    let second = sample(sampler, 100);
    assert!(first["gpu_freq_mhz"].is_number());
    assert!(second["gpu_freq_mhz"].is_number());
    assert!(error_text().is_empty(), "stale error: {}", error_text());

    unsafe { macmon_sampler_free(sampler) };
  }

  #[test]
  fn a_null_sampler_reports_an_error_instead_of_crashing() {
    assert!(unsafe { macmon_sampler_next(ptr::null_mut(), 100) }.is_null());
    assert!(!error_text().is_empty(), "no error after sampling a null sampler");

    assert!(unsafe { macmon_sampler_soc_json(ptr::null_mut()) }.is_null());
    assert!(!error_text().is_empty(), "no error after reading null soc info");
  }

  #[test]
  fn freeing_null_is_a_no_op() {
    let sampler = macmon_sampler_new();
    assert!(!sampler.is_null(), "no sampler: {}", error_text());
    let _ = sample(sampler, 100); // clears the error

    unsafe { macmon_sampler_free(ptr::null_mut()) };
    assert!(error_text().is_empty(), "free(null) set an error: {}", error_text());
    unsafe { macmon_free(ptr::null_mut()) };
    assert!(error_text().is_empty(), "free(null) set an error: {}", error_text());

    unsafe { macmon_sampler_free(sampler) };
  }

  /// Take the whole process list, as the C side would, and hand back the decoded array.
  fn processes(sampler: *mut c_void, top_n: u32) -> Vec<serde_json::Value> {
    // The first call of a sampler is a baseline: CPU and power are rates since the previous one.
    let warmup = unsafe { macmon_procs_next(sampler, 0) };
    unsafe { macmon_free(warmup) };

    let json = unsafe { macmon_procs_next(sampler, top_n) };
    assert!(!json.is_null(), "no processes: {}", error_text());
    let text = unsafe { CStr::from_ptr(json) }.to_string_lossy().into_owned();
    unsafe { macmon_free(json) };

    let rows: serde_json::Value = serde_json::from_str(&text).expect("the document is JSON");
    rows.as_array().expect("an array of rows").clone()
  }

  #[test]
  fn processes_come_back_busiest_first_with_the_documented_keys() {
    let sampler = macmon_procs_new();
    assert!(!sampler.is_null());

    let rows = processes(sampler, 8);
    assert!(!rows.is_empty(), "a machine with no processes?");
    assert!(rows.len() <= 8, "top_n 8 returned {} rows", rows.len());

    for key in ["pid", "name", "user", "cpu_pct", "mem_bytes", "power_w", "gpu_pct"] {
      assert!(rows[0].get(key).is_some(), "missing {key}: {}", rows[0]);
    }

    let cpus: Vec<f64> = rows.iter().filter_map(|row| row["cpu_pct"].as_f64()).collect();
    assert_eq!(cpus.len(), rows.len(), "every row carries a cpu_pct");
    assert!(cpus.windows(2).all(|pair| pair[0] >= pair[1]), "not busiest first: {cpus:?}");

    unsafe { macmon_procs_free(sampler) };
  }

  #[test]
  fn every_process_carries_a_name_and_a_user() {
    let sampler = macmon_procs_new();
    assert!(!sampler.is_null());

    for row in processes(sampler, 0) {
      assert!(row["name"].as_str().is_some_and(|name| !name.is_empty()), "no name: {row}");
      assert!(row["user"].as_str().is_some_and(|user| !user.is_empty()), "no user: {row}");
    }

    unsafe { macmon_procs_free(sampler) };
  }

  /// This test's own process reads its energy counter, so its row carries watts rather than null.
  #[test]
  fn our_own_row_carries_a_power_reading() {
    let sampler = macmon_procs_new();
    assert!(!sampler.is_null());

    let rows = processes(sampler, 0);
    let own = rows
      .iter()
      .find(|row| row["pid"].as_i64() == Some(std::process::id() as i64))
      .unwrap_or_else(|| panic!("this process is not in the list of {} rows", rows.len()));
    assert!(own["power_w"].is_number(), "no power for our own process: {own}");

    unsafe { macmon_procs_free(sampler) };
  }

  #[test]
  fn a_null_process_sampler_reports_an_error_instead_of_crashing() {
    assert!(unsafe { macmon_procs_next(ptr::null_mut(), 8) }.is_null());
    assert!(!error_text().is_empty(), "no error after sampling a null sampler");

    unsafe { macmon_procs_free(ptr::null_mut()) };
    assert!(!error_text().is_empty(), "freeing null should not clear an error it did not set");
  }
}
