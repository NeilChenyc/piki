# Piki Product Notes

Working product notes for turning the LLM Wiki kernel into a usable personal knowledge-base product.

## Command And Intent Layer

- MVP decision: use OpenAI Agents SDK as the first agent runtime layer, implemented as a local Piki Agent Service.
- The client should not depend on raw SDK events. It should render Piki-owned structured product events: messages, task phases, file reads/writes, diffs, change records, rollback state, and queue transitions.
- This means the MVP UI can be practical: a conversation pane, a task/status pane, a file/reference pane, and a change/rollback pane are enough to make SDK-driven agent work feel native.
- Documentation quality becomes even more important in this setup. If `AGENTS.md`, vault structure, source docs, official episode overviews, and product docs are clear, the SDK-backed local agent can maintain Piki without us first writing a full custom agent loop.
- Piki should support two equivalent interaction modes: natural-language intent and explicit slash commands.
- Natural language is the friendly top layer. The user should be able to say things like "把这篇文章收进知识库", "帮我查一下纤维摄入对情绪的影响", or "做一次知识库健康检查".
- Slash commands are the stable power-user layer. They are hints to the same SDK-backed agent, not a separate routing system.
- Both modes should compile down to the same task API, shared context loading, and shared tool registry. Natural language should not trigger an ad-hoc workflow that differs from slash commands.
- The product should show what changed after conversations that modify `raw/` or `wiki/`, and keep a rollback affordance. Example: "This conversation updated source, concept, domain, index, and log pages; this journal entry can be rolled back while hashes still match."
- The initial command set can mirror the LLM Wiki maintenance loop:
  - `/wiki:ingest <source>`: capture or normalize a source into the vault.
  - `/wiki:compile <source-or-inbox>`: update wiki pages from raw sources.
  - `/wiki:query "<question>"`: answer from the compiled wiki with citations.
  - `/wiki:lint`: inspect structure, links, stale claims, duplicate concepts, and missing pages.
  - `/wiki:research "<topic>"`: gather sources and optionally create or expand a topic area.
- The agent should infer target source/topic/question from the conversation and `AGENTS.md`; read/write boundaries should be enforced by tools.
- The Mac client should expose commands visually as actions, not just text. Examples: "Ingest", "Ask", "Lint", "Research".
- The CLI/API/client should all call the same task API and tool layer so Piki does not split into three subtly different products.

## References From nashsu/llm_wiki

- Piki's north star should stay narrower than nashsu/llm_wiki: help an individual remember and recall, not become a maximal research suite on day one.
- Add `purpose.md` or equivalent. `AGENTS.md`/schema explains how the wiki is maintained; `purpose.md` should explain why this personal memory vault exists, what the user wants to remember, and what kinds of recall matter.
- Split ingest into two explicit stages:
  - Analyze: extract entities, concepts, claims, contradictions, source quality, and candidate links.
  - Generate: create or update source, concept, entity, domain, synthesis, index, and log pages.
- Keep source traceability strict. Every generated wiki page should include `sources: []` and every answer should cite the wiki pages used.
- Add an ingest queue before heavy automation. The queue should support pending, processing, failed, retry, cancel, and completed states so memory ingestion feels reliable.
- Add source hashing. If a source has not changed, skip re-ingest and avoid wasting tokens.
- Add source change detection. On app open or manual rescan, compare source files against a manifest; changed sources should enter an update queue and go through Analyze -> Generate with change-set logging.
- Defer user review queues beyond MVP. The LLM should mark uncertainty and conflicts in the wiki content and log, not block writing on per-item confirmation.
- MVP should not include a separate conversation-saving workflow. If the user explicitly asks to write a synthesis or update a page, the agent can handle it as a normal vault write with journal tracking.
- Build recall around multiple cues, not only chat search:
  - keyword search
  - source overlap
  - wikilinks
  - graph neighbors
  - optional vector search later
- Use a knowledge graph as a recall surface, but keep MVP simple. First show backlinks, related pages, and isolated pages; community detection and surprise scoring can come later.
- Add knowledge gaps as product objects. Pages with few links, sparse areas, and bridge concepts should become prompts for maintenance or research.
- Make vector search optional. The default should work with Markdown, token search, and graph expansion; embeddings can be enabled later.
- Support Chinese retrieval intentionally. Token search should handle CJK text with bigrams or another Chinese-friendly strategy.
- Add local HTTP API early enough that external agents can query the vault. Start read-only: health, projects, files, search, graph, and rescan.
- Keep write endpoints local and bounded. Vault-internal writes are allowed, `AGENTS.md` is read-only, and vault-external writes are never exposed.
- A browser clipper is highly valuable for personal memory, but it can be phase two. First support folder/file import; then add web capture.
- Multi-format ingestion matters, but Markdown/text/PDF should come first. DOCX, PPTX, XLSX, image captions, audio, and video can be staged later.
- The app should persist conversations, cited references, settings, conversation-level journal entries, rollback state, and ingest activity so recall context survives restarts.
- UI layout worth borrowing: left knowledge/source tree, center chat/command surface, right preview/reference panel.
- Avoid over-borrowing early complexity: Louvain clustering, surprising-connection scoring, deep research providers, and multimodal image ingestion are useful later, not kernel requirements.
