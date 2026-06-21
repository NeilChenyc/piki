# Piki macOS Client - Development Guide

## Project Overview

Piki is a local-first personal knowledge system. The macOS client (PikiApp/) communicates with a local Python Agent Service (agent_service/) via HTTP + SSE.

## Tech Stack

- **macOS 15.0+**, Swift 6.0+, SwiftUI
- **Architecture**: MVVM with @Observable
- **Networking**: URLSession async/await, SSE via URLSession bytes
- **Markdown**: Apple swift-markdown (SPM dependency)
- **Charts**: Swift Charts (system framework)
- **No third-party dependencies** except swift-markdown

## Swift & SwiftUI Rules

See `.claude/AGENTS-swift.md` for detailed Swift/SwiftUI coding rules. Key points:
- Target macOS 15.0+ (NOT iOS)
- Use `@Observable` classes marked `@MainActor`
- Use `NavigationSplitView` for multi-column layout
- Use `foregroundStyle()` not `foregroundColor()`
- Use `clipShape(.rect(cornerRadius:))` not `cornerRadius()`
- No UIKit — use AppKit only when SwiftUI has no equivalent
- No third-party frameworks without asking

## Architecture Skills

- `.claude/commands/swiftui-pro/` — SwiftUI best practices and review
- `.claude/commands/swift-architecture-skill/` — Architecture selection and patterns

## Agent Service API (localhost:8782)

The client connects to a local FastAPI service (auto-launched by the app via uvicorn). Key endpoints:
- `GET /health` — service health check
- `POST /tasks` — create agent task (query, ingest, etc.)
- `GET /tasks/{id}/events` — SSE event stream
- `GET /ingest-queue` — list queued items
- `POST /ingest-queue/enqueue` — add files to queue
- `POST /lint` — run vault lint check
- `GET /journal/recent` — recent change journal
- `POST /journal/{id}/rollback` — rollback changes

## Project Structure

```
PikiApp/
├── PikiApp.swift           // @main entry
├── Core/                   // Networking, vault access, models
├── Features/               // Per-page modules (Home, Inbox, Wiki, Health)
├── SharedUI/               // Theme, reusable components
└── Resources/              // Assets
```
