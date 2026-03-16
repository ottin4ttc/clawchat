import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isSidebarOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private var resolvedOffset: CGFloat {
        if isDragging {
            if isSidebarOpen {
                return HomeSidebarMetrics.travelWidth + min(0, dragOffset)
            } else {
                return min(HomeSidebarMetrics.travelWidth, max(0, dragOffset))
            }
        }
        return isSidebarOpen ? HomeSidebarMetrics.travelWidth : 0
    }

    private var progress: CGFloat {
        min(1, max(0, resolvedOffset / HomeSidebarMetrics.travelWidth))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [appState.currentVisualTheme.pageGradientTop, appState.currentVisualTheme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            SessionListView(
                isSidebarDragging: isDragging || isSidebarOpen
            )
            .blur(radius: progress * 6)
            .scaleEffect(1.0 - progress * 0.03)

            Color.black
                .opacity(Double(progress) * 0.15)
                .ignoresSafeArea()
                .allowsHitTesting(isSidebarOpen && !isDragging)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isSidebarOpen = false
                    }
                }

            AgentSidebarView(onDismiss: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSidebarOpen = false
                }
            })
            .frame(width: HomeSidebarMetrics.sidebarWidth)
            .padding(.top, 12)
            .padding(.bottom, 96)
            .padding(.leading, HomeSidebarMetrics.sidebarLeadingPadding)
            .offset(x: resolvedOffset - HomeSidebarMetrics.travelWidth)
        }
        .simultaneousGesture(dragGesture)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSidebarOpen)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let startX = value.startLocation.x

                if !isDragging {
                    guard abs(dx) > abs(dy) * 1.2 else { return }

                    if isSidebarOpen {
                        isDragging = true
                    } else if dx > 0 && startX < 40 { // Only allow opening from the left edge (40pt)
                        isDragging = true
                    }
                }

                if isDragging {
                    dragOffset = dx
                }
            }
            .onEnded { value in
                guard isDragging else { return }

                let v = value.velocity.width
                let final = resolvedOffset

                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isSidebarOpen {
                        if final < HomeSidebarMetrics.travelWidth * 0.5 || v < -200 {
                            isSidebarOpen = false
                        }
                    } else {
                        if final > HomeSidebarMetrics.travelWidth * 0.4 || v > 200 {
                            isSidebarOpen = true
                        }
                    }
                    dragOffset = 0
                    isDragging = false
                }
            }
    }
}
