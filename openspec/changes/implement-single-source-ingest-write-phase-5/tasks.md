## 1. OpenSpec Artifacts

- [x] 1.1 Add phase 5 proposal, design, tasks, and delta spec

## 2. Ingest Models

- [x] 2.1 Add `SourceMeta`, extracted entity/concept/claim/conflict models
- [x] 2.2 Add `IngestResult` structured output model

## 3. Ingest Workflow Hint

- [x] 3.1 Detect explicit `/wiki:ingest`, `/wiki:compile`, or `raw/sources/*.md` source path
- [x] 3.2 Validate that ingest targets exactly one canonical source under `raw/sources/`
- [x] 3.3 Emit ingest-specific task events and failure messages

## 4. SDK-backed Ingest Runner

- [x] 4.1 Build ingest-specific instructions/prompt from baseline context and source path
- [x] 4.2 Run ingest through OpenAI Agents SDK and phase 4 function tools
- [x] 4.3 Normalize SDK final output into `IngestResult`
- [x] 4.4 Include changed pages and journal entry in task output

## 5. Verification

- [x] 5.1 Add golden ingest test with mocked SDK runner that writes source/index/log/concept pages
- [x] 5.2 Add invalid source path and unconfigured runtime tests
- [x] 5.3 Run OpenSpec validation, Python tests, compile checks, and diff checks
