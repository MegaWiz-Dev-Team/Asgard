---
name: patient-summary
description: Use this skill to generate comprehensive patient summaries from EMR data. Trigger when asked to summarize a patient's medical history, create handoff reports, or prepare clinical documentation from structured health records.
version: "1.0"
author: asgard-team
tags: [medical, patient, summary, EMR, clinical]
tools: [eir_patient_lookup, eir_get_encounters, mimir_search]
---

# Patient Summary

## Overview
Generate structured patient summaries from Electronic Medical Record (EMR) data via Eir. Produces concise, clinically relevant overviews suitable for handoffs, consultations, and care coordination.

## When to Use
- Patient handoff between providers
- Clinical consultation preparation
- Care coordination summaries
- Pre-visit documentation review
- Discharge summary generation

## Instructions
1. **Retrieve patient data** — use `eir_patient_lookup` to get demographics and active problems
2. **Gather encounters** — use `eir_get_encounters` for recent visit history
3. **Identify key issues** — extract active diagnoses, current medications, recent labs
4. **Structure summary** using standard format:
   - **Demographics**: Age, sex, key identifiers
   - **Active Problems**: Current diagnoses ranked by severity
   - **Medications**: Active prescriptions with dosages
   - **Recent Encounters**: Last 3-5 visits with key findings
   - **Pending**: Outstanding orders, referrals, follow-ups
   - **Alerts**: Allergies, critical lab values, fall risk

## Quality Bar
- Use standardized medical terminology
- Include medication dosages and frequencies
- Flag critical or abnormal values
- Maintain patient confidentiality (no unnecessary identifiers)

## Common Mistakes to Avoid
- Do NOT omit allergy information
- Do NOT include outdated or discontinued medications without marking them
- Do NOT make clinical judgments — present data objectively
