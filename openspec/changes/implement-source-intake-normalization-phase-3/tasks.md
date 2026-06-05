## 1. Models And Dependencies

- [x] 1.1 Add source intake models and events
- [x] 1.2 Add document extraction dependencies
- [x] 1.3 Add manifest path support to vault helpers

## 2. Source Intake Pipeline

- [x] 2.1 Implement supported file detection and hashing
- [x] 2.2 Implement Markdown and text extraction
- [x] 2.3 Implement DOCX extraction
- [x] 2.4 Implement PDF extraction with clear failure handling
- [x] 2.5 Implement canonical Markdown source rendering
- [x] 2.6 Implement original file copy into raw assets
- [x] 2.7 Implement source manifest read/write and duplicate reuse

## 3. API Integration

- [x] 3.1 Route capture tasks with selected paths through source intake
- [x] 3.2 Persist SourceIntakeResult output on task records
- [x] 3.3 Emit source intake progress and failure events
- [x] 3.4 Ensure source intake does not modify wiki files

## 4. Verification

- [x] 4.1 Add golden-style Markdown intake tests
- [x] 4.2 Add DOCX intake tests
- [x] 4.3 Add API tests for capture output and duplicate reuse
- [x] 4.4 Add unsupported-format and wiki non-modification tests
- [x] 4.5 Run OpenSpec validation, Python tests, and compile checks
