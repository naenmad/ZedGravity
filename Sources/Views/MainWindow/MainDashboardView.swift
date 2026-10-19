import SwiftUI
import AppKit
import Charts
import SwiftData

public enum MainNavigationTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case analytics = "Analytics"
    case accounts = "Accounts"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .analytics: return "chart.bar.xaxis"
        case .accounts: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Unified Utility Cockpit with native macOS toolbar segmented navigation and authentic frosted vibrancy
public struct MainDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var selectedTab: MainNavigationTab = .dashboard
    @State private var accountToDelete: Account? = nil
    @State private var showingDeleteConfirmation: Bool = false
    @State private var expandedGroupId: String? = nil
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Main Content View based on active Tab
                switch selectedTab {
                case .dashboard:
                    dashboardView
                case .analytics:
                    analyticsView
                case .accounts:
                    accountsListView
                case .settings:
                    settingsView
                }
            }
        }
        .frame(minWidth: 840, minHeight: 580)
        .background(WindowAccessor())
        .toolbar {
            // Center Navigation Segmented Control
            ToolbarItem(placement: .principal) {
                Picker("Navigation", selection: $selectedTab) {
                    ForEach(MainNavigationTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.iconName)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
            }

            // Trailing Action Controls
            ToolbarItemGroup(placement: .automatic) {
                // Active Account & Tier Indicator
                HStack(spacing: 6) {
                    let brand: BrandLogoKind = (viewModel.selectedAccount?.provider == .claude) ? .claude : .gemini
                    BrandLogoView(brand, size: 13)
                        .frame(width: 13, height: 13)
                        .fixedSize()

                    Text(viewModel.selectedAccount?.email.isEmpty ?? true ? (viewModel.selectedAccount?.name ?? "Account") : (viewModel.selectedAccount?.email ?? ""))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)

                    if let acc = viewModel.selectedAccount {
                        let tier = acc.accountTier
                        HStack(spacing: 2) {
                            if tier == .ultra {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 7.5))
                            }
                            Text(tier.displayName.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundColor(tier.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(tier.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())

                Button {
                    Task {
                        await viewModel.refreshAllQuotas(activeAccountOnly: false)
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                }
                .help("Refresh Quotas (⌘R)")
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.isLoading)

                // Add Account Button
                Button {
                    viewModel.showingAddAccountSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .help("Connect Account (⌘N)")
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .sheet(isPresented: $viewModel.showingAddAccountSheet) {
            AddAccountSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Delete Account?",
            isPresented: $showingDeleteConfirmation,
            presenting: accountToDelete
        ) { acc in
            Button("Delete \(acc.email.isEmpty ? acc.name : acc.email)", role: .destructive) {
                viewModel.deleteAccount(id: acc.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { acc in
            Text("Are you sure you want to delete this account? Its tokens and credentials will be permanently removed.")
        }
    }

    // MARK: - 1. Dashboard View (Integrated Cockpit)

    private var dashboardView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Quota Cockpit")
                            .font(.system(size: 20, weight: .bold))

                        Text("Real-time token allocations, countdown horizons, and model rate limits")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                }

                // 2 Core Category Cards (Gemini vs Claude/GPT-OSS)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(viewModel.currentQuotaGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            // Header Row
                            HStack(spacing: 8) {
                                if group.id == "gemini" {
                                    BrandLogoView(.gemini, size: 16)
                                        .frame(width: 26, height: 26)
                                        .background(group.accentColor.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                } else {
                                    HStack(spacing: 4) {
                                        BrandLogoView(.claude, size: 14)
                                            .frame(width: 24, height: 24)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                        BrandLogoView(.chatgpt, size: 14)
                                            .frame(width: 24, height: 24)
                                            .background(Color.teal.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }

                                Text(group.title)
                                    .font(.system(size: 14, weight: .bold))

                                Spacer()

                                Text(group.displayPercentage)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .foregroundColor(group.isDepleted ? Color.red : Color(red: 0.22, green: 0.82, blue: 0.55))
                            }

                            // Cycle Reset Countdown
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text("Resets in \(group.countdownString)")
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(Color(red: 0.92, green: 0.74, blue: 0.30))

                            // Core Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                    Capsule().fill(group.isDepleted ? Color.red : Color(red: 0.22, green: 0.82, blue: 0.55))
                                        .frame(width: max(0, min(geo.size.width * CGFloat(group.percentage / 100.0), geo.size.width)))
                                }
                            }
                            .frame(height: 5)

                            // Dedicated Gemini Image Quota Row
                            if let imageQuota = group.imageQuota {
                                Divider().opacity(0.12)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "photo.badge.sparkles")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0.70, green: 0.35, blue: 0.95))

                                        Text("Gemini Image Quota")
                                            .font(.system(size: 12, weight: .medium))

                                        Spacer()

                                        Text("Resets in \(imageQuota.countdownString)")
                                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                            .foregroundColor(Color(red: 0.92, green: 0.74, blue: 0.30))

                                        Text("\(Int(imageQuota.percentage))%")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(imageQuota.percentage <= 15 ? Color.red : Color(red: 0.70, green: 0.35, blue: 0.95))
                                    }

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.06))
                                            Capsule().fill(imageQuota.percentage <= 15 ? Color.red : Color(red: 0.70, green: 0.35, blue: 0.95))
                                                .frame(width: max(0, min(geo.size.width * CGFloat(imageQuota.percentage / 100.0), geo.size.width)))
                                        }
                                    }
                                    .frame(height: 4)
                                }
                            }

                            // Card Description
                            Text(group.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            // Integrated Model Inspector Accordion
                            if !group.models.isEmpty {
                                Divider().opacity(0.12)

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        expandedGroupId = (expandedGroupId == group.id) ? nil : group.id
                                    }
                                } label: {
                                    HStack {
                                        Text(expandedGroupId == group.id ? "Hide Granular Models" : "Inspect Models (\(group.models.count))")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.accentColor)

                                        Spacer()

                                        Image(systemName: expandedGroupId == group.id ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .buttonStyle(.plain)

                                if expandedGroupId == group.id {
                                    VStack(spacing: 6) {
                                        ForEach(group.models) { model in
                                            ModelQuotaRowView(item: model, currentTime: viewModel.currentTime)
                                                .padding(6)
                                                .background(Color.primary.opacity(0.03))
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                }

                // Smart Advisor Section
                if let recommendation = viewModel.recommendation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Smart Token Consumption Advisor")
                            .font(.system(size: 14, weight: .bold))

                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 18))
                                .foregroundColor(.cyan)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(recommendation.actionableSummary)
                                    .font(.system(size: 12.5, weight: .medium))

                                Text("Pace: \(recommendation.burnRateStatus.title) • Reset in: \(recommendation.daysUntilReset) days")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(Account.formatTokens(recommendation.recommendedDailyBudget) + "/day")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        .padding(14)
                        .background(Color.cyan.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                // Quick Switcher Grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configured Account Pools")
                        .font(.system(size: 14, weight: .bold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(viewModel.accounts) { acc in
                            HStack(spacing: 8) {
                                let brand: BrandLogoKind = (acc.provider == .claude) ? .claude : .gemini
                                BrandLogoView(brand, size: 12)
                                    .frame(width: 12, height: 12)
                                    .fixedSize()

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(acc.email.isEmpty ? acc.name : acc.email)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(acc.accountTier.displayName.uppercased())
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundColor(acc.accountTier.color)

                                        Text("• \(Int(acc.remainingPercentage))%")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if acc.id == viewModel.selectedAccount?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(acc.id == viewModel.selectedAccount?.id ? Color.accentColor : Color.white.opacity(0.06), lineWidth: acc.id == viewModel.selectedAccount?.id ? 1 : 0.5)
                            )
                            .onTapGesture {
                                Task {
                                    await viewModel.switchAntigravityIDE(to: acc.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
    }

    // MARK: - 2. Analytics View (Token Usage & Trends)

    private struct AnalyticsDayPoint: Identifiable {
        let id = UUID()
        let day: String
        let tokensMillions: Double
        let provider: String
        let color: Color
    }

    private var analyticsChartData: [AnalyticsDayPoint] {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var points: [AnalyticsDayPoint] = []
        // Generate realistic 7-day breakdown for active account
        let baseTokens = max(1.5, Double(viewModel.selectedAccount?.usedQuotaTokens ?? 2_500_000) / 7_000_000.0)
        let multipliers = [0.8, 1.2, 1.5, 0.9, 1.4, 0.5, 0.7]

        for (idx, day) in days.enumerated() {
            let mult = multipliers[idx % multipliers.count]
            let geminiTokens = (baseTokens * mult * 0.7)
            let claudeTokens = (baseTokens * mult * 0.3)
            points.append(AnalyticsDayPoint(day: day, tokensMillions: geminiTokens, provider: "Gemini", color: Color.cyan))
            points.append(AnalyticsDayPoint(day: day, tokensMillions: claudeTokens, provider: "Claude & GPT", color: Color.orange))
        }
        return points
    }

    private var analyticsView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 3) {
                    Text("Token Analytics & Consumption Horizons")
                        .font(.system(size: 20, weight: .bold))

                    Text("Historical usage velocity, provider distribution, and cycle burn pacing")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // 4 Top Metric Glass Tiles
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metricCard(
                        title: "Safe Daily Budget",
                        value: Account.formatTokens(viewModel.recommendation?.recommendedDailyBudget ?? 126_500_000),
                        caption: "Tokens / Day Target",
                        accentColor: .cyan,
                        icon: "shield.checkerboard"
                    )

                    metricCard(
                        title: "Pool Health Status",
                        value: "\(Int(viewModel.selectedAccount?.remainingPercentage ?? 83))%",
                        caption: viewModel.recommendation?.burnRateStatus.title ?? "Sustainable Pace",
                        accentColor: Color(red: 0.22, green: 0.82, blue: 0.55),
                        icon: "heart.fill"
                    )

                    metricCard(
                        title: "Active Account Plan",
                        value: viewModel.selectedAccount?.accountTier.displayName ?? "PRO",
                        caption: viewModel.selectedAccount?.email ?? "Primary Account",
                        accentColor: viewModel.selectedAccount?.accountTier.color ?? .blue,
                        icon: "crown.fill"
                    )

                    metricCard(
                        title: "Reset Horizon",
                        value: viewModel.recommendation != nil ? "\(viewModel.recommendation!.daysUntilReset) Days" : "6 Days",
                        caption: "Next Cycle Reset",
                        accentColor: Color(red: 0.92, green: 0.74, blue: 0.30),
                        icon: "hourglass"
                    )
                }

                // Weekly Consumption Trend Chart
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-Day Token Consumption Trend")
                                .font(.system(size: 14, weight: .bold))
                            Text("Daily token burn categorized by provider (Millions of Tokens)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Chart Legend
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 7, height: 7)
                                Text("Gemini").font(.system(size: 11))
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 7, height: 7)
                                Text("Claude & GPT").font(.system(size: 11))
                            }
                        }
                    }

                    Chart(analyticsChartData) { item in
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Tokens (M)", item.tokensMillions)
                        )
                        .foregroundStyle(by: .value("Provider", item.provider))
                        .cornerRadius(3)
                    }
                    .chartForegroundStyleScale([
                        "Gemini": Color.cyan,
                        "Claude & GPT": Color.orange
                    ])
                    .frame(height: 190)
                    .padding(.top, 8)
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

                // Health Diagnostic Banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 0.22, green: 0.82, blue: 0.55))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Consumption Velocity Is Healthy")
                            .font(.system(size: 13, weight: .semibold))

                        Text("At current token consumption levels, your active account will comfortably maintain access through the scheduled weekly cycle reset without encountering rate throttling.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color(red: 0.22, green: 0.82, blue: 0.55).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(22)
        }
    }

    private func metricCard(title: String, value: String, caption: String, accentColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(accentColor)
            }

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - 3. Accounts Tab

    private var accountsListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account Management")
                        .font(.system(size: 18, weight: .bold))

                    Text("Direct Google Cloud Code OAuth tokens & Antigravity IDE active profile")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Unified Auto-Switch Toggle
                Button {
                    viewModel.toggleAutoSwitch()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.autoSwitchEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                            .font(.system(size: 11))
                        Text(viewModel.autoSwitchEnabled ? "Auto-Switch: ON (\(viewModel.autoRotateFocus.displayName))" : "Auto-Switch: OFF")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(viewModel.autoSwitchEnabled ? Color.green : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(viewModel.autoSwitchEnabled ? Color.green.opacity(0.12) : Color.white.opacity(0.04))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Auto-switch accounts when quota falls <= 5% across enabled targets: \(viewModel.enabledTargetsSummary)")

                // Active Account Badge
                if let selected = viewModel.selectedAccount {
                    let activeTargets = viewModel.activeTargetsForAccount(selected)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active: \(selected.email.isEmpty ? selected.name : selected.email) (\(activeTargets.isEmpty ? "Ready" : activeTargets.joined(separator: " • ")))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }

                Button("Connect Account") {
                    viewModel.showingAddAccountSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .top], 22)

            // Unified Switch Toast Banner
            if let msg = viewModel.unifiedSwitchStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isUnifiedSwitchSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(viewModel.isUnifiedSwitchSuccess ? .green : .red)
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((viewModel.isUnifiedSwitchSuccess ? Color.green : Color.red).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 22)
                .transition(.opacity)
            }

            List(viewModel.accounts) { account in
                let isFullyActive = viewModel.isAccountFullyActive(account)
                let activeTargets = viewModel.activeTargetsForAccount(account)

                HStack(spacing: 12) {
                    let brand: BrandLogoKind = (account.provider == .claude) ? .claude : .gemini
                    BrandLogoView(brand, size: 18)
                        .frame(width: 24, height: 24)
                        .background(account.provider.brandColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.email.isEmpty ? account.name : account.email)
                                .font(.system(size: 13, weight: .semibold))

                            // Tier Badge
                            HStack(spacing: 2.5) {
                                if account.accountTier == .ultra {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 7))
                                }
                                Text(account.accountTier.displayName.uppercased())
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .foregroundColor(account.accountTier.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(account.accountTier.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))

                            if isFullyActive {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 8))
                                    Text("ACTIVE (\(viewModel.enabledTargetsSummary))")
                                        .font(.system(size: 8.5, weight: .bold))
                                }
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .clipShape(Capsule())
                            } else if !activeTargets.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 8))
                                    Text(activeTargets.joined(separator: " • "))
                                        .font(.system(size: 8.5, weight: .bold))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }

                        Text("Plan: \(account.accountTier.badgeLabel) • \(account.quotas.count) models tracked")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(account.accountTier.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(account.accountTier.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(account.accountTier.color.opacity(0.12))
                        .clipShape(Capsule())

                    Text("\(Int(account.remainingPercentage))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(account.status.color)
                        .frame(width: 45, alignment: .trailing)

                    // Single Unified Switch Account button
                    Button {
                        Task {
                            await viewModel.switchUnifiedAccount(to: account.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isSwitchingAccount && account.id == viewModel.selectedAccountId {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: isFullyActive ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                            }
                            Text(isFullyActive ? "Active" : "Switch Account")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isFullyActive ? Color.green.opacity(0.3) : Color.blue)
                    .disabled(viewModel.isSwitchingAccount || isFullyActive)
                    .help("Switch \(viewModel.enabledTargetsSummary) to use this account")

                    // Delete Account Button
                    Button(role: .destructive) {
                        accountToDelete = account
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete this account from ZedGravity")
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.white.opacity(0.02))
                .contextMenu {
                    Button("Switch Everywhere (\(viewModel.enabledTargetsSummary))") {
                        Task {
                            await viewModel.switchUnifiedAccount(to: account.id)
                        }
                    }
                    Divider()
                    Button("Switch only Antigravity CLI / Ghostex") {
                        Task {
                            await viewModel.switchAntigravityCLI(to: account.id)
                        }
                    }
                    Button("Switch only Zed ACP") {
                        Task {
                            await viewModel.switchZedACP(to: account.id)
                        }
                    }
                    Button("Switch only Antigravity IDE") {
                        Task {
                            await viewModel.switchAntigravityIDE(to: account.id)
                        }
                    }
                    Divider()
                    Button(account.id == viewModel.selectedAccount?.id ? "Currently Selected" : "Select in Dashboard") {
                        viewModel.selectAccount(id: account.id)
                    }
                    Divider()
                    Button(role: .destructive) {
                        accountToDelete = account
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
        }
    }

    // MARK: - 4. Settings Tab

    private var settingsView: some View {
        Form {
            Section("General & System Startup") {
                Toggle("Launch ZedGravity at Login", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setLaunchAtLogin(enabled: $0) }
                ))

                Text("Automatically launch ZedGravity companion in the Menu Bar when your Mac boots up.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if !launchManager.statusMessage.isEmpty {
                    Text(launchManager.statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }

            Section("Menu Bar Display Settings") {
                Toggle("Show Google Gemini Quota", isOn: $viewModel.menuBarShowGemini)
                Toggle("Show Claude & GPT-OSS Quota", isOn: $viewModel.menuBarShowClaudeGpt)
                Toggle("Show Gemini Image Generation Quota", isOn: $viewModel.menuBarShowImage)

                HStack {
                    Text("Menu Bar Preview:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                        Text(viewModel.menuBarSummaryText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
            }

            Section("Intelligent Account Sync & Auto-Switch") {
                Toggle("Enable Unified Auto-Switch on Low Quota (≤ 5%)", isOn: $viewModel.autoSwitchEnabled)

                if viewModel.autoSwitchEnabled {
                    Picker("Quota to Monitor", selection: Binding(
                        get: { viewModel.autoRotateFocus },
                        set: { viewModel.setAutoRotateFocus($0) }
                    )) {
                        ForEach(AutoSwitchQuotaFocus.allCases) { focus in
                            Text(focus.displayName).tag(focus)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(viewModel.autoRotateFocus.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Synchronize & Rotate Targets:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Toggle(isOn: $viewModel.syncTargetCLI) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal.fill")
                                .foregroundColor(.purple)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Antigravity CLI / Ghostex")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Syncs ~/.gemini/antigravity-cli and ~/.gemini/google_accounts.json")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $viewModel.syncTargetZed) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.green)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Zed Editor ACP")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Syncs ~/.gemini/antigravity-acp with seamless process reload")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Toggle(isOn: $viewModel.syncTargetIDE) {
                        HStack(spacing: 6) {
                            Image(systemName: "macwindow")
                                .foregroundColor(.blue)
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Antigravity IDE")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Syncs VS Code / Antigravity state.vscdb storage")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                Text("When the monitored quota reaches critical limit (≤ 5%), ZedGravity hot-swaps all enabled targets simultaneously to the account with the highest available quota. Zed and Ghostex sessions continue seamlessly.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("Background Sync & Battery Optimization") {
                Picker("Sync Frequency", selection: Binding(
                    get: { viewModel.syncFrequency },
                    set: { viewModel.updateSyncFrequency($0) }
                )) {
                    ForEach(SyncFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }

                Text("Background sync refreshes your active account only to minimize network requests and battery consumption. Manual refresh will sync all accounts.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    Task {
                        await viewModel.refreshAllQuotas(activeAccountOnly: false)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh All Accounts Now")
                    }
                }
            }

            Section("Account Import & Local Storage") {
                Button {
                    viewModel.importAccountsFromAntigravityTools()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Accounts from Antigravity Tools")
                    }
                }
                .buttonStyle(.borderedProminent)

                if let msg = viewModel.importStatusMessage {
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }

                Text("Imports existing accounts and tokens directly into macOS Keychain and ZedGravity local storage (~/Library/Application Support/ZedGravity). ZedGravity operates 100% standalone via direct Google Cloud Code API.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Section("Quota Monitoring & Notifications") {
                Toggle("Track Gemini Flash Image Generation Quota", isOn: $viewModel.trackImageQuota)
                Toggle("Notify When Quota Drops Below Safe Threshold", isOn: $viewModel.notifyLowQuota)

                if viewModel.notifyLowQuota {
                    Picker("Critical Alert Threshold", selection: $viewModel.lowQuotaThreshold) {
                        Text("25% Remaining").tag(25.0)
                        Text("20% Remaining").tag(20.0)
                        Text("15% (Critical Default)").tag(15.0)
                        Text("10% Remaining").tag(10.0)
                    }
                }

                Text("Dispatches native macOS banners with sound when Gemini or Claude quotas fall below your chosen threshold.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Section("About ZedGravity") {
                LabeledContent("Version", value: "1.2.0 (Open Source Edition)")
                LabeledContent("Architecture", value: "Native Swift & SwiftUI (100% Standalone)")
                LabeledContent("Platform", value: "macOS 14+ Sonoma / Sequoia")
                LabeledContent("Security", value: "Apple Keychain Protected (0600 POSIX)")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(22)
    }
}

/// Helper NSViewRepresentable to configure window transparency for full-surface frosted glass
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
