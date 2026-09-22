# Compliance Response — INC-2026-05-10-O1

**Document purpose**: Asgard's regulatory + customer-facing posture for
this incident. Drafted 2026-05-20 for archival; activate sections only if
specific regulator inquiry or customer disclosure request lands.

## Regulatory exposure assessment

### Thai PDPA (Personal Data Protection Act)
- **Personal data affected?** No PHI / PII was contained in the leaked secrets
  themselves. The secrets enabled hypothetical access to systems that hold
  PHI (Mimir databases) — but no observed exploitation, and access from
  outside Tailscale tunnel was not possible during the burn window.
- **Notification threshold?** Thai PDPA Sec. 37 (notification within 72h of
  awareness) applies to "personal data breach". This incident is a CREDENTIAL
  leak (potentially enabling a breach), not a breach itself. No personal data
  was confirmed exfiltrated. Notification not required.
- **Internal documentation**: This bundle satisfies PDPA Sec. 39 (documentation
  of incidents not requiring notification).

### HIPAA (US — applies if any US customer present or US-resident PHI processed)
- **PHI breach?** No PHI confirmed accessed. Credentials enabled access to
  systems holding PHI, but the threat surface (Tailscale-only ingress) and
  lack of observed exploitation keep this below the "breach" threshold per
  45 CFR §164.402.
- **Notification threshold?** Not triggered. Risk Assessment (per
  §164.402(2)) concludes "low probability that PHI has been compromised":
  - Type of PHI: None directly exposed; access required additional steps
    (network ingress) that weren't available externally
  - Unauthorized party: Public repo was visible to anyone, but no targeted
    party has been identified as having used the credentials
  - PHI acquisition: No evidence of acquisition
  - Risk mitigation: Credentials rotated within 24h-9d depending on step
- **6-year retention**: this document satisfies that requirement should
  any audit reach back to 2026-05.

### ISO 27001 / ISO 29110 (Asgard's working compliance frame)
- Aligns with `docs/iso_29110/` working materials.
- Incident handled per defined process (detection → assessment → response →
  recovery → postmortem).
- Lessons captured (`postmortem.md` §"Lessons learned").
- Compensating control (gitleaks pre-commit) was already in place before
  the incident; controlled scope of regression.

## Customer / partner disclosure stance

### Default: no proactive disclosure
- Cluster ingress was Tailscale-only during the burn window.
- No observed exploitation, no third-party security advisory.
- Burned credentials were all rotated within the recovery period.
- Proactive notification to all customers would create disproportionate
  alarm relative to actual exposure (no PHI breach).

### If asked: prepared statement (Thai)

> เมื่อ 2026-05-10 ตอน Asgard เปิดเป็น open-core สาธารณะ มี secrets ที่
> ค้างใน git history บางส่วนต้องหมุนใหม่ — เป็น preventive rotation
> ไม่มีรายงาน exploit หรือการเข้าถึงข้อมูลผู้ใช้จากภายนอก. การหมุน
> เสร็จเรียบร้อยภายใน 1-9 วันแยกตามขั้นตอน. ตอนนี้มี gitleaks pre-commit
> hook ป้องกันการ regress + เพิ่ม pre-flip checklist สำหรับครั้งหน้า

### If asked: prepared statement (English)

> On 2026-05-10 during Asgard's transition to open-core public repository,
> credentials persisted in pre-existing git history required preventive
> rotation. No exploitation was observed and no customer data was accessed
> externally — cluster ingress remained restricted to authenticated VPN
> throughout. Rotation completed within 1-9 days depending on step.
> Compensating control (gitleaks pre-commit) was already in place to
> prevent regression; the visibility-flip checklist has been updated to
> require historical-secret scanning before future flips.

## Posture by audience

| Audience | Default posture | Trigger to escalate |
|---|---|---|
| Existing customer (under MSA) | No proactive notification | If they raise the question OR if PHI audit finds anomaly |
| Prospective customer in sales conversation | Disclosed under NDA only if asked about incidents | Standard part of due diligence |
| Regulator (Thai PDPA / HIPAA OCR) | No proactive notification (below threshold) | If specific inquiry received OR if subsequent evidence shows actual breach |
| Security research community | Repo is public — anyone can read history themselves | Not applicable |
| Internal team (this team) | Full transparency via this bundle + Sprint planning + memory | Already done |

## Action items (compliance-specific)

| # | Item | Owner | Status |
|---|---|---|---|
| CR-1 | If a customer or regulator inquiry references this incident, route to engineering lead before responding | Sales, support | 📝 Standing |
| CR-2 | If any subsequent evidence of actual breach surfaces (audit log anomaly, third-party report, abuse signal), reclassify and notify per regulation | Engineering, security | 📝 Standing |
| CR-3 | If Asgard pursues SOC 2 / ISO 27001 formal cert, this incident becomes part of the audit trail; cross-reference | Future audit prep | 📝 Tracking |

## Sign-off

```
Engineering lead:  _____________________  Date: __________
Legal / compliance review (if applicable):  _____________________  Date: __________
```
