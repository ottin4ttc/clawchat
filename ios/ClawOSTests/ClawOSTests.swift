//
//  ClawOSTests.swift
//  ClawOSTests
//
//  Created by Sid Qin on 2026/3/15.
//

import Testing
import Foundation
import CoreGraphics
@testable import ClawOS

struct ClawOSTests {

    @Test("startNewSession 为当前选中 agent 创建会话")
    func startNewSessionCreatesSessionForSelectedAgent() {
        let appState = AppState()
        appState.agents = [
            Agent(
                id: "hulu",
                name: "呼噜",
                avatar: "",
                status: .online,
                unreadCount: 0,
                gatewayId: "gw-1",
                model: "claude-opus-4-6",
                availableModels: ["claude-opus-4-6"]
            )
        ]
        appState.selectedAgentId = "hulu"

        let session = appState.startNewSession()

        #expect(session != nil)
        #expect(session?.agentId == "hulu")
        #expect(session?.title == "新对话")
        #expect(appState.sessions.count == 1)
        #expect(appState.sessions.first?.id == session?.id)
    }

    @Test("deleteSession 删除指定会话")
    func deleteSessionRemovesMatchingSession() {
        let appState = AppState()
        appState.sessions = [
            Session(id: "s1", agentId: "hulu", title: "会话1", category: "对话", lastMessage: nil, lastMessageTime: nil, unreadCount: 0),
            Session(id: "s2", agentId: "hulu", title: "会话2", category: "对话", lastMessage: nil, lastMessageTime: nil, unreadCount: 0),
        ]

        appState.deleteSession(id: "s1")

        #expect(appState.sessions.count == 1)
        #expect(appState.sessions.first?.id == "s2")
    }

    @Test("applyConnectionInfo 解析 agent 描述中的名字模型与可用模型")
    func applyConnectionInfoParsesAgentDescriptor() {
        let appState = AppState()

        appState.applyConnectionInfo(
            gatewayId: "gw-1",
            relayUrl: "wss://relay.example.com",
            agentIds: ["hulu::呼噜::claude-opus-4-6::claude-opus-4-6||gpt-5.3-codex"]
        )

        #expect(appState.agents.count == 1)
        #expect(appState.agents.first?.id == "hulu")
        #expect(appState.agents.first?.name == "呼噜")
        #expect(appState.agents.first?.model == "claude-opus-4-6")
        #expect(appState.agents.first?.availableModels == ["claude-opus-4-6", "gpt-5.3-codex"])
    }

    @Test("appendMessage 在仅有附件时仍会更新会话预览")
    func appendMessageUsesAttachmentSummaryWhenTextEmpty() {
        let appState = AppState()
        appState.sessions = [
            Session(id: "s1", agentId: "hulu", title: "会话1", category: "对话", lastMessage: nil, lastMessageTime: nil, unreadCount: 0)
        ]

        let attachment = StoredMessageAttachment(
            id: "a1",
            type: .image,
            filename: "eva.png",
            mimeType: "image/png",
            size: 128
        )
        let message = StoredMessage(
            id: "m1",
            role: .user,
            text: "",
            attachments: [attachment],
            timestamp: Date()
        )

        appState.appendMessage(to: "s1", message: message)

        #expect(appState.sessions.first?.lastMessage == "附件：eva.png")
    }

    @Test("session 左滑超过确认阈值后会进入阻尼区")
    func sessionSwipeDampensBeyondConfirmThreshold() {
        let offset = SessionSwipeBehavior.interactiveOffset(
            initialOffset: 0,
            translation: -320
        )

        #expect(offset < -SessionSwipeBehavior.confirmThreshold)
        #expect(offset > -320)
    }

    @Test("session 中段左滑松手会吸附到动作展开态")
    func sessionSwipeSettlesToRevealForModerateDrag() {
        let target = SessionSwipeBehavior.settleTarget(
            currentOffset: -108,
            predictedEndOffset: -148,
            velocity: -180
        )

        #expect(target == .revealed)
        #expect(SessionSwipeBehavior.targetOffset(for: target) == -SessionSwipeBehavior.revealWidth)
    }

    @Test("session 深拉松手会进入删除确认就绪态")
    func sessionSwipeSettlesToArmedForDelete() {
        let target = SessionSwipeBehavior.settleTarget(
            currentOffset: -198,
            predictedEndOffset: -236,
            velocity: -210
        )

        #expect(target == .armedForDelete)
        #expect(SessionSwipeBehavior.targetOffset(for: target) == -SessionSwipeBehavior.armedLockWidth)
    }

    @Test("session 删除接管阶段会压缩 pin 并扩展删除按钮")
    func sessionSwipeMetricsShiftFromPinToDelete() {
        let revealed = SessionSwipeBehavior.metrics(for: -130)
        let dominant = SessionSwipeBehavior.metrics(for: -190)

        #expect(revealed.stage == .actionsRevealed)
        #expect(dominant.stage == .deleteDominant)
        #expect(dominant.pinWidth < revealed.pinWidth)
        #expect(dominant.deleteWidth > revealed.deleteWidth)
    }

    @Test("session 左滑进入删除确认区时 pin 会被完全挤压消失")
    func sessionSwipeConfirmZoneFullyHidesPin() {
        let armedMetrics = SessionSwipeBehavior.metrics(for: -SessionSwipeBehavior.confirmThreshold)

        #expect(armedMetrics.stage == .armedForDelete)
        #expect(armedMetrics.pinWidth == 0)
        #expect(armedMetrics.deleteWidth == SessionSwipeBehavior.armedLockWidth)
    }

    @Test("Siri glow 在没有键盘时保持整屏边缘模式")
    func siriGlowUsesFullscreenModeWithoutKeyboard() {
        let screen = CGRect(x: 0, y: 0, width: 393, height: 852)

        let mode = SiriGlowLayout.mode(for: screen, keyboardFrame: nil)

        #expect(mode == .fullScreen)
    }

    @Test("Siri glow 在底部键盘出现时切换为键盘顶部光带")
    func siriGlowUsesKeyboardTopModeWhenKeyboardVisible() {
        let screen = CGRect(x: 0, y: 0, width: 393, height: 852)
        let keyboard = CGRect(x: 0, y: 548, width: 393, height: 304)

        let mode = SiriGlowLayout.mode(for: screen, keyboardFrame: keyboard)

        guard case .keyboardTop(let glowFrame) = mode else {
            Issue.record("Expected keyboardTop glow mode")
            return
        }

        #expect(glowFrame.minY < keyboard.minY)
        #expect(glowFrame.maxY > keyboard.minY)
        #expect(glowFrame.minX > screen.minX)
        #expect(glowFrame.maxX < screen.maxX)
    }

    @Test("打字机效果每个节拍只前进固定字符数")
    func typewriterAdvanceUsesFixedStep() {
        let next = StreamingTypewriter.nextDisplayText(
            current: "",
            target: "你好世界",
            charactersPerTick: 2
        )

        #expect(next == "你好")
    }

    @Test("打字机效果不会超过真实已返回内容")
    func typewriterAdvanceNeverExceedsTarget() {
        let next = StreamingTypewriter.nextDisplayText(
            current: "你好世",
            target: "你好世界",
            charactersPerTick: 8
        )

        #expect(next == "你好世界")
    }

    @Test("打字机效果遇到最终文本回退时会以真实文本为准")
    func typewriterAdvanceSnapsToAuthoritativeTargetWhenCurrentIsNotPrefix() {
        let next = StreamingTypewriter.nextDisplayText(
            current: "hello world world",
            target: "hello world",
            charactersPerTick: 2
        )

        #expect(next == "hello world")
    }

    @Test("打字机滚动跟随节奏比字符输出节奏更快")
    func typewriterScrollFollowCadenceIsFasterThanTypingCadence() {
        #expect(StreamingTypewriter.followScrollDelayMilliseconds < StreamingTypewriter.tickIntervalMilliseconds)
    }

    @Test("聊天滚动恢复会选择最接近顶部的可见消息")
    func chatScrollAnchorChoosesTopVisibleMessage() {
        let frames: [String: CGRect] = [
            "m1": CGRect(x: 0, y: -88, width: 200, height: 60),
            "m2": CGRect(x: 0, y: -12, width: 200, height: 60),
            "m3": CGRect(x: 0, y: 44, width: 200, height: 60),
            "m4": CGRect(x: 0, y: 520, width: 200, height: 60)
        ]

        let anchorId = ChatScrollAnchorResolver.anchorMessageID(
            from: frames,
            viewportHeight: 480
        )

        #expect(anchorId == "m2")
    }

    @Test("聊天滚动恢复会忽略完全不可见的消息")
    func chatScrollAnchorIgnoresOffscreenMessages() {
        let frames: [String: CGRect] = [
            "m1": CGRect(x: 0, y: -200, width: 200, height: 60),
            "m2": CGRect(x: 0, y: 520, width: 200, height: 60)
        ]

        let anchorId = ChatScrollAnchorResolver.anchorMessageID(
            from: frames,
            viewportHeight: 480
        )

        #expect(anchorId == nil)
    }

    @Test("sidebar 入口尺寸与 agent 头像基准保持一致")
    func sidebarUsesUnifiedAvatarSizing() {
        #expect(HomeSidebarMetrics.controlDiameter == HomeSidebarMetrics.avatarDiameter)
        #expect(HomeSidebarMetrics.addButtonDiameter == HomeSidebarMetrics.avatarDiameter)
    }

    @Test("sidebar 宽度收窄到 66pt")
    func sidebarUsesCompactWidth() {
        #expect(HomeSidebarMetrics.sidebarWidth == 66)
    }

    @Test("session 长按预览默认锚定到最后一条消息")
    func sessionPreviewAnchorsToLastMessage() {
        let messages = [
            StoredMessage(id: "m1", role: .user, text: "第一条", timestamp: Date()),
            StoredMessage(id: "m2", role: .assistant, text: "第二条", timestamp: Date()),
            StoredMessage(id: "m3", role: .user, text: "最新一条", timestamp: Date())
        ]

        let anchorId = SessionPreviewScrollAnchorResolver.initialAnchorMessageID(in: messages)

        #expect(anchorId == "m3")
    }

    @Test("session 长按预览在没有消息时不设置锚点")
    func sessionPreviewHasNoAnchorWhenEmpty() {
        let anchorId = SessionPreviewScrollAnchorResolver.initialAnchorMessageID(in: [])

        #expect(anchorId == nil)
    }

}
