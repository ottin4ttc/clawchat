# iOS Interaction Performance Optimization Plan

**Branch:** `perf/ios-interaction-smoothness`
**Base:** `fix/ios18-compat-and-ux-polish` (post PR #10)
**Date:** 2026-03-27

## Goal

Reduce main-thread stalls during typical Home-screen and Chat interactions: session list scrolling, search typing, avatar loading, and background persistence. Every fix targets measurable frame-time or latency improvement with zero behavioral change.

## Architecture Context

- `AppState` (@Observable) owns sessions, agents, messages, strip items
- Persistence uses `UserDefaults` via JSON encoding
- `AvatarStorage` does synchronous file I/O with a `[String: UIImage]` dictionary cache
- `RemoteImageLoader` is `@MainActor`, decodes images on the main thread
- `SessionListView.filteredSessions` does full-text search across all stored messages per render cycle

## Cross-Cutting Constraints

- Zero behavioral regressions — all persistence must remain durable
- No new dependencies
- Minimum-diff principle — touch only what is necessary
- All changes testable via existing test patterns

## Non-Goals

- Network layer optimization
- Chat message rendering pipeline changes (already uses TiledView)
- New caching infrastructure (stay with NSCache + dictionary)

---

## Tasks

### Task 1: Debounce Session Persistence

**Problem:** `sessions.didSet` calls `persistSessions()` synchronously on every mutation. During a single `applyConnectionInfo()` call, sessions may mutate multiple times. During `loadSessions()`, the setter re-persists what was just decoded.

**Fix:**
- Replace `didSet { persistSessions() }` with `didSet { scheduleSessionPersistence() }`
- Add `schedulePersistSessions()` with 300ms debounce + utility queue (mirror message persistence pattern)
- Skip re-persist during load using a `isLoadingSessions` flag
- Add `flushPendingSessionPersistence()` for app background hook

**Acceptance:** Session data survives app-kill. No synchronous UserDefaults writes during scrolling/filtering.

### Task 2: Debounce Search + Cap Full-Text Scanning

**Problem:** `filteredSessions` re-computes on every keystroke. It iterates *all messages* for *every session* doing `localizedCaseInsensitiveContains`. For 50 sessions × 100 messages each, that's 5,000 string comparisons per frame.

**Fix:**
- Add 250ms debounce on search text before it drives `filteredSessions`
- Split filtering: first pass checks only `session.title`, `agent.name`, `session.lastMessage` (cheap)
- Full-text message search only triggers after debounce settles, and limits to first N matches (e.g., 50)
- Serve stale results during debounce window for zero-jank typing

**Acceptance:** Typing in search produces zero frame drops on iPhone 15. Full-text results appear ≤ 300ms after typing stops.

### Task 3: Move AvatarStorage File I/O Off Main Thread

**Problem:** `AvatarStorage.load(for:)` does synchronous `Data(contentsOf:)` + `UIImage(data:)` on calling thread. When called from `AgentAvatarView` during scroll, this blocks the main thread.

**Fix:**
- Make `AvatarStorage.load(for:)` return cached value synchronously if available
- Add an async `loadAsync(for:)` that does file I/O on a background actor
- Update `AgentAvatarView` (or its call sites) to use the async path with a placeholder fallback

**Acceptance:** First-scroll of session list with uncached avatars shows no hitch.

### Task 4: Decode Images Off @MainActor in RemoteImageLoader

**Problem:** `RemoteImageLoader` is `@MainActor`. The `UIImage(data: data)` decode inside the task runs on the main thread, blocking the run loop for large images.

**Fix:**
- Move the network fetch + `UIImage(data:)` decode into a `Task.detached(priority: .userInitiated)` block
- Only assign to `self.image` back on `@MainActor`
- Keep `NSCache` lookup on main actor (it's already fast)

**Acceptance:** Loading a 2MB remote image does not drop frames in the session list.

### Task 5: Debounce Strip & Token Persistence

**Problem:** `agentStripItems.didSet` → `persistStripItems()` fires on every reorder/merge. `persistTokenUsage()` fires on every message response. Both do sync JSON encode + UserDefaults.

**Fix:**
- Apply same debounce pattern as Task 1 (300ms for strip, 1000ms for tokens)
- Add `flushPendingStripPersistence()` and `flushPendingTokenPersistence()` for app background

**Acceptance:** Rapid drag-reorder in agent strip produces no dropped frames.

---

## Verification

- `xcodebuild test` on existing test suite — all green (except known pre-existing failure)
- Manual smoke: scroll session list, type in search, reorder agents, open chat — no hitches
- Instruments Time Profiler spot-check on main thread during scroll
