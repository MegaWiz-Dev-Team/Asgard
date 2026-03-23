---
name: medical-research
description: Use this skill for medical literature research, clinical evidence synthesis, and drug interaction analysis. Trigger on queries involving medical topics, clinical guidelines, treatment protocols, or healthcare evidence review.
version: "1.0"
author: asgard-team
tags: [medical, research, evidence, clinical, guidelines]
tools: [mimir_search, eir_patient_lookup]
---

# Medical Research

## Overview
Systematic medical literature research and clinical evidence synthesis skill. Designed for healthcare AI agents that need to search, evaluate, and summarize medical evidence from knowledge bases and patient records.

## When to Use
- Clinical question answering (diagnosis, treatment, drug interactions)
- Evidence synthesis from medical literature
- Treatment protocol comparison
- Drug interaction and contraindication checks
- Clinical guideline summarization

## Instructions
1. **Identify the clinical question** — structure as PICO (Population, Intervention, Comparison, Outcome)
2. **Search knowledge bases** — use `mimir_search` to query medical RAG knowledge bases
3. **Cross-reference patient context** — if available, use `eir_patient_lookup` for patient-specific data
4. **Evaluate evidence quality** — note study type, sample size, and level of evidence
5. **Synthesize findings** — create structured summary with:
   - Key findings
   - Evidence strength (high/moderate/low)
   - Clinical relevance
   - Limitations and caveats

## Quality Bar
- All claims must cite source documents
- Drug dosages must include standard ranges and contraindications
- Distinguish between established guidelines and emerging research
- Flag any information gaps explicitly

## Common Mistakes to Avoid
- Do NOT provide definitive medical advice — always frame as "evidence suggests"
- Do NOT ignore patient-specific context (allergies, comorbidities)
- Do NOT mix up drug names (especially sound-alike medications)
