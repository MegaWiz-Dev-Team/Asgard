# Skuggi Extraction Migration Plan (engine public / rules private)

**Status:** Steps 1–2 DONE (2026-05-31) · Steps 3–5 gated on Skuggi W2–W4/NER
**Date:** 2026-05-30 (plan) · 2026-05-31 (steps 1–2 executed)
**Owner:** paripol@megawiz.co
**Drives:** the deferred action in [OPEN_CORE_POLICY.md](../../OPEN_CORE_POLICY.md) Tier-C / Skuggi gap
**Related:** [ADR-023](../decisions/ADR-023-open-core-ip-boundary.md), ADR-007 (Skuggi)

## Goal

Make Skuggi's **tuned PII-detection IP** private without breaking the public builds of Mimir and
Heimdall (both AGPL Tier-B), and without a private *code* dependency that would make those repos
un-buildable from public source.

## Why the obvious approach fails

`skuggi-core` lives at `Mimir/ro-ai-bridge/skuggi-core` (public) and is consumed by **path
dependency** from:

| Consumer | Repo | API used |
|----------|------|----------|
| `gateway/src/skuggi.rs` (re-export) | Heimdall (public) | `redact_chat_body`, `redact_text`, `scan_categories`, `Detection`, `RedactionResult` |
| `routes/admin_skuggi.rs` | Mimir (public) | `scan_categories` |
| `routes/a2a.rs` | Mimir (public) | `redact_text` |
| `bin/skuggi_leak_runner.rs`, `bin/skuggi_bench.rs` | Mimir (public) | `scan_categories` |

Moving `skuggi-core` into a private repo and depending on it privately → **both public repos stop
compiling without private access.** That breaks the Tier-B "community-buildable / auditable"
promise. So we must split, not relocate.

## The split: engine (public) vs rules (private)

Looking at `skuggi-core/src/lib.rs`, the file already separates cleanly:

- **Engine = generic plumbing, NO IP value → stays public in `skuggi-core`:**
  `ReplaceMode`, `Detection`, `RedactionResult`, `redact_text`, `scan_categories`,
  `redact_chat_body`. These are format-agnostic — they apply *whatever* ruleset they are given.
- **Rules = the tuned IP → becomes private:** the regex `static`s + the ordered `patterns()`
  dispatch table (categories, placeholders, replace modes, ordering rationale). Today this is 8
  standard patterns (Thai ID/phone/email + 5 form anchors). Low IP value *now*; high once W2–W4
  / NER detectors and tuned weights land — which is exactly what we're protecting for.

### Recommended mechanism: private **rules data file**, not a private crate

Refactor `patterns()` from compile-time `&'static Regex` statics into a runtime-loaded `RuleSet`:

```rust
// skuggi-core (PUBLIC) — engine + a generic, non-proprietary default ruleset
pub struct Rule { pub category: String, pub placeholder: String,
                  pub regex: Regex, pub mode: ReplaceMode }
pub struct RuleSet { rules: Vec<Rule> }

impl RuleSet {
    /// Generic baseline so public builds detect & run out of the box.
    pub fn builtin() -> Self { /* the current standard 8 patterns */ }

    /// Commercial/on-prem: load tuned rules from a data file if present,
    /// else fall back to builtin(). NO private code dependency.
    pub fn load() -> Self {
        match std::env::var("SKUGGI_RULES_PATH") {
            Ok(p) => Self::from_toml_path(&p).unwrap_or_else(|_| Self::builtin()),
            Err(_) => Self::builtin(),
        }
    }
    pub fn from_toml_path(path: &str) -> anyhow::Result<Self> { /* parse TOML → compile regex */ }
}

// Engine functions take &RuleSet (or read a process-global set once).
pub fn redact_text(rules: &RuleSet, text: &str) -> RedactionResult { /* unchanged logic */ }
```

The **tuned ruleset ships only as a data file** (`skuggi-rules.toml` + future model artifacts) on
commercial/on-prem images, distributed from the private **`MegaWiz-Dev-Team/Skuggi`** repo. Public
source contains only `builtin()` (generic patterns). Result:

- Public Mimir + Heimdall **build and run** from public source (using `builtin()`). ✅
- No private *code* dependency in any public repo. ✅
- The tuned detectors/weights/models live exclusively in the private Skuggi repo as data. ✅
- On-prem boxes set `SKUGGI_RULES_PATH=/etc/asgard/skuggi-rules.toml` (dropped in at deploy). ✅

> Rejected alternative: a feature-gated private `skuggi-rules` **crate**. Works, but commercial CI
> then needs private-repo build access and the public/commercial build graphs diverge. The data-file
> approach keeps even commercial builds buildable from public source + a dropped-in file. Pick the
> crate only if rules need compiled Rust logic (not just patterns) — revisit when NER lands.

## Step-by-step (each step keeps all repos green)

1. ✅ **DONE 2026-05-31 — Refactor in place (public, no behavior change).** In `skuggi-core`,
   introduced `Rule`/`RuleSet`, moved the 8 patterns into `RuleSet::builtin()`, and made
   `redact_text`/`scan_categories`/`redact_chat_body` methods on `&RuleSet`. Added `RuleSet::load()`
   (env `SKUGGI_RULES_PATH` → `from_toml_path`/`from_toml_str`, else `builtin()`). Kept the existing
   **free functions** with identical signatures as thin wrappers over a `once_cell` process-global
   `Lazy<RuleSet>` = `load()`, so all Heimdall + Mimir callsites compile unchanged. Crucially,
   `Detection.category` / `scan_categories` stay **`&'static str`** (Mimir's
   `pii_matches_in_response: Vec<&'static str>` depends on it) — loaded rules `Box::leak` their
   category/placeholder once at startup. **Bumped skuggi-core 0.1.0 → 0.2.0** (+ `toml` dep; updated
   Mimir workspace requirement to `0.2`). Added `toml` dep. **Verified:** skuggi-core 17/17 tests;
   Heimdall gateway skuggi 27/27 (incl. all leak-contract tests) — behaviour identical to v0.1;
   `ro-ai-bridge` + Heimdall gateway both compile (`SQLX_OFFLINE=true`).
2. ✅ **DONE 2026-05-31 — Wire `load()` at startup.** Heimdall `main.rs` now calls
   `skuggi_core::init_default_rules()` eagerly at boot (just before the tenant-config cache),
   logging the active detector count and whether a custom `SKUGGI_RULES_PATH` is in use — so a bad
   path surfaces at startup, not on the first proxied request. Mimir relies on lazy global init at
   first use (per-request path; no hot-path startup wiring needed). Leak-contract tests confirm
   `builtin()` reproduces today's redaction exactly.
3. **Create private repo `MegaWiz-Dev-Team/Skuggi`.** Contents: `skuggi-rules.toml` (the tuned
   ruleset, initially = builtin exported to TOML, then extended privately), the tuning/eval harness
   (move `skuggi_bench.rs` / `skuggi_leak_runner.rs` here if they embed proprietary corpora — keep
   public smoke versions), and future W2–W4 / NER model artifacts. License: `LicenseRef-Commercial`.
4. **Deploy wiring.** Add `SKUGGI_RULES_PATH` to the on-prem/commercial image build + customer
   deployment runbook; drop `skuggi-rules.toml` from the private repo into the image. Public/dev
   builds leave it unset → `builtin()`.
5. **Verify gap closed.** `grep` confirms no tuned patterns remain in public repos beyond the
   generic `builtin()`. Update [OPEN_CORE_POLICY.md](../../OPEN_CORE_POLICY.md) gap log: Skuggi → done.

## Trigger / timing

Per ADR-023, execute steps 3–5 **when the proprietary detectors (Skuggi W2–W4 / NER) actually
exist** — that's when there is real IP to protect. Steps 1–2 (the refactor enabling runtime rules)
are safe to land anytime and are a prerequisite, so they can go first independently.

## Reversibility note

Steps 1–2 are ordinary refactors (fully reversible). Step 3 creates a *new private* repo (does not
touch public repo visibility — nothing flips public→private, so no broken links/forks/crates). This
plan deliberately avoids the irreversible moves (un-publishing crates, privatizing public repos)
that the rejected "close Bifrost/refgraph" proposal would have required.
