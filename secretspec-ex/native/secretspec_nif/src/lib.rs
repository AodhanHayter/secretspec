//! Rustler NIF for the Elixir SDK.
//!
//! A thin wrapper over `secretspec::resolve_json` / `call_json`, the same
//! JSON-in/JSON-out boundary the C ABI uses. The Elixir layer
//! (`lib/secretspec.ex`) does the request/response marshaling and exposes the
//! builder API.
//!
//! Resolution can launch provider CLIs and hit the network, so every call runs
//! on a dirty I/O scheduler instead of blocking a normal BEAM scheduler.

/// Resolve secrets from a JSON request, returning the JSON response envelope
/// (`{"ok": true, "response": ...}` or `{"ok": false, "error": ...}`).
#[rustler::nif(schedule = "DirtyIo")]
fn resolve(request_json: &str) -> String {
    secretspec::resolve_json(request_json)
}

/// Process a versioned native operation request, including inline specs.
#[rustler::nif(schedule = "DirtyIo")]
fn call(request_json: &str) -> String {
    secretspec::call_json(request_json)
}

/// The NIF's version (tracks the crate version).
#[rustler::nif]
fn abi_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

rustler::init!("Elixir.SecretSpec.Native");
