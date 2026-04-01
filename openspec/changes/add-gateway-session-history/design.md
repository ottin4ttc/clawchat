# Design: add-gateway-session-history

## 数据流

```
Gateway 连接成功 (handleHelloOk)
  ↓
refreshAgentsCatalog()          ← 已有
  ↓
fetchSessionHistory()           ← 新增
  ↓ sessions.list RPC (includeDerivedTitles=true, includeLastMessage=true)
  ↓
onSessionHistoryLoaded?(sessions)  ← 新增回调
  ↓
ClawChatManager
  ↓
AppState.mergeGatewaySessions()  ← 新增
  ↓
SessionListView 自动刷新（@Observable）
```

## Gateway sessions.list 参数

```json
{
  "includeDerivedTitles": true,
  "includeLastMessage": true,
  "includeGlobal": false,
  "includeUnknown": false,
  "limit": 50
}
```

不传 `agentId`，获取所有 agent 的 session。

## GatewaySessionsListResult 扩展

当前 `SessionEntry` 只有 model 字段，需要扩展支持：

```swift
public struct SessionEntry: Decodable, Sendable {
    // 已有
    public let key: String
    public let modelProvider: String?
    public let model: String?
    
    // 新增
    public let label: String?
    public let derivedTitle: String?
    public let lastMessagePreview: String?
    public let updatedAt: Int64?       // ms timestamp
    public let kind: String?           // direct / group / global
    public let totalTokens: Int?
}
```

## Session 合并策略

以 `sessionKey` 为合并键：

| 字段 | 来源 |
|------|------|
| `id` | 本地已有则保留，否则用 `sessionKey` 生成 |
| `agentId` | 从 `sessionKey` 解析（`agent:<agentId>:<rest>`） |
| `sessionKey` | 网关 `key` |
| `title` | 优先 `derivedTitle`，fallback `label`，fallback 本地 `title` |
| `lastMessage` | 网关 `lastMessagePreview` 优先，fallback 本地 |
| `lastMessageTime` | 网关 `updatedAt` 转 Date 优先，fallback 本地 |
| `isPinned` | 保留本地值 |
| `unreadCount` | 保留本地值 |
| `category` | 固定 "对话" |

## 时序考虑

- `fetchSessionHistory()` 在 `refreshAgentsCatalog()` 之后调用，确保 agent 列表已就绪
- 合并时只保留 `appState.agents` 中存在的 agentId 对应的 session，过滤掉已删除 agent 的 session
