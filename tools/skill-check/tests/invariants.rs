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

//! Every rule is proven able to fail: each fixture tree breaks exactly one
//! rule, and the check must report that rule and nothing else.

use skill_check::{check, write, Rule};
use std::fs;
use std::path::{Path, PathBuf};

fn fixture(case: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(case)
}

fn rules(root: &Path) -> Vec<Rule> {
    check(root).expect("fixture is readable").into_iter().map(|f| f.rule).collect()
}

#[test]
fn valid_tree_has_no_findings() {
    let findings = check(&fixture("valid")).unwrap();
    assert!(findings.is_empty(), "{findings:#?}");
}

#[test]
fn each_fixture_breaks_exactly_its_rule() {
    let cases = [
        ("missing-frontmatter", Rule::Frontmatter),
        ("unknown-key", Rule::Frontmatter),
        ("bad-status", Rule::Frontmatter),
        ("name-mismatch", Rule::Name),
        ("name-not-kebab", Rule::Name),
        ("empty-description", Rule::Description),
        ("long-description", Rule::Description),
        ("misplaced", Rule::Location),
        ("duplicate", Rule::Duplicate),
        ("stale-index", Rule::Block),
        ("stale-targets", Rule::Block),
        ("unknown-block", Rule::Block),
        ("unterminated-block", Rule::Block),
    ];
    for (case, rule) in cases {
        assert_eq!(rules(&fixture(case)), vec![rule], "fixture `{case}`");
    }
}

#[test]
fn missing_skills_dir_is_an_error_not_a_pass() {
    assert!(check(&fixture("does-not-exist")).is_err());
}

#[test]
fn write_repairs_stale_blocks_and_then_changes_nothing() {
    for case in ["stale-index", "stale-targets"] {
        let tmp = std::env::temp_dir().join(format!("skill-check-{}-{case}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        copy_tree(&fixture(case), &tmp);

        assert_eq!(write(&tmp).unwrap().len(), 1, "fixture `{case}` rewrites one file");
        assert!(rules(&tmp).is_empty(), "fixture `{case}` is clean after --write");
        assert!(write(&tmp).unwrap().is_empty(), "fixture `{case}` second --write is a no-op");

        fs::remove_dir_all(&tmp).unwrap();
    }
}

#[test]
fn write_leaves_unknown_blocks_for_a_human() {
    let tmp = std::env::temp_dir().join(format!("skill-check-{}-unknown", std::process::id()));
    let _ = fs::remove_dir_all(&tmp);
    copy_tree(&fixture("unknown-block"), &tmp);

    assert!(write(&tmp).unwrap().is_empty());
    assert_eq!(rules(&tmp), vec![Rule::Block]);

    fs::remove_dir_all(&tmp).unwrap();
}

fn copy_tree(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.file_type().unwrap().is_dir() {
            copy_tree(&entry.path(), &target);
        } else {
            fs::copy(entry.path(), target).unwrap();
        }
    }
}
