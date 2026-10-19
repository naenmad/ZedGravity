import SwiftUI

/// Pixel-refined macOS MenuBar popover conforming strictly to Apple HIG
public struct MenuBarView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView

            Divider()
                .opacity(0.12)

            // Content Area
            VStack(spacing: 9) {
                // Smart Advisor Compact Banner
                if let recommendation = viewModel.recommendation {
                    BudgetAdvisorCardView(recommendation: recommendation)
                }

                // Account Selector Capsule Bar
                if !viewModel.accounts.isEmpty {
                    accountSwitcherBar
                }

                // 2 Core Group Cards (Gemini vs Claude/GPT-OSS)
                quotaListView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .opacity(0.12)

            // Footer
            footerView
        }
        .frame(width: 345)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .sheet(isPresented: $viewModel.showingAddAccountSheet) {
            AddAccountSheet(viewModel: viewModel)
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 8) {
            Text("ZedGravity")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            // Open Full App Button (⌘O)
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Full Dashboard Window (⌘O)")
            .keyboardShortcut("o", modifiers: [.command])

            // Refresh Button (⌘R)
            Button {
                Task {
                    await viewModel.refreshAllQuotas(activeAccountOnly: false)
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh Quotas (⌘R)")
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.isLoading)

            // Add Account Button (⌘N)
            Button {
                viewModel.showingAddAccountSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add Account (⌘N)")
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var accountSwitcherBar: some View {
        HStack {
            Menu {
                Section("Switch Account (\(viewModel.enabledTargetsSummary))") {
                    ForEach(viewModel.accounts) { account in
                        let isFullyActive = viewModel.isAccountFullyActive(account)
                        let activeTargets = viewModel.activeTargetsForAccount(account)
                        Button {
                            Task {
                                await viewModel.switchUnifiedAccount(to: account.id)
                            }
                        } label: {
                            HStack {
                                Text(account.email.isEmpty ? account.name : account.email)
                                Text("(\(account.accountTier.displayName))")
                                if isFullyActive {
                                    Text("✓ Active")
                                } else if !activeTargets.isEmpty {
                                    Text("• Active in \(activeTargets.joined(separator: ", "))")
                                }
                            }
                        }
                    }
                }

                Menu("Switch Specific Target...") {
                    Section("Antigravity CLI / Ghostex Only") {
                        ForEach(viewModel.accounts) { account in
                            let isCLIActive = account.email.lowercased() == (viewModel.activeCLIEmail ?? "").lowercased()
                            Button {
                                Task {
                                    await viewModel.switchAntigravityCLI(to: account.id)
                                }
                            } label: {
                                HStack {
                                    Text(account.email.isEmpty ? account.name : account.email)
                                    if isCLIActive {
                                        Text("• Active")
                                    }
                                }
                            }
                        }
                    }

                    Section("Zed Editor ACP Only") {
                        ForEach(viewModel.accounts) { account in
                            let isZedActive = account.email.lowercased() == (viewModel.activeZedACPEmail ?? "").lowercased()
                            Button {
                                Task {
                                    await viewModel.switchZedACP(to: account.id)
                                }
                            } label: {
                                HStack {
                                    Text(account.email.isEmpty ? account.name : account.email)
                                    if isZedActive {
                                        Text("• Active")
                                    }
                                }
                            }
                        }
                    }

                    Section("Antigravity IDE Only") {
                        ForEach(viewModel.accounts) { account in
                            let isIDEActive = account.email.lowercased() == (viewModel.activeIDEAccountEmail ?? "").lowercased()
                            Button {
                                Task {
                                    await viewModel.switchAntigravityIDE(to: account.id)
                                }
                            } label: {
                                HStack {
                                    Text(account.email.isEmpty ? account.name : account.email)
                                    if isIDEActive {
                                        Text("• Active")
                                    }
                                }
                            }
                        }
                    }
                }

                if let selected = viewModel.selectedAccount {
                    Divider()
                    Button(role: .destructive) {
                        viewModel.deleteAccount(id: selected.id)
                    } label: {
                        Label("Remove This Account", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    let brand: BrandLogoKind = (viewModel.selectedAccount?.provider == .claude) ? .claude : .gemini
                    BrandLogoView(brand, size: 13)
                        .frame(width: 13, height: 13)
                        .fixedSize()

                    Text(viewModel.selectedAccount?.email.isEmpty ?? true ? (viewModel.selectedAccount?.name ?? "Account") : (viewModel.selectedAccount?.email ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let account = viewModel.selectedAccount {
                        let tier = account.accountTier
                        HStack(spacing: 2.5) {
                            if tier == .ultra {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 7))
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

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)

            Spacer()

            if viewModel.isSwitchingAccount || viewModel.isSwitchingZedACP || viewModel.isSwitchingIDE || viewModel.isSwitchingCLI {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 14, height: 14)
            } else if let msg = viewModel.unifiedSwitchStatusMessage {
                Text(msg)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(viewModel.isUnifiedSwitchSuccess ? .accentColor : .red)
                    .lineLimit(1)
            } else if let msg = viewModel.cliSwitchStatusMessage {
                Text(msg)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(viewModel.isCLISwitchSuccess ? .purple : .red)
                    .lineLimit(1)
            } else if let msg = viewModel.zedACPSwitchStatusMessage {
                Text(msg)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(viewModel.isZedACPSwitchSuccess ? .green : .red)
                    .lineLimit(1)
            } else {
                HStack(spacing: 5) {
                    if viewModel.activeCLIEmail != nil {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(viewModel.isGhostexOrCLIRunning ? Color.purple : Color.secondary)
                                .frame(width: 5, height: 5)
                            Text("CLI")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(viewModel.isGhostexOrCLIRunning ? .purple : .secondary)
                        }
                    }
                    if viewModel.activeZedACPEmail != nil {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(viewModel.isZedACPRunning ? Color.green : Color.secondary)
                                .frame(width: 5, height: 5)
                            Text("Zed")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(viewModel.isZedACPRunning ? .green : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var quotaListView: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.currentQuotaGroups) { group in
                QuotaGroupCardView(group: group, currentTime: viewModel.currentTime)
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button("Open Full Dashboard") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.accentColor)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
