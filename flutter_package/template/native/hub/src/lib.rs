//! This `hub` crate is the
//! entry point of the Rust logic.

mod messages;
mod sample_functions;

// use tokio_with_wasm::alias as tokio; // Uncomment this line to target the web.

rinf::write_interface!();

// You can go with any async runtime, not just tokio's.
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Spawn concurrent tasks.
    // Always use non-blocking async functions like `tokio::fs::File::open`.
    // If you must use blocking code, use `tokio::task::spawn_blocking`
    // or the equivalent provided by your async library.
    tokio::spawn(sample_functions::communicate());

    // Keep the main function running until Dart shutdown.
    rinf::dart_shutdown().await;
}
