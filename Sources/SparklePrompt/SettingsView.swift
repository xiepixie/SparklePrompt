import SwiftUI
import AppKit

/// In-app settings overlay for configuring AI provider, model, and API key.
struct SettingsOverlay: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            // Scrim: Respect presentationStyle for premium opacity and stealthiness
            viewModel.presentationStyle.backgroundColor
                .opacity(max(0.7, viewModel.bgOpacity * viewModel.presentationStyle.panelOpacityMultiplier))
                .ignoresSafeArea()
                .onTapGesture { viewModel.showSettings = false }

            HStack(spacing: 0) {
                // Left Sidebar Pane
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(viewModel.presentationStyle.accentColor.opacity(0.15)).frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .foregroundColor(viewModel.presentationStyle.accentColor)
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text("Sparkle 配置")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                    Divider().background(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))

                    // Navigation Tab Buttons
                    ScrollView {
                        VStack(spacing: 6) {
                            sidebarTabButton(title: "模型厂商", icon: "server.rack", index: 0)
                            sidebarTabButton(title: "角色库", icon: "person.text.rectangle", index: 1)
                            sidebarTabButton(title: "上下文", icon: "brain.head.profile", index: 2)
                            sidebarTabButton(title: "热键配置", icon: "keyboard", index: 3)
                            sidebarTabButton(title: "外观呈现", icon: "paintpalette", index: 4)
                            sidebarTabButton(title: "隐私安全", icon: "shield.fill", index: 5)
                            sidebarTabButton(title: "高级设置", icon: "gearshape.2", index: 6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                    }

                    Spacer()

                    Divider().background(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.activeStatusColor.opacity(viewModel.presentationStyle.textOpacityMultiplier))
                            .frame(width: 6, height: 6)
                        Text(viewModel.activeStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .frame(width: 160)
                .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.02))

                // Vertical Divider Line
                Rectangle()
                    .fill(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))
                    .frame(width: 1)

                // Right Content Pane
                VStack(alignment: .leading, spacing: 0) {
                    // Close button row (discreetly placed)
                    HStack {
                        Spacer()
                        Button(action: { viewModel.showSettings = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(viewModel.presentationStyle.secondaryTextColor.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Content Area
                    ZStack {
                        switch selectedTab {
                        case 0: AIProvidersTab(viewModel: viewModel)
                        case 1: AIRolesTab(viewModel: viewModel)
                        case 2: AIContextTab(viewModel: viewModel)
                        case 3: HotkeysSettingsTab(viewModel: viewModel)
                        case 4: AppearanceSettingsTab(viewModel: viewModel)
                        case 5: PrivacySettingsTab(viewModel: viewModel)
                        case 6: AdvancedSettingsTab(viewModel: viewModel)
                        default: EmptyView()
                        }
                    }
                    .frame(height: 440)

                    Divider().background(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.dividerOpacity))

                    // Footer actions
                    HStack {
                        if selectedTab == 3 {
                            Button("恢复默认快捷键") {
                                viewModel.resetShortcutsToDefault()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        if viewModel.showSaveStatus {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(viewModel.isPrivacyMode ? viewModel.presentationStyle.accentColor : .green)
                                    .font(.system(size: 12))
                                Text("已保存")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(viewModel.isPrivacyMode ? viewModel.presentationStyle.secondaryTextColor : .green)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.trailing, 8)
                        }

                        Button("完成并保存") {
                            viewModel.saveShortcuts()
                            Task { await viewModel.saveAISettings() }
                            viewModel.notifySaveSuccess()

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                viewModel.showSettings = false
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.presentationStyle.accentColor)
                        .controlSize(.regular)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .frame(width: 520)
                .background(viewModel.presentationStyle.backgroundColor.opacity(0.12))
            }
            .contentShape(Rectangle())
            .frame(width: 681, height: 540)
            .background {
                ZStack {
                    viewModel.presentationStyle.backgroundColor.opacity(viewModel.bgOpacity)
                    if !viewModel.isPrivacyMode {
                        Rectangle().fill(.ultraThinMaterial)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.presentationStyle.panelBorderOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(viewModel.presentationStyle.shadowOpacity * 0.5), radius: viewModel.presentationStyle.shadowRadius * 10, x: 0, y: viewModel.presentationStyle.shadowYOffset * 15)
            .onDisappear {
                viewModel.saveShortcuts()
                Task { await viewModel.saveAISettings() }
            }
        }
    }

    private func sidebarTabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                    .foregroundColor(selectedTab == index ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13, weight: selectedTab == index ? .semibold : .medium))
                    .foregroundColor(selectedTab == index ? viewModel.presentationStyle.secondaryTextColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.65))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if selectedTab == index {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(viewModel.presentationStyle.accentColor.opacity(0.12))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 1. AI Providers Tab
private struct AIProvidersTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Failover Settings
                SettingsSection(title: "故障转移设置", icon: "arrow.triangle.2.circlepath", style: viewModel.presentationStyle) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("启用故障转移")
                                    .font(.system(size: 14, weight: .medium))
                                Text("当主要提供商失败时，自动尝试备用提供商")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.enableFailover)
                                .toggleStyle(.switch)
                                .tint(viewModel.presentationStyle.accentColor)
                        }

                        if viewModel.enableFailover {
                            Divider().opacity(0.08)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("提供商优先级（拖拽调整顺序）")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))

                                ForEach(Array(viewModel.providerPriority.enumerated()), id: \.offset) { index, provider in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                                            .frame(width: 24)

                                        Text(provider.rawValue)
                                            .font(.system(size: 13))
                                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))

                                        Spacer()

                                        HStack(spacing: 10) {
                                            Button(action: {
                                                withAnimation {
                                                    viewModel.providerPriority.swapAt(index, index - 1)
                                                }
                                            }) {
                                                Image(systemName: "chevron.up")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(index > 0 ? viewModel.presentationStyle.secondaryTextColor.opacity(0.4) : viewModel.presentationStyle.secondaryTextColor.opacity(0.15))
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == 0)

                                            Button(action: {
                                                withAnimation {
                                                    viewModel.providerPriority.swapAt(index, index + 1)
                                                }
                                            }) {
                                                Image(systemName: "chevron.down")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(index < viewModel.providerPriority.count - 1 ? viewModel.presentationStyle.secondaryTextColor.opacity(0.4) : viewModel.presentationStyle.secondaryTextColor.opacity(0.15))
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(index == viewModel.providerPriority.count - 1)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }

                // Provider Cards
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    ProviderCard(viewModel: viewModel, provider: provider)
                }
            }
            .padding(20)
        }
    }
}

private struct ProviderCard: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    let provider: AIProvider

    @State private var isExpanded: Bool = false

    var isSelected: Bool { viewModel.aiProvider == provider }

    private var urlBinding: Binding<String> {
        Binding(
            get: { viewModel.getBaseURL(for: provider) },
            set: { viewModel.setBaseURL($0, for: provider) }
        )
    }

    private var keyBinding: Binding<String> {
        Binding(
            get: { viewModel.getAPIKey(for: provider) },
            set: { viewModel.setAPIKey($0, for: provider) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { viewModel.getModel(for: provider) },
            set: { viewModel.setModel($0, for: provider) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row (Clickable to expand)
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(provider.rawValue)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(viewModel.presentationStyle.secondaryTextColor)

                            if isSelected {
                                Text("当前默认")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(viewModel.presentationStyle.accentColor.opacity(0.3))
                                    .foregroundColor(viewModel.presentationStyle.accentColor)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(viewModel.getProviderStatus(provider))
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.getProviderStatusColor(provider).opacity(viewModel.presentationStyle.textOpacityMultiplier))
                    }

                    Spacer()

                    if !isSelected {
                        Button("设为默认") {
                            viewModel.aiProvider = provider
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded = true
                            }
                        }
                        .font(.system(size: 12, weight: .bold))
                        .buttonStyle(.plain)
                        .foregroundColor(viewModel.presentationStyle.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.presentationStyle.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.1)

                VStack(spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Label("Base URL", systemImage: "link")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                            .frame(width: 80, alignment: .leading)
                        TextField("例如: https://api.openai.com", text: urlBinding)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Label("API Key", systemImage: "key.fill")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                            .frame(width: 80, alignment: .leading)
                        SecureField(keyBinding.wrappedValue.isEmpty ? "输入 API Key (本地协议可留空)" : "Keychain 中已加密存储", text: keyBinding)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Label("当前模型", systemImage: "cpu")
                            .font(.system(size: 12))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                            .frame(width: 80, alignment: .leading)
                        ModelSelectionRow(
                            viewModel: viewModel,
                            models: viewModel.getAvailableModels(for: provider),
                            modelBinding: modelBinding
                        )
                    }

                    if provider == .deepseek || provider == .openAICompatible {
                        HStack(alignment: .center, spacing: 12) {
                            Label("深度思考", systemImage: "brain")
                                .font(.system(size: 12))
                                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Toggle("", isOn: $viewModel.enableDeepSeekThinking)
                                .toggleStyle(.switch)
                                .tint(viewModel.presentationStyle.accentColor)
                                .labelsHidden()
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Button(action: {
                            if !isSelected { viewModel.aiProvider = provider }
                            viewModel.fetchModels()
                        }) {
                            HStack(spacing: 6) {
                                if isSelected && viewModel.isTestingAPI {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("测试并刷新模型")
                                }
                            }
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.presentationStyle.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundColor(viewModel.presentationStyle.accentColor)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if let status = viewModel.apiTestStatus, isSelected {
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(status.contains("成功") ? .green.opacity(viewModel.presentationStyle.textOpacityMultiplier) : .orange.opacity(viewModel.presentationStyle.textOpacityMultiplier))
                        }
                    }
                }
                .padding(16)
                .background(viewModel.presentationStyle.backgroundColor.opacity(0.2))
            }
        }
        .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? viewModel.presentationStyle.accentColor.opacity(0.5) : viewModel.presentationStyle.secondaryTextColor.opacity(0.1), lineWidth: 1))
        .onAppear {
            if isSelected { isExpanded = true }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded = true
                }
            }
        }
    }
}

// MARK: - Subcomponents
private struct ModelSelectionRow: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    let models: [String]
    @Binding var modelBinding: String

    var body: some View {
        HStack(spacing: 0) {
            TextField("手动输入模型名称", text: $modelBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .padding(6)
                .frame(maxWidth: .infinity)

            if !models.isEmpty {
                Divider().frame(height: 14).opacity(0.3)
                Menu {
                    ForEach(models, id: \.self) { model in
                        Button(viewModel.cleanModelName(model)) { modelBinding = model }
                    }
                } label: {
                    Color.clear
                        .frame(width: 30)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - 2. AI Roles Tab
private struct AIRolesTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("角色库管理", systemImage: "person.text.rectangle")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button(action: {
                        let newRole = AIRole(name: "新角色", prompt: "")
                        viewModel.aiRoles.append(newRole)
                        viewModel.selectedRoleIndex = viewModel.aiRoles.count - 1
                    }) {
                        Label("新增角色", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(viewModel.presentationStyle.accentColor)
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<viewModel.aiRoles.count, id: \.self) { index in
                            Button(action: { viewModel.selectedRoleIndex = index }) {
                                Text(viewModel.aiRoles[index].name)
                                    .font(.system(size: 12, weight: viewModel.selectedRoleIndex == index ? .bold : .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.selectedRoleIndex == index ? viewModel.presentationStyle.accentColor.opacity(0.3) : viewModel.presentationStyle.secondaryTextColor.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if viewModel.aiRoles.indices.contains(viewModel.selectedRoleIndex) {
                    RoleEditorView(
                        role: viewModel.aiRoles[viewModel.selectedRoleIndex],
                        onUpdate: { updatedRole in
                            viewModel.aiRoles[viewModel.selectedRoleIndex] = updatedRole
                        },
                        viewModel: viewModel
                    )
                }
            }
            .padding(20)
        }
    }
}

// MARK: - 3. AI Context Tab
private struct AIContextTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel
    @FocusState private var isStyleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsSection(title: "背景资料控制", icon: "doc.text", style: viewModel.presentationStyle) {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("使用背景资料")
                                    .font(.system(size: 14, weight: .medium))
                                Text("关闭后 AI 将不读取任何文档内容，仅根据你的问题回答")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.useAnyContextForAI)
                                .toggleStyle(.switch)
                                .tint(viewModel.presentationStyle.accentColor)
                        }

                        if viewModel.useAnyContextForAI {
                            Divider().opacity(0.08)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("将整个文件夹内容作为背景")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("AI 将读取同一工作区内的所有剧本。消耗更多 Token，但理解力更强。")
                                        .font(.system(size: 11))
                                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                                }
                                Spacer()
                                Toggle("", isOn: $viewModel.useWorkspaceContextForAI)
                                    .toggleStyle(.switch)
                                    .tint(viewModel.presentationStyle.accentColor)
                            }
                        }
                    }
                }

                SettingsSection(title: "全局个人风格记忆", icon: "text.bubble", style: viewModel.presentationStyle) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("此内容作为固定前缀。适合录入：演讲风格、常用缩写等。")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))

                        TextEditor(text: $viewModel.aiPersonalStyle)
                            .font(.system(size: 13))
                            .focused($isStyleFocused)
                            .frame(height: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(viewModel.presentationStyle.backgroundColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isStyleFocused ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 3. Hotkeys Settings Tab
private struct HotkeysSettingsTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "快捷键配置", icon: "keyboard", style: viewModel.presentationStyle) {
                    VStack(spacing: 12) {
                        ForEach(ShortcutAction.allCases, id: \.self) { action in
                            HStack {
                                Text(action.rawValue)
                                    .font(.system(size: 13))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                                Spacer()
                                ShortcutRecorderView(action: action, viewModel: viewModel)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 4. Appearance Tab
private struct AppearanceSettingsTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "视觉呈现", icon: "textformat", style: viewModel.presentationStyle) {
                    VStack(spacing: 14) {
                        colorRow(title: "字体颜色", subtitle: "普通模式主文字颜色", selection: $viewModel.textColor)
                        colorRow(title: "播放线颜色", subtitle: "阅读辅助线颜色", selection: $viewModel.readingLineColor)
                        colorRow(title: "主题强调色", subtitle: "按钮、滑块与高亮状态", selection: $viewModel.accentColor)

                        Divider().opacity(0.08)

                        sliderRow(title: "字体大小", subtitle: "普通与隐私模式共用字号", value: $viewModel.fontSize, range: 16...140, suffix: "pt")
                        sliderRow(title: "行间距", subtitle: "控制长文本的呼吸感", value: $viewModel.lineSpacing, range: 0...60, suffix: "pt")
                        sliderRow(title: "文字透明度", subtitle: "整体文字可见度", value: $viewModel.textOpacity, range: 0.1...1.0, suffix: "%")
                        sliderRow(title: "背景透明度", subtitle: "主面板背景遮罩强度", value: $viewModel.bgOpacity, range: 0...1.0, suffix: "%")

                        Divider().opacity(0.1)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("代码模式 (Code Mode)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                                Text("强制以等宽字体与左对齐排版渲染，优化代码演示")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.isCodeMode)
                                .toggleStyle(.switch)
                                .tint(viewModel.presentationStyle.accentColor)
                                .labelsHidden()
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - 5. Privacy Tab
private struct PrivacySettingsTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SettingsSection(title: "隐私与隐身", icon: "shield.fill", style: viewModel.presentationStyle) {
                    VStack(spacing: 16) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("隐私防护 (Privacy Mode)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                                Text("隐藏 Dock 图标并启用录屏抓取防护")
                                    .font(.system(size: 11)).foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            }
                            Spacer()
                            Button(action: { viewModel.togglePrivacy() }) {
                                Capsule()
                                    .fill(viewModel.isPrivacyMode ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.14))
                                    .frame(width: 42, height: 24)
                                    .overlay(alignment: viewModel.isPrivacyMode ? .trailing : .leading) {
                                        Circle()
                                            .fill(viewModel.presentationStyle.secondaryTextColor.opacity(viewModel.isPrivacyMode ? 0.9 : 0.5))
                                            .frame(width: 18, height: 18)
                                            .padding(.horizontal, 3)
                                    }
                            }
                            .buttonStyle(.plain)
                        }

                        if viewModel.isPrivacyMode {
                            privacySliderRow(title: "防窥模糊", subtitle: "统一作用于主文本、剧本库与浮层控件", value: $viewModel.privacyBlurRadius, range: 0...3.0, suffix: "pt")

                            Divider().opacity(0.05)
                        }

                        Divider().opacity(0.05)

                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("鼠标穿透 (Ghost Mode)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.82))
                                Text(viewModel.mousePenetration ? "幽灵模式已锁定 - 倒计时结束释放" : "鼠标直接穿过提词器，操作背后窗口")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.mousePenetration ? .orange.opacity(viewModel.presentationStyle.textOpacityMultiplier) : viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
                            }
                            Spacer()

                            if viewModel.isGhostModePending {
                                Button(action: { viewModel.cancelGhostPrep() }) {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("\(viewModel.ghostModeCountdown)s 后锁定")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundColor(.orange.opacity(viewModel.presentationStyle.textOpacityMultiplier))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.12 * viewModel.presentationStyle.textOpacityMultiplier), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            } else if viewModel.mousePenetration {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 11))
                                    Text("\(viewModel.ghostModeTimeRemaining)s 后恢复")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundColor(.orange.opacity(viewModel.presentationStyle.textOpacityMultiplier))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.12 * viewModel.presentationStyle.textOpacityMultiplier), in: Capsule())
                            } else {
                                Button(action: { viewModel.requestGhostMode() }) {
                                    Text("启动锁定会话")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(viewModel.presentationStyle.accentColor, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func privacySliderRow(title: String, subtitle: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, suffix: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.82))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
            }
            Spacer()
            Slider(value: value, in: range, step: 0.1)
                .frame(width: 145)
                .tint(viewModel.presentationStyle.accentColor)
            Text(String(format: "%.1f %@", Double(value.wrappedValue), suffix))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Helper Functions for AppearanceSettingsTab
private extension AppearanceSettingsTab {
    func colorRow(title: String, subtitle: String, selection: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                // Left column: Title and Subtitle with flexible space
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
                }

                Spacer()

                // Right column: Current selection circle + hex value text field
                HStack(spacing: 8) {
                    // Current color dot
                    ZStack {
                        Circle()
                            .fill(selection.wrappedValue)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.3), lineWidth: 1.5))
                            .shadow(color: .black.opacity(0.25), radius: 2)
                    }
                    .contentShape(Circle())
                    .onTapGesture {
                        if let hex = NSColor(selection.wrappedValue).toHex() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(hex, forType: .string)
                        }
                    }
                    .help("点击复制颜色代码")

                    // Hex Text Field
                    TextField("#FFFFFF", text: Binding(
                        get: { NSColor(selection.wrappedValue).toHex() ?? "#FFFFFF" },
                        set: { selection.wrappedValue = Color(NSColor(hex: $0) ?? NSColor.white) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 85, height: 26)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.12), lineWidth: 1))
                }
            }

            // Row 2: Preset Recommendation Palette
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 9))
                    Text("推荐色板")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))

                Spacer()

                HStack(spacing: 6) {
                    ForEach(presetColors(for: selection.wrappedValue), id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.2), lineWidth: 1)
                            )
                            .overlay(
                                Circle()
                                    .stroke(compareColors(selection.wrappedValue, color) ? viewModel.presentationStyle.secondaryTextColor.opacity(0.9) : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.15), radius: 1)
                            .contentShape(Circle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                                    selection.wrappedValue = color
                                }
                            }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    // Helper to robustly check if colors are identical using hex representations
    private func compareColors(_ c1: Color, _ c2: Color) -> Bool {
        let h1 = NSColor(c1).toHex() ?? ""
        let h2 = NSColor(c2).toHex() ?? ""
        return !h1.isEmpty && h1.lowercased() == h2.lowercased()
    }

    // Generate preset color palette without duplicates to prevent SwiftUI ForEach crashes
    private func presetColors(for current: Color) -> [Color] {
        let baseColors: [Color] = [
            .white,
            .red,
            .orange,
            .yellow,
            .green,
            .blue,
            .purple,
            .pink,
            .cyan
        ]

        if baseColors.contains(where: { compareColors($0, current) }) {
            return baseColors
        } else {
            return baseColors + [current]
        }
    }

    private func sliderRow(title: String, subtitle: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.82))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
            }
            Spacer()
            Slider(value: value, in: range)
                .frame(width: 145)
                .tint(viewModel.presentationStyle.accentColor)
            Text(formattedValue(value.wrappedValue, suffix: suffix))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func sliderRow(title: String, subtitle: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, suffix: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.82))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.42))
            }
            Spacer()
            Slider(value: value, in: range, step: 0.1)
                .frame(width: 145)
                .tint(viewModel.presentationStyle.accentColor)
            Text(String(format: "%.1f %@", Double(value.wrappedValue), suffix))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.6))
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func formattedValue(_ value: Double, suffix: String) -> String {
        if suffix == "%" {
            return "\(Int(value * 100))%"
        }
        return "\(Int(value)) \(suffix)"
    }
}

// MARK: - 5. Advanced Settings Tab
private struct AdvancedSettingsTab: View {
    @ObservedObject var viewModel: SparklePromptViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "AI 智播高级设置", icon: "sparkles.square.filled.on.square", style: viewModel.presentationStyle) {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("自动追随滚动")
                                    .font(.system(size: 14, weight: .medium))
                                Text("AI 输出时视图自动向下滚动。")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.autoFollowEnabled)
                                .toggleStyle(.switch)
                                .tint(viewModel.presentationStyle.accentColor)
                        }
                    }
                }

                SettingsSection(title: "数据与初始化", icon: "internaldrive", style: viewModel.presentationStyle) {
                    VStack(spacing: 0) {
                        settingActionRow(title: "在 Finder 中显示配置目录", icon: "folder.fill") {
                            viewModel.showConfigFileInFinder()
                        }

                        Divider().padding(.leading, 12).opacity(0.1)

                        settingActionRow(title: "重置应用 (数据初始化)", icon: "arrow.counterclockwise", isDestructive: true) {
                            viewModel.resetAllSettings()
                        }
                    }
                }

                // App Info
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 40))
                        .foregroundColor(viewModel.presentationStyle.accentColor)
                    Text("SparklePrompt")
                        .font(.title3.bold())
                    Text("专业级 AI 透明提词器")
                        .font(.subheadline)
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.4))
                }
                .padding(.top, 40)
            }
            .padding(20)
        }
    }

    private func settingActionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(isDestructive ? .red.opacity(viewModel.presentationStyle.textOpacityMultiplier) : viewModel.presentationStyle.secondaryTextColor.opacity(0.5))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(isDestructive ? .red.opacity(viewModel.presentationStyle.textOpacityMultiplier) : viewModel.presentationStyle.secondaryTextColor.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.2))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Components

/// A standard section container for settings groups.
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let style: PromptPresentationStyle
    let content: Content

    init(title: String, icon: String, style: PromptPresentationStyle, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(style.secondaryTextColor.opacity(0.5))

            content
                .padding(12)
                .background(style.secondaryTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(style.secondaryTextColor.opacity(0.1), lineWidth: 1))
        }
    }
}

struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @ObservedObject var viewModel: SparklePromptViewModel
    @State private var isRecording = false
    @State private var monitor: Any?

    var shortcut: Shortcut? {
        viewModel.shortcuts[action]
    }

    var body: some View {
        Button(action: {
            if isRecording { stopRecording() }
            else { startRecording() }
        }) {
            if isRecording {
                Text("请按键…")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red.opacity(viewModel.presentationStyle.textOpacityMultiplier))
                    .frame(minWidth: 85)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.2 * viewModel.presentationStyle.textOpacityMultiplier), in: RoundedRectangle(cornerRadius: 6))
            } else if let shortcut = shortcut {
                HStack(spacing: 4) {
                    ForEach(shortcut.keySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.1), lineWidth: 1))
                    }

                    Text(shortcut.key.uppercased() == " " ? "SPACE" : shortcut.key.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(viewModel.presentationStyle.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(viewModel.presentationStyle.accentColor.opacity(0.3), lineWidth: 1))
                        .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                }
            } else {
                Text("未设置")
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.3))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    func startRecording() {
        isRecording = true
        NSApp.keyWindow?.makeFirstResponder(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { stopRecording(); return nil }
            if event.keyCode == 51 { viewModel.shortcuts[action] = nil; stopRecording(); return nil }
            let chars = event.charactersIgnoringModifiers ?? ""
            guard !chars.isEmpty else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control]).rawValue
            viewModel.shortcuts[action] = Shortcut(key: chars.lowercased(), keyCode: event.keyCode, modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Helpers

struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0, currentY: CGFloat = 0, lineHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0; currentY += lineHeight + spacing; lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX, currentY: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX; currentY += lineHeight + spacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Role Editor Component
private struct RoleEditorView: View {
    let role: AIRole
    var onUpdate: (AIRole) -> Void
    @ObservedObject var viewModel: SparklePromptViewModel

    @State private var localName: String = ""
    @State private var localPrompt: String = ""
    @FocusState private var isNameFocused: Bool
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            TextField("角色名称", text: $localName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor)
                .focused($isNameFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(viewModel.presentationStyle.backgroundColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isNameFocused ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.08), lineWidth: 1)
                )
                .onChange(of: localName) { _, _ in updateParent() }

            TextEditor(text: $localPrompt)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .foregroundColor(viewModel.presentationStyle.secondaryTextColor.opacity(0.9))
                .focused($isPromptFocused)
                .frame(height: 100)
                .padding(8)
                .background(viewModel.presentationStyle.backgroundColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isPromptFocused ? viewModel.presentationStyle.accentColor : viewModel.presentationStyle.secondaryTextColor.opacity(0.08), lineWidth: 1)
                )
                .onChange(of: localPrompt) { _, _ in updateParent() }
        }
        .padding(12)
        .background(viewModel.presentationStyle.secondaryTextColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.presentationStyle.secondaryTextColor.opacity(0.1), lineWidth: 1))
        .onAppear { localName = role.name; localPrompt = role.prompt }
        .onChange(of: role.id) { _, _ in localName = role.name; localPrompt = role.prompt }
    }
    private func updateParent() {
        var updated = role; updated.name = localName; updated.prompt = localPrompt
        onUpdate(updated)
    }
}
