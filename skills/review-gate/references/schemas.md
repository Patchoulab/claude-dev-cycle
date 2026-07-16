### 5.4 StructuredOutput schemas (compatibility contract)

Findings — required keys are exactly the four fields the existing pipeline already produces/consumes (`filePath`, `category`, `vulnerableCode`, `explanation`); new fields are optional so existing consumers are unaffected:

```json
{
  "type": "object",
  "required": ["findings"],
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["filePath", "category", "vulnerableCode", "explanation"],
        "properties": {
          "filePath": { "type": "string" },
          "category": { "type": "string" },
          "vulnerableCode": { "type": "string" },
          "explanation": { "type": "string" },
          "severity": { "enum": ["critical", "high", "medium", "low", "info"] },
          "startLine": { "type": "integer" },
          "endLine": { "type": "integer" },
          "recommendation": { "type": "string" }
        },
        "additionalProperties": true
      }
    }
  }
}
```

Verdicts:

```json
{
  "type": "object",
  "required": ["verdicts"],
  "properties": {
    "verdicts": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["filePath", "category", "verdict", "evidence"],
        "properties": {
          "filePath": { "type": "string" },
          "category": { "type": "string" },
          "verdict": { "enum": ["confirm", "dismiss"] },
          "explanation": { "type": "string" },
          "evidence": {
            "type": "object",
            "required": ["file", "startLine", "endLine", "quote"],
            "properties": {
              "file": { "type": "string" },
              "startLine": { "type": "integer" },
              "endLine": { "type": "integer" },
              "quote": { "type": "string" }
            }
          }
        }
      }
    }
  }
}
```

Gate-side validation: `jq`-based structural check + `verify_evidence.py`. On schema failure (the observed `must have required property findings`): retry once with the schema re-quoted and the failure message appended; second failure → audit `schema_failed`, raw output saved to `.git/dev-cycle/review/failed/<sha>.json`.
