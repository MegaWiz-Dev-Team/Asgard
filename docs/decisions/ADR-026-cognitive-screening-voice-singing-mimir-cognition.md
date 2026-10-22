# ADR-026: Nemelo — Cognitive Screening from Singing and Speech — `mimir-cognition` engine + `eir-cognition` agent

**Product name:** **Nemelo** (เนเมโล) — coined from Greek *mnēmē* (memory) + *melos* (melody), spelled as it is said; chosen by Paripol 22 Oct 2026 (replacing an earlier pick, Lamun, which two unrelated projects started using in Aug–Sep 2026), pending a formal trademark search (DIP + WIPO, classes 9/10/42/44; check against Nemlia, an elder-care monitoring start-up). Mascot: น้องเมโล่ (Melo). Product label only; the screen shown to older adults says "ร้องเพลงด้วยกัน", not the brand. Avoid "Nemo"/clownfish imagery (Disney's *Finding Nemo*, whose Dory is a memory-loss gag).

**Status:** Accepted — structure approved by Paripol, 22 Oct 2026
**Date:** 2026-10-22
**Deciders:** paripol@megawiz.co
**Scope:** New capability: a short karaoke-style session for older adults that screens for early cognitive decline and refers to a clinician. Also offered as a music activity (mood, engagement).
**Related:** ADR-009 (single-tenant Mac mini), ADR-014 (FHIR data plane = Mimir), ADR-018 (CDS as Eir agent family), ADR-024 (asgard_analytics engine), ADR-025 (Nótt — the product-repo pattern this ADR copies), [feedback: no new Norse components], [Rust-first], [Tyr/Skuggi in every PII design], [license gate at admission]

## Context

- The new disease-modifying Alzheimer's drugs (lecanemab, donanemab) are only for MCI / mild dementia with confirmed amyloid. Finding people early is where the value is.
- Speech analysis separates MCI from cognitively unimpaired people with pooled sensitivity 80%, specificity 77%, AUC 0.78 (54 studies; *Age and Ageing* 2025). The same review warns that models trained on English lose sensitivity in other languages. Thai work exists but is small (TLCA task set; Thai verbal fluency AUC 0.733; ASR for the MoCA fluency item). Thai data we collect is the moat.
- **Familiar songs cannot be the test.** Musical memory is relatively spared in Alzheimer's (*Brain* 2015): someone can sing an old song perfectly while memory is failing. Karaoke is the wrapper that makes people want to come back; the measurement is learning *new* material and speech tasks.
- **Music as therapy:** music-based interventions probably reduce depression and behavioural problems, may improve quality of life, do not reduce agitation, and have little or no effect on cognition (Cochrane 2018). A 26-person karaoke RCT improved frontal executive scores (FAB). A 52,601-person Japanese cohort found karaoke associated with lower dementia risk in women (HR 0.77), which is association, not prevention.
- **POC (21–22 Oct 2026, `~/Developer/acestep-thai-poc`):** ACE-Step 1.5 generated 5 Thai choruses + 1 English control, two seeds each, ~14 s per 40 s clip on the Mac mini. Scored against Sága transcripts: share of lyric words misheard or missing = Thai 28% (23% without one clip where Whisper failed) vs English 26%. Residual errors are mostly tonal (ไก่→ไกล, บาน→บ้าน). Paripol listened and chose ACE-Step over Suno.

## Decision

> **No new top-level component. A product repo (`asgard-nemelo`, like `asgard-nott`) holds a Rust engine `mimir-cognition` that turns session recordings into versioned, deterministic features. `eir-cognition` drafts a referral note for a clinician later. Songs and prompts are made offline; the session client only plays and records; analysis runs afterwards as a batch on the customer's Mac mini.**

1. **Components and homes.**
   - `mimir-cognition` (Rust, Mimir-family data engine by role, housed in the product repo — same arrangement as `mimir-sleep` in `asgard-nott`).
   - `eir-cognition` (Eir CDS family per ADR-018): human-in-the-loop, drafts only, a clinician decides. Built in Phase 3, not before.
   - Reused, not forked: **Sága** (STT), **Bragi** (pre-rendered host prompts), **Heimdall** (one generative model, gemma-4-26b, only for answers that need interpretation), **bifrost-jobs** (batch), **MinIO** (raw audio), **mimir-fhir / mimir-lab** (sinks), **Tyr** (audit).

2. **Task- and language-agnostic model.** Canonical shape: `Session → Task → Recording → Features`. Karaoke is one task family, not the engine. Initial task types: `song_learn`, `song_recall_immediate`, `song_recall_delayed`, `naming`, `autobiographical`, `reading`, `fluency`, `picture_description`. Language is a field on every task and stimulus. Thai first; Japanese / Chinese later add stimuli and validation data, not code.

3. **Session flow (draft, ~10 min):** hearing check → familiar warm-up song (not scored) → teach a new chorus → speech tasks → recall the chorus → familiar closing song. A failed hearing check stops scoring: low recall from not hearing is not a memory finding.

4. **Pipeline.**
   - *Session client (tablet):* plays stimuli, records, uploads to the Mac mini. No LLM or STT at session time.
   - *Batch (bifrost-jobs):* Sága → `mimir-cognition` features → sinks. One model resident at a time; heavy steps run under the Mac mini's memory guard.
   - *Sinks:* clinical → FHIR R5 Observations (interim Bundle JSON → MinIO until mimir-fhir persists resources, as in ADR-025); analytics → `mimir-lab`, consent-gated, de-identified.

5. **Stimulus library.**
   - Songs are generated **offline with ACE-Step 1.5** (MIT code + weights) on our hardware. **Not Suno.** The generator is a Python tool outside the request path (Rust-first exception for offline data tooling). If a service ever needs on-demand songs, Rust calls ACE-Step's REST API, the way Heimdall fronts MLX.
   - Each song record carries: language, lyrics, syllable count, BPM, repeat count, generator + model + seed, listener-check result, similarity-check result. All songs in one form set must match on syllables, tempo, and repeats so monthly retests are comparable.
   - A song enters the library only after (a) naive listeners who have not seen the lyrics transcribe them correctly, and (b) a check that the melody does not resemble a well-known song (ACE-Step does not disclose its training data).
   - The library is shared reference data: it ships with a row in `GET /api/v1/knowledge/shared` and is visible in the UI.

6. **Scoring rules (`mimir-cognition`).**
   - Deterministic and versioned; the LLM never decides a score that rules can compute.
   - **Compare by sound, not spelling.** Thai homophones (ไหว้/ไว้, บาตร/บาท) are not errors.
   - **Segment audio before STT.** Whole-clip Whisper loops on instrumental parts ("ช้า ช้า ช้า…"); one POC clip scored 0.30 recall though the vocals were fine. Sága needs segmentation and word timestamps (for pause features); the running interim server returns neither today.
   - Thai word segmentation: nlpO3 newmm with `safe=false`, and assert the tokens concatenate back to the input (safe mode corrupted long input in the POC).
   - Report miss rate (substitutions + deletions over lyric words) next to WER; insertions are dominated by STT artefacts and repeated lines.
   - The POC scorer `lyric-recall` (Rust: Thai-safe normalisation, LCS recall, CER, WER, loop collapse; 11 tests) is the seed for this crate.

7. **Governance.**
   - Tenant `asgard_medical`; one Mac mini per customer (ADR-009); audio never leaves the box.
   - Voice used to assess health is sensitive personal data: an explicit FHIR R5 `Consent` gates recording, and a separate consent gates analytics use.
   - Tyr audits every ingest / read / export. Skuggi applies to any future cloud hop (none planned).
   - Third-party model artifacts go through the license gate (`ai_models.metadata.commercial_use`); research-only music models (YuE2, LeVo 2) are benchmark-only.
   - Standard instruments (MMSE, MoCA) are copyrighted; clear licences before their items appear in any task.

8. **What we may claim.**
   - The screen **refers**; it does not diagnose. At ~77% specificity about 1 in 4 healthy people would be referred, so the referral path must not land on neurologists unfiltered.
   - The music activity supports mood and engagement. **No claim** that it improves memory or prevents dementia.
   - Any screening claim to customers requires Thai FDA (อย.) review first.

## Phases and gates

| Phase | Work | Gate to continue |
|---|---|---|
| 0 ✅ | POC: song generation + scorer | Done 22 Oct 2026 |
| 1 | Stimulus library + session prototype + listener check; `mimir-cognition` data model; Sága segmentation + word timestamps. No patient data. | Songs pass the listener check; older adults finish a session |
| 2 | Pilot with a partner clinic under ethics approval: diagnosed MCI/AD vs cognitively normal, MoCA or TMSE on the same day; real features in `mimir-cognition` | Features separate the groups against the standard test |
| 3 | `eir-cognition` referral draft + clinician console | Thai FDA path settled before any screening claim |

## Consequences

- **+** No new component, repo pattern already proven by Nótt; the same engine serves plain speech screening and karaoke.
- **+** Songs cost nothing per item, stay on our hardware, and can be regenerated as alternate forms.
- **−** Clinical validity is unproven until Phase 2; the team has no clinician, so a partner clinic is a hard dependency.
- **−** ACE-Step on MPS currently holds ~21.7 GB of duplicate PyTorch weights next to ~10 GB of MLX; trim before it runs on a customer Mac mini.
- **Open:** trademark search for "Nemelo" (nemelo.com is taken; nemelo.co, .ai, .health, .app and .co.th were free on 22 Oct 2026); partner clinic; MMSE/MoCA licensing; ACE-Step training-data provenance.

## References

- Speech-based biomarkers in MCI, systematic review and meta-analysis — *Age and Ageing* 54(10) afaf316, 2025.
- Jacobsen et al., "Why musical memory can be preserved in advanced Alzheimer's disease" — *Brain* 138(8):2122, 2015.
- van der Steen et al., "Music-based therapeutic interventions for people with dementia" — Cochrane CD003477, 2018.
- Karaoke training and frontal executive function, pilot RCT (n=26) — *IJERPH* 17(4):1459, 2020.
- Musical activities and dementia risk, JAGES (n=52,601) — *Geriatr Gerontol Int*, 2021.
- ACE-Step 1.5 — github.com/ace-step/ACE-Step-1.5 (MIT); arXiv 2602.00744.
