---
name: ocr-document-processing
description: OCR and document processing patterns for Syn service (Thai ID, Medical docs, eKYC)
---

# OCR & Document Processing — Syn Service

## Overview
Patterns for building the Syn (👁️) OCR + eKYC service for the Asgard platform. Covers Thai document OCR, medical document parsing, and identity verification.

## Technology Stack
| Component | Library/API | Purpose |
|:--|:--|:--|
| Thai OCR | PaddleOCR | Primary OCR engine (supports Thai) |
| Fallback OCR | Google Cloud Vision | Higher accuracy, paid API |
| Thai ID Parser | Custom + regex | Extract structured fields from ID card |
| Medical OCR | PaddleOCR + ICD-10 lookup | Extract diagnosis codes |
| eKYC | iApp / NDID API | Face matching + liveness |
| Document Classifier | Fine-tuned model or LLM | Classify document type |

## Thai ID Card OCR Output Schema
```python
class ThaiIDResult(BaseModel):
    id_number: str          # เลขบัตรประชาชน 13 หลัก
    prefix: str             # คำนำหน้า (นาย/นาง/นางสาว)
    first_name: str         # ชื่อ
    last_name: str          # นามสกุล
    first_name_en: str      # Name (English)
    last_name_en: str       # Last Name (English)
    date_of_birth: str      # วันเกิด (YYYY-MM-DD)
    address: str            # ที่อยู่
    issue_date: str         # วันออกบัตร
    expiry_date: str        # วันหมดอายุ
    confidence: float       # OCR confidence score
    raw_text: str           # Raw OCR output
```

## PaddleOCR Setup
```python
from paddleocr import PaddleOCR

ocr = PaddleOCR(
    use_angle_cls=True,
    lang='th',  # Thai language model
    show_log=False,
    use_gpu=False  # CPU mode for initial deployment
)

def extract_text(image_path: str) -> list[str]:
    result = ocr.ocr(image_path, cls=True)
    texts = []
    for line in result[0]:
        text = line[1][0]
        confidence = line[1][1]
        if confidence > 0.5:
            texts.append(text)
    return texts
```

## Medical Document Processing
```python
import re

ICD10_PATTERN = re.compile(r'[A-Z]\d{2}(?:\.\d{1,4})?')

def extract_icd_codes(text: str) -> list[str]:
    """Extract ICD-10 codes from medical document text."""
    return ICD10_PATTERN.findall(text)

def classify_document(text: str) -> str:
    """Classify medical document type."""
    keywords = {
        "ใบรับรองแพทย์": "medical_certificate",
        "medical certificate": "medical_certificate",
        "ใบเคลม": "claim_form",
        "claim": "claim_form",
        "ผลตรวจ": "lab_result",
        "ใบสั่งยา": "prescription",
    }
    text_lower = text.lower()
    for keyword, doc_type in keywords.items():
        if keyword in text_lower:
            return doc_type
    return "unknown"
```

## API Endpoints (Syn :8600)
```
POST /v1/ocr/thai-id          → ThaiIDResult
POST /v1/ocr/medical-doc      → MedicalDocResult
POST /v1/ocr/bank-book        → BankBookResult
POST /v1/ocr/general          → GeneralOCRResult
POST /v1/classify/document    → DocumentClassification
POST /v1/ekyc/face-match      → FaceMatchResult
GET  /health                   → HealthStatus
```

## Docker Considerations
- PaddleOCR requires ~300MB disk for models
- Use `paddlepaddle` CPU version (no CUDA needed for initial)
- Cache models in Docker layer to speed up builds:
```dockerfile
FROM python:3.12-slim
RUN pip install paddlepaddle paddleocr
# Pre-download Thai model
RUN python -c "from paddleocr import PaddleOCR; PaddleOCR(lang='th')"
```

## Testing
- Use sample Thai ID images (anonymized/synthetic)
- Test ICD-10 extraction with known medical texts
- Mock eKYC API calls in unit tests
- Confidence threshold tests (accept ≥0.7, reject <0.5)
