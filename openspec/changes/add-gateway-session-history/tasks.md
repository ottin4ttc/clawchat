# Tasks: add-gateway-session-history

## Phase 1: 扩展 GatewayFrames 数据模型

- [x] 扩展 `GatewaySessionsListResult.SessionEntry`，新增 `label`、`derivedTitle`、`lastMessagePreview`、`updatedAt`、`kind`、`totalTokens` 字段
- [x] 新增辅助方法 `displayTitle` 和 `parsedAgentId`，方便从 `SessionEntry` 提取标题和 agentId

## Phase 2: GatewaySession 新增 fetchSessionHistory

- [x] 在 `GatewaySession.swift` 新增 `public var onSessionHistoryLoaded: (([GatewaySessionsListResult.SessionEntry]) -> Void)?` 回调
- [x] 新增 `fetchSessionHistory()` 方法：调用 `sessions.list`（`includeDerivedTitles: true`, `includeLastMessage: true`, `limit: 50`），成功后触发 `onSessionHistoryLoaded`
- [x] 在 `handleHelloOk()` 中，`refreshAgentsCatalog()` 之后调用 `fetchSessionHistory()`

## Phase 3: ClawChatManager 接入

- [x] 在 `setupGatewaySessionCallbacks()` 中注册 `onSessionHistoryLoaded` 回调
- [x] 回调中调用 `AppState.mergeGatewaySessions()`

## Phase 4: AppState 合并逻辑

- [x] 新增 `mergeGatewaySessions(_ entries: [GatewaySessionsListResult.SessionEntry])` 方法
- [x] 合并逻辑：以 `sessionKey` 匹配，网关数据更新 title/lastMessage/lastMessageTime，本地数据保留 isPinned/unreadCount
- [x] 新 session（本地不存在的 key）插入到列表
- [x] 过滤掉 agentId 不在当前 `agents` 列表中的 session

## Phase 5: 验证

- [ ] 连接网关后确认历史 session 出现在列表中
- [ ] 确认本地创建的 session 不会被网关合并覆盖丢失
- [ ] 确认 isPinned 等本地状态在合并后保留
