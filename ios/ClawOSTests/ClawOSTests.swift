//
//  ClawOSTests.swift
//  ClawOSTests
//
//  Created by Sid Qin on 2026/3/15.
//

import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClawOS

@MainActor
struct ClawOSTests {

    @Test("folder popover 拖拽使用长按激活")
    func folderPopoverDragUsesLongPressActivation() {
        #expect(AgentFolderPopoverDragBehavior.longPressDuration > 0)
        #expect(AgentFolderPopoverDragBehavior.longPressDuration <= 0.4)
        #expect(AgentFolderPopoverDragBehavior.dragStartDistance == 0)
    }

    @Test("folder popover 只有拖出阈值后才拆分 agent")
    func folderPopoverDragRequiresEscapeThreshold() {
        #expect(AgentFolderPopoverDragBehavior.shouldUngroup(for: CGSize(width: 0, height: 81)))
        #expect(AgentFolderPopoverDragBehavior.shouldUngroup(for: CGSize(width: 101, height: 0)))
        #expect(AgentFolderPopoverDragBehavior.shouldUngroup(for: CGSize(width: 60, height: 40)) == false)
    }

    @Test("startNewSession 为当前选中 agent 创建会话")
    func startNewSessionCreatesSessionForSelectedAgent() {
        let appState = AppState()
        appState.sessions = []
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

    @Test("group 内切换过 agent 后重新聚焦 group 不应把新建目标重置为第一个 agent")
    func groupSelectionKeepsChosenAgentForNewSession() {
        let appState = AppState()
        appState.selectedGatewayId = "gw-1"
        appState.agents = [
            Agent(id: "a1", name: "Ayanami", avatar: "", status: .online, unreadCount: 0, gatewayId: "gw-1"),
            Agent(id: "a2", name: "Asuka", avatar: "", status: .online, unreadCount: 0, gatewayId: "gw-1")
        ]
        let group = AgentGroup(id: "g1", name: "Group", agentIds: ["a1", "a2"])
        let groupItemId = "group_\(group.id)"
        appState.agentStripItems = [.group(group)]

        appState.selectStripItem(groupItemId)
        appState.selectAgentInGroup("a2", groupItemId: groupItemId)
        appState.selectStripItem(groupItemId)

        let session = appState.startNewSession()

        #expect(appState.selectedStripItemId == groupItemId)
        #expect(appState.selectedAgentId == "a2")
        #expect(session?.agentId == "a2")
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
            endpointUrl: "wss://relay.example.com",
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

    @Test("Gateway 运行时模型会同步到现有 agent")
    func updateAgentRuntimeModelUpdatesExistingAgent() {
        let appState = AppState()
        appState.agents = [
            Agent(
                id: "main",
                name: "主代理",
                avatar: "",
                status: .online,
                unreadCount: 0,
                gatewayId: "gw-1",
                model: nil,
                availableModels: nil
            )
        ]

        appState.updateAgentRuntimeModel(
            id: "main",
            modelDisplayValue: "anthropic/claude-opus-4-1"
        )

        #expect(appState.agents.first?.model == "anthropic/claude-opus-4-1")
        #expect(appState.agents.first?.availableModels == ["anthropic/claude-opus-4-1"])
    }

    @Test("addTokenUsage 累加并持久化 agent token 消耗")
    func addTokenUsageAccumulatesTokens() {
        let appState = AppState()
        appState.agents = [
            Agent(
                id: "main",
                name: "主代理",
                avatar: "",
                status: .online,
                unreadCount: 0,
                gatewayId: "gw-1",
                model: nil,
                availableModels: nil
            )
        ]

        appState.addTokenUsage(agentId: "main", tokens: 1500)
        #expect(appState.agents.first?.totalTokens == 1500)

        appState.addTokenUsage(agentId: "main", tokens: 800)
        #expect(appState.agents.first?.totalTokens == 2300)

        appState.addTokenUsage(agentId: "main", tokens: 0)
        #expect(appState.agents.first?.totalTokens == 2300)

        appState.addTokenUsage(agentId: "nonexistent", tokens: 100)
        #expect(appState.agents.first?.totalTokens == 2300)
    }

    @Test("startNewSession 为同一 agent 生成独立 sessionKey")
    func startNewSessionGeneratesDistinctSessionKeys() {
        let appState = AppState()
        appState.sessions = []
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

        let first = appState.startNewSession()
        let second = appState.startNewSession()
        let firstKey = first?.sessionKey
        let secondKey = second?.sessionKey

        #expect(first != nil)
        #expect(second != nil)
        #expect(firstKey != nil)
        #expect(secondKey != nil)
        #expect(firstKey?.isEmpty == false)
        #expect(secondKey?.isEmpty == false)
        #expect(firstKey != secondKey)
    }

    @Test("session 左滑交互偏移保持线性跟手")
    func sessionSwipeTracksDragLinearly() {
        let offset = SessionSwipeBehavior.interactiveOffset(
            initialOffset: 0,
            translation: -320
        )

        #expect(offset == -320)
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

    @Test("session 深拉但未达到确认阈值时仍停留在展开态")
    func sessionSwipeStaysRevealedBeforeArmedThreshold() {
        let target = SessionSwipeBehavior.settleTarget(
            currentOffset: -198,
            predictedEndOffset: -236,
            velocity: -210
        )

        #expect(target == .revealed)
        #expect(SessionSwipeBehavior.targetOffset(for: target) == -SessionSwipeBehavior.revealWidth)
    }

    @Test("session 删除按钮在接近 dominant 阈值时继续接管 rail 宽度")
    func sessionSwipeMetricsExpandDeleteWidthBeforeDominantStage() {
        let revealed = SessionSwipeBehavior.metrics(for: -130)
        let dominant = SessionSwipeBehavior.metrics(for: -190)

        #expect(revealed.stage == .actionsRevealed)
        #expect(dominant.stage == .actionsRevealed)
        #expect(dominant.pinWidth < revealed.pinWidth)
        #expect(dominant.deleteWidth > revealed.deleteWidth)
    }

    @Test("session 左滑进入删除确认区时 pin 会被完全挤压消失")
    func sessionSwipeConfirmZoneFullyHidesPin() {
        let armedMetrics = SessionSwipeBehavior.metrics(for: -SessionSwipeBehavior.confirmThreshold)

        #expect(armedMetrics.stage == .armedForDelete)
        #expect(armedMetrics.pinWidth == 0)
        #expect(armedMetrics.deleteWidth == armedMetrics.railWidth)
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

    @Test("agent 轨道入口和新增按钮尺寸与头像保持一致")
    func agentTrackUsesUnifiedControlSizing() {
        #expect(AgentTrackMetrics.controlDiameter == AgentTrackMetrics.avatarDiameter)
        #expect(AgentTrackMetrics.addButtonDiameter == AgentTrackMetrics.avatarDiameter)
    }

    @Test("编辑模式下点击单 agent 不触发选中")
    func stripTapIgnoresSingleItemWhileEditing() {
        let action = AgentStripTapBehavior.action(
            for: .single(agentId: "a1"),
            isEditMode: true,
            selectedStripItemId: "",
            folderOverlayActive: false
        )

        #expect(action == .ignore)
    }

    @Test("group 点击在 overlay 已展开时会关闭，否则会打开组")
    func stripTapTogglesGroupOverlay() {
        let group = AgentGroup(id: "g1", name: "Team", agentIds: ["a1", "a2"])

        let openAction = AgentStripTapBehavior.action(
            for: .group(group),
            isEditMode: false,
            selectedStripItemId: "",
            folderOverlayActive: false
        )
        let closeAction = AgentStripTapBehavior.action(
            for: .group(group),
            isEditMode: false,
            selectedStripItemId: "group_g1",
            folderOverlayActive: true
        )

        #expect(openAction == .openGroup(itemId: "group_g1"))
        #expect(closeAction == .closeGroup)
    }

    @Test("agent strip 拖拽会根据中心点计算插入位置")
    func stripDragComputesInsertionIndexFromHorizontalCenter() {
        let frames: [String: CGRect] = [
            "a1": CGRect(x: 0, y: 0, width: 50, height: 50),
            "a2": CGRect(x: 56, y: 0, width: 50, height: 50),
            "a3": CGRect(x: 112, y: 0, width: 50, height: 50),
        ]

        let index = AgentStripDragBehavior.insertionIndex(
            draggedID: "a2",
            draggedCenterX: 140,
            orderedIDs: ["a1", "a2", "a3"],
            frames: frames
        )

        #expect(index == 2)
    }

    @Test("agent strip 拖进目标 inset 区会识别 merge candidate")
    func stripDragDetectsMergeCandidateInsideInsetFrame() {
        let frames: [String: CGRect] = [
            "a1": CGRect(x: 0, y: 0, width: 60, height: 60),
            "a2": CGRect(x: 70, y: 0, width: 60, height: 60),
        ]

        let candidate = AgentStripDragBehavior.mergeCandidateID(
            draggedID: "a1",
            draggedCenter: CGPoint(x: 100, y: 30),
            orderedIDs: ["a1", "a2"],
            frames: frames
        )

        #expect(candidate == "a2")
    }

    @Test("拖拽态的视觉抬升优先级高于其他状态")
    func dragPresentationPrioritizesDraggedState() {
        let elevation = AgentDragPresentation.stripElevation(
            isSelected: true,
            isArmed: true,
            isDragged: true,
            isMergeCandidate: true,
            isMergeReady: true
        )

        #expect(elevation.scale == 1.16)
        #expect(elevation.yOffset == -6)
        #expect(elevation.shadowRadius == 16)
    }

    @Test("冷启动已登录用户跳过登录并显示开屏")
    func appLaunchSkipsLoginWhenAlreadyAuthenticated() {
        let state = AppLaunchPresentation.initialVisibility(hasLoggedIn: true)

        #expect(state.showLogin == false)
        #expect(state.showSplash == true)
        #expect(state.isSplashDone == false)
    }

    @Test("冷启动未登录用户展示登录页")
    func appLaunchShowsLoginWhenUnauthenticated() {
        let state = AppLaunchPresentation.initialVisibility(hasLoggedIn: false)

        #expect(state.showLogin == true)
        #expect(state.showSplash == false)
        #expect(state.isSplashDone == false)
    }

    @Test("Relay 配对默认地址为空")
    func relayPairingDefaultAddressIsEmpty() {
        #expect(PairingDefaults.relayUrl.isEmpty)
    }

    @Test("开屏结束后不再预热键盘避免闪烁")
    func splashCompletionDoesNotPrewarmKeyboard() {
        #expect(KeyboardPrewarmer.isEnabled == false)
    }

    @Test("东京行程故事文案不包含乱码替代字符")
    func ahaTravelStoryCopyHasNoReplacementCharacters() {
        let content = DashboardViewModel.defaultMoments
            .first(where: { $0.id == "aha_travel" })?
            .content

        #expect(content != nil)
        #expect(content?.contains("\u{FFFD}") == false)
        #expect(content?.contains("浅草到涩谷") == true)
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

    @Test("Aha 故事左边缘右滑即使带少量纵向抖动也应触发退出手势")
    func momentDismissBeginsFromEdgeWithVerticalNoise() {
        let axis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 24, y: 280),
            translation: CGSize(width: 18, height: 10),
            allowsContentHorizontalDismiss: false
        )

        #expect(axis == .horizontal)
    }

    @Test("Aha 故事第一页在内容区强右滑可触发退出，非第一页不误伤图片翻页")
    func momentDismissContentSwipeDependsOnImageIndex() {
        let firstImageAxis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 180, y: 320),
            translation: CGSize(width: 42, height: 12),
            allowsContentHorizontalDismiss: true
        )
        let laterImageAxis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 180, y: 320),
            translation: CGSize(width: 42, height: 12),
            allowsContentHorizontalDismiss: false
        )

        #expect(firstImageAxis == .horizontal)
        #expect(laterImageAxis == nil)
    }

    @Test("Aha 故事内容区仅左半屏起手右滑可触发退出")
    func momentDismissContentSwipeOnlyBeginsFromLeftHalf() {
        let leftHalfAxis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 180, y: 320),
            translation: CGSize(width: 42, height: 12),
            allowsContentHorizontalDismiss: true,
            contentHorizontalStartLimitX: 195
        )
        let rightHalfAxis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 240, y: 320),
            translation: CGSize(width: 42, height: 12),
            allowsContentHorizontalDismiss: true,
            contentHorizontalStartLimitX: 195
        )

        #expect(leftHalfAxis == .horizontal)
        #expect(rightHalfAxis == nil)
    }

    @Test("Agent Hub 头部隐藏标题并统一 liquid glass 控件")
    func agentHubHeaderChromeUsesUnifiedGlassControls() {
        #expect(AgentHubHeaderChrome.showsTitle == false)
        #expect(AgentHubHeaderChrome.controlDiameter == 40)
        #expect(AgentHubHeaderChrome.settingsUsesLiquidGlass)
    }

    @Test("Agent Hub 无 gateway 时左上角按钮仍提供配对入口")
    func agentHubGatewayMenuFallsBackToPairingWhenEmpty() {
        #expect(AgentHubGatewayMenuBehavior.mode(for: []) == .pairingOnly)
    }

    @Test("Agent Hub 有 gateway 时显示切换菜单并保留新增入口")
    func agentHubGatewayMenuShowsSwitcherWhenGatewaysExist() {
        let gateways = [
            Gateway(
                id: "gw-1",
                name: "Local",
                url: "ws://localhost:8787",
                type: .local,
                status: .online,
                ping: nil,
                connectionMethod: nil
            )
        ]

        #expect(AgentHubGatewayMenuBehavior.mode(for: gateways) == .switcherWithAdd)
    }

    @Test("隐私政策提供标准章节而非占位文本")
    func privacyPolicyUsesStandardSections() {
        let document = LegalDocumentContentProvider.document(for: .privacyPolicy)

        #expect(document.title == "隐私政策")
        #expect(document.summary.contains("ClawOS"))
        #expect(document.sections.contains { $0.title == "我们收集的信息" })
        #expect(document.sections.contains { $0.title == "我们如何使用信息" })
        #expect(document.sections.contains { $0.title == "第三方服务与数据共享" })
        #expect(document.sections.contains { $0.title == "数据存储与安全" })
        #expect(document.sections.contains { $0.title == "你的权利与选择" })
    }

    @Test("服务条款提供标准章节而非占位文本")
    func termsOfServiceUseStandardSections() {
        let document = LegalDocumentContentProvider.document(for: .termsOfService)

        #expect(document.title == "服务条款")
        #expect(document.summary.contains("ClawOS"))
        #expect(document.sections.contains { $0.title == "服务说明" })
        #expect(document.sections.contains { $0.title == "可接受使用规则" })
        #expect(document.sections.contains { $0.title == "用户内容与 AI 生成内容" })
        #expect(document.sections.contains { $0.title == "免责声明与责任限制" })
        #expect(document.sections.contains { $0.title == "条款更新与终止" })
    }

    @Test("Aha 故事水平退出时会锁定主方向并抑制纵向抖动")
    func momentDismissLocksHorizontalOffset() {
        let offset = MomentDismissGestureBehavior.resolvedOffset(
            for: CGSize(width: 120, height: 45),
            axis: .horizontal
        )

        #expect(offset.width == 120)
        #expect(offset.height < 12)
    }

    @Test("Aha 故事明显右滑时应更早判定为可退出")
    func momentDismissUsesResponsiveHorizontalThreshold() {
        let shouldDismiss = MomentDismissGestureBehavior.shouldDismiss(
            translation: CGSize(width: 96, height: 18),
            velocity: CGSize(width: 260, height: 40),
            axis: .horizontal
        )

        #expect(shouldDismiss)
    }

    @Test("Aha 故事内容区下拉不会触发退出手势")
    func momentDismissIgnoresVerticalPullInsideContent() {
        let axis = MomentDismissGestureBehavior.beginAxis(
            startLocation: CGPoint(x: 220, y: 520),
            translation: CGSize(width: 12, height: 72),
            allowsContentHorizontalDismiss: true
        )

        #expect(axis == nil)
    }

    @Test("交互返回配置只在首次启用时改写手势")
    func interactivePopConfigRunsOnlyOnce() {
        let recognizer = UIScreenEdgePanGestureRecognizer()
        recognizer.isEnabled = false
        recognizer.delegate = TestGestureDelegate()

        var hasConfigured = false

        InteractivePopGestureBehavior.configureIfNeeded(recognizer: recognizer, hasConfigured: &hasConfigured)

        #expect(hasConfigured)
        #expect(recognizer.isEnabled)
        #expect(recognizer.delegate == nil)

        let secondDelegate = TestGestureDelegate()
        recognizer.delegate = secondDelegate

        InteractivePopGestureBehavior.configureIfNeeded(recognizer: recognizer, hasConfigured: &hasConfigured)

        #expect(recognizer.delegate === secondDelegate)
    }

    @Test("Aha 详情布局指标固定卡片高度并保留底部间距语义")
    func momentDetailLayoutMetricsPreserveCurrentSizingRules() {
        let containerHeight: CGFloat = 844
        let safeBottomInset: CGFloat = 34

        #expect(MomentDetailLayoutMetrics.maxCardPull(for: containerHeight) == containerHeight * 0.45)
        #expect(MomentDetailLayoutMetrics.currentCardHeight(for: containerHeight, pullUp: 80) == containerHeight * 0.45)
        #expect(MomentDetailLayoutMetrics.ctaBottomPadding(for: safeBottomInset) == 20)
        #expect(MomentDetailLayoutMetrics.ctaBottomPadding(for: 10) == 16)
        #expect(MomentDetailLayoutMetrics.ctaReservedHeight(for: safeBottomInset) == 78)
    }

    @Test("Aha 详情退场距离改由容器尺寸驱动")
    func momentDetailLayoutMetricsUseContainerSizeForDismissTravel() {
        let travel = MomentDetailLayoutMetrics.dismissTravel(for: CGSize(width: 390, height: 844))

        #expect(travel.width == 450)
        #expect(travel.height == 904)
    }

    @Test("Aha 详情内容卡高度固定为默认高度")
    func momentDetailLayoutMetricsKeepCardHeightFixed() {
        let containerHeight: CGFloat = 844
        let defaultHeight = MomentDetailLayoutMetrics.currentCardHeight(for: containerHeight, pullUp: 0)
        let draggedHeight = MomentDetailLayoutMetrics.currentCardHeight(for: containerHeight, pullUp: 140)

        #expect(defaultHeight == containerHeight * 0.45)
        #expect(draggedHeight == defaultHeight)
    }

    @Test("Aha 详情 CTA 使用中性玻璃样式而非主题色")
    func momentDetailCTAStyleUsesNeutralGlass() {
        #expect(MomentDetailCTAStyle.usesTintedGlass == false)
    }

    @Test("Aha 详情固定卡片后隐藏顶部拖拽标识")
    func momentDetailLayoutMetricsHideTopHandleWhenCardIsFixed() {
        #expect(MomentDetailLayoutMetrics.showsTopHandle == false)
        #expect(MomentDetailLayoutMetrics.contentTopPadding == 20)
    }

}

private final class TestGestureDelegate: NSObject, UIGestureRecognizerDelegate {}
