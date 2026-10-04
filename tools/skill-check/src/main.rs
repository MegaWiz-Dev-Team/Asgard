// Asgard AI Platform
// Copyright (C) 2026 MegaCare Dev
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

use std::path::PathBuf;
use std::process::ExitCode;

const USAGE: &str = "usage: skill-check [--root <asgard-repo>] [--write]

Checks skills/ against skills/SPEC.md. --write first regenerates stale
<!-- skill-check:begin ... --> blocks. Exit 0 = clean, 1 = findings, 2 = error.";

fn main() -> ExitCode {
    let mut root = PathBuf::from(".");
    let mut write = false;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--write" => write = true,
            "--root" => match args.next() {
                Some(path) => root = path.into(),
                None => return usage_error(),
            },
            "-h" | "--help" => {
                println!("{USAGE}");
                return ExitCode::SUCCESS;
            }
            _ => return usage_error(),
        }
    }

    if write {
        match skill_check::write(&root) {
            Ok(changed) => changed.iter().for_each(|p| println!("wrote {}", p.display())),
            Err(e) => return error(e),
        }
    }

    match skill_check::check(&root) {
        Ok(findings) if findings.is_empty() => {
            println!("skill-check: ok");
            ExitCode::SUCCESS
        }
        Ok(findings) => {
            findings.iter().for_each(|f| println!("{f}"));
            println!("skill-check: {} finding(s)", findings.len());
            ExitCode::from(1)
        }
        Err(e) => error(e),
    }
}

fn usage_error() -> ExitCode {
    eprintln!("{USAGE}");
    ExitCode::from(2)
}

fn error(e: std::io::Error) -> ExitCode {
    eprintln!("skill-check: {e}");
    ExitCode::from(2)
}
