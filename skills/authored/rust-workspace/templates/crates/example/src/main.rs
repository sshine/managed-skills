// These docs are spliced into README.md as its CLI section; the prose around it
// is hand-written in README.tpl at the repository root.

//! Say hello, once per greeting.
//!
//! ## Usage
//!
//! ```console
//! $ example world
//! Hello, world!
//!
//! $ example --count 2 world
//! Hello, world! (1/2)
//! Hello, world! (2/2)
//! ```
//!
//! A `--count` of zero is treated as one, because a greeting nobody sees is a
//! surprising result for a command whose only job is to print one.
//!
//! ## Exit codes
//!
//! `0` when every greeting was printed, `2` when the arguments did not parse.

use std::process::ExitCode;

use clap::Parser;

#[derive(Debug, Parser)]
#[command(version, about)]
struct Args {
    /// Name to greet
    name: String,

    /// How many times to greet, once per line
    #[arg(short, long, default_value_t = 1)]
    count: usize,
}

fn main() -> ExitCode {
    let args = Args::parse();
    let count = args.count.max(1);

    for greeting in 1..=count {
        if count == 1 {
            println!("Hello, {}!", args.name);
        } else {
            println!("Hello, {}! ({}/{})", args.name, greeting, count);
        }
    }

    ExitCode::SUCCESS
}
