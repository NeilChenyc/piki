# Piki Product Notes

Working product notes for turning the LLM Wiki kernel into a usable personal knowledge-base product.

## Command And Intent Layer

- MVP decision: use Codex CLI as the first agent runtime layer, and let the Piki client act as the visual shell around it.
- The client should not aim to mimic a raw terminal. It should render CLI activity as structured product events: messages, resolved operations, file reads/writes, diffs, queue transitions, and review prompts.
- This means the MVP UI can be quite practical: a conversation pane, an operation/status pane, a file/reference pane, and a diff/review pane are enough to make CLI-driven agent work feel native.
- Documentation quality becomes even more important in this setup. If `AGENTS.md`, vault structure, source docs, official episode overviews, and product docs are clear, Codex CLI can act as a capable agent layer without Piki first building a full custom planner/runtime.
- Piki should support two equivalent interaction modes: natural-language intent and explicit slash commands.
- Natural language is the friendly top layer. The user should be able to say things like "把这篇文章收进知识库", "帮我查一下纤维摄入对情绪的影响", or "做一次知识库健康检查".
- Slash commands are the stable power-user layer. The same operations should also be invokable as `/wiki:ingest`, `/wiki:query`, `/wiki:lint`, `/wiki:research`, and related commands.
- Both modes should compile down to the same internal operation model. Natural language should not trigger an ad-hoc workflow that differs from slash commands.
- The product should show the resolved operation before running when ambiguity or write risk exists. Example: "I interpreted this as `/wiki:ingest raw/inbox/article.md` and will update source, concept, domain, index, and log pages."
- The initial command set can mirror the LLM Wiki maintenance loop:
  - `/wiki:ingest <source>`: capture or normalize a source into the vault.
  - `/wiki:compile <source-or-inbox>`: update wiki pages from raw sources.
  - `/wiki:query "<question>"`: answer from the compiled wiki with citations.
  - `/wiki:file-back`: save valuable conversation output back into the wiki by recording the conversation as a source, then updating the right source, concept, entity, domain, or synthesis pages.
  - `/wiki:lint`: inspect structure, links, stale claims, duplicate concepts, and missing pages.
  - `/wiki:research "<topic>"`: gather sources and optionally create or expand a topic area.
- Natural-language routing should identify operation type, target source/topic/question, write scope, risk level, and whether review is required.
- The Mac client should expose commands visually as actions, not just text. Examples: "Ingest", "Ask", "File Back", "Lint", "Research".
- The CLI/API/client should all call the same operation layer so Piki does not split into three subtly different products.

## References From nashsu/llm_wiki

- Piki's north star should stay narrower than nashsu/llm_wiki: help an individual remember and recall, not become a maximal research suite on day one.
- Add `purpose.md` or equivalent. `AGENTS.md`/schema explains how the wiki is maintained; `purpose.md` should explain why this personal memory vault exists, what the user wants to remember, and what kinds of recall matter.
- Split ingest into two explicit stages:
  - Analyze: extract entities, concepts, claims, contradictions, source quality, and candidate links.
  - Generate: create or update source, concept, entity, domain, synthesis, index, and log pages.
- Keep source traceability strict. Every generated wiki page should include `sources: []` and every answer should cite the wiki pages used.
- Add an ingest queue before heavy automation. The queue should support pending, processing, failed, retry, cancel, and completed states so memory ingestion feels reliable.
- Add source hashing. If a source has not changed, skip re-ingest and avoid wasting tokens.
- Add source change detection. On app open or manual rescan, compare source files against a manifest; changed sources should enter an update queue and go through Analyze -> Review -> Generate instead of silently rewriting the wiki.
- Add a review queue. The LLM should flag uncertain items for human judgment without blocking the whole ingest pipeline.
- Treat "Save to Wiki" as a core recall feature. Conversation snippets should first be treated as sources; durable conclusions, comparisons, decisions, and insights should then be compiled into the appropriate wiki pages, including synthesis only when the content is truly cross-source or analytical.
- Build recall around multiple cues, not only chat search:
  - keyword search
  - source overlap
  - wikilinks
  - graph neighbors
  - optional vector search later
- Use a knowledge graph as a recall surface, but keep MVP simple. First show backlinks, related pages, and isolated pages; community detection and surprise scoring can come later.
- Add knowledge gaps as product objects. Pages with few links, sparse areas, and bridge concepts should become prompts for review or research.
- Make vector search optional. The default should work with Markdown, token search, and graph expansion; embeddings can be enabled later.
- Support Chinese retrieval intentionally. Token search should handle CJK text with bigrams or another Chinese-friendly strategy.
- Add local HTTP API early enough that external agents can query the vault. Start read-only: health, projects, files, search, graph, and rescan.
- Keep write endpoints more conservative than read endpoints. Mutations should go through reviewed operations like ingest, compile, file-back, and lint-fix.
- A browser clipper is highly valuable for personal memory, but it can be phase two. First support folder/file import; then add web capture.
- Multi-format ingestion matters, but Markdown/text/PDF should come first. DOCX, PPTX, XLSX, image captions, audio, and video can be staged later.
- The app should persist conversations, cited references, settings, review items, and ingest activity so recall context survives restarts.
- UI layout worth borrowing: left knowledge/source tree, center chat/command surface, right preview/reference panel.
- Avoid over-borrowing early complexity: Louvain clustering, surprising-connection scoring, deep research providers, and multimodal image ingestion are useful later, not kernel requirements.
