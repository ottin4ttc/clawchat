# Proposal: add-gateway-session-history

## Why

iOS 连接网关成功后，看不到历史 session 列表。当前 `sessions.list` RPC 只被用于解析 model 配置（`refreshSessionModel`），返回的 session 列表数据被丢弃。用户换设备或重装 app 后，之前的对话历史全部丢失。

Web 端已有完整的历史 session 加载逻辑（`useChatSessions.ts`），iOS 需要对齐。

## What Changes

1. **GatewaySession 新增 `fetchSessionHistory()` 方法** — 调用 `sessions.list` 并携带 `includeDerivedTitles: true` + `includeLastMessage: true`，返回完整的 session 列表
2. **新增 `onSessionHistoryLoaded` 回调** — 将网关返回的 session 列表传递给 ClawChatManager
3. **ClawChatManager 在连接成功后自动调用** — 获取历史 session 并合并到 AppState
4. **AppState 新增 `mergeGatewaySessions()` 方法** — 将网关返回的 session 与本地 session 合并（网关为主，本地补充 isPinned/unreadCount 等本地状态）
5. **GatewaySessionsListResult 扩展** — 解析 `derivedTitle`、`lastMessagePreview`、`updatedAt` 等字段（当前 `SessionEntry` 只有 model 相关字段）

## Impact

- **ClawChatKit**: `GatewaySession.swift` + `GatewayFrames.swift` 修改
- **App 层**: `ClawChatManager.swift` + `AppState.swift` 修改
- **UI 层**: 无变化，`SessionListView` 已能正确渲染 `appState.sessions`
- **风险**: 低，新增逻辑不影响现有连接和聊天流程
