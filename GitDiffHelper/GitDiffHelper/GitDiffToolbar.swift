//
//  GitDiffToolbar.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI
import AppKit

struct GitDiffToolbar: ToolbarContent {
    
    @EnvironmentObject private var model: DiffViewModel
    @Binding var showAdvancedInspector: Bool
    @Binding var selectedScreen: WorkbenchScreen
    @Binding var selectedTwoCommitBaseID: String?
    var onChooseRepositoryFolder: () -> Void
    
    private var logBranchMenuOptions: [String] {
        var refs = [DiffViewModel.allBranchesFilterLabel]
        refs.append(contentsOf: model.availableBranchRefs)
        var seen = Set<String>()
        return refs.filter { seen.insert($0).inserted }
    }
    
    private var selectedTwoCommitBase: GitLogEntry? {
        guard let selectedTwoCommitBaseID else {
            return nil
        }
        return model.recentBranchCommits.first(where: { $0.id == selectedTwoCommitBaseID })
    }
    
    private var selectedTwoCommitHeads: [GitLogEntry] {
        guard let selectedTwoCommitBase else {
            return []
        }
        return model.recentBranchCommits.filter { $0.id != selectedTwoCommitBase.id }
    }
    
    private var logBranchFilterLabel: String {
        let selected = model.selectedLogBranchFilter
        if selected == DiffViewModel.allBranchesFilterLabel {
            return selected
        }
        return friendlyRefName(selected)
    }
    
    var body: some ToolbarContent {
        screenPicker
        
        chooseRepoButton
        
        if selectedScreen == .diff {
            diffToolbarContent
        } else {
            ToolbarItemGroup(placement: .automatic) {
                filterBranchesMenu
                refreshLogsButton
            }
        }
    }
}

// MARK: - Helpers
extension GitDiffToolbar {
    
    // MARK: - Screen Picker
    private var screenPicker: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Screen", selection: $selectedScreen) {
                Label("Diff", systemImage: "rectangle.split.2x1").tag(WorkbenchScreen.diff)
                Label("Commit Log", systemImage: "clock.arrow.circlepath").tag(WorkbenchScreen.log)
                Label("Commit Tree", systemImage: "arrow.triangle.branch").tag(WorkbenchScreen.tree)
            }
            .pickerStyle(.segmented)
            .help("Switch between diff view, commit history, and commit tree.")
        }
    }
    
    // MARK: - Choose Repo Button
    private var chooseRepoButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onChooseRepositoryFolder) {
                ToolbarSymbolLabel("Choose Repository", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.accentColor)
            .help("Pick a folder that contains your .git repository")
            .accessibilityLabel("Choose Repository")
            .accessibilityHint("Opens a folder picker so you can select the Git repository to inspect.")
        }
    }
}

// MARK: - Diff Toolbar Content
extension GitDiffToolbar {
    private var diffToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            ControlGroup {
                reloadWorkingChangesButton
                
                loadLastCommitButton
                
                compareBranchesMenu
                
                compareCommitsMenu
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.accentColor)
            .disabled(model.repoPath.isEmpty)
            
            Button {
                showAdvancedInspector.toggle()
            } label: {
                ToolbarSymbolLabel("Custom Compare", systemImage: showAdvancedInspector ? "sidebar.trailing" : "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.accentColor)
            .disabled(model.repoPath.isEmpty)
            .help("Open advanced options for custom comparisons and path filters.")
            .accessibilityLabel("Advanced Compare")
            .accessibilityHint("Opens options to compare specific commits or branches and filter to a file or folder path.")
        }
    }
    
    
    private var reloadWorkingChangesButton: some View {
        Button {
            Task {
                await model.loadUncommittedChanges()
            }
        } label: {
            Image(systemName: "arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 16, height: 16, alignment: .center)
//            ToolbarSymbolLabel("Reload", systemImage: "arrow.circlepath")
        }
        .help("Show files changed in your working folder that are not committed yet.")
        .accessibilityLabel("Show Working Changes")
        .accessibilityHint("Loads differences between the files you are editing and your latest saved commit.")
    }
    
    private var loadLastCommitButton: some View {
        Button {
            Task {
                await model.loadLastCommit()
            }
        } label: {
            ToolbarSymbolLabel("Last Commit", systemImage: "clock")
        }
        .help("Compare the latest commit with the one right before it.")
        .accessibilityLabel("Compare Recent Commit")
        .accessibilityHint("Shows what changed in the most recently created commit.")
    }
    
    private var compareBranchesMenu: some View {
        Menu {
            if model.availableBranchRefs.filter({ $0 != "HEAD" }).isEmpty {
                Text("No branches found")
            } else {
                ForEach(model.availableBranchRefs.filter { $0 != "HEAD" }, id: \.self) { branch in
                    Button(branch) {
                        Task {
                            await model.compareAgainstBranch(branch)
                        }
                    }
                }
            }
        } label: {
            ToolbarSymbolLabel("Compare Branch", systemImage: "arrow.triangle.branch")
        }
        .help("Compare your current work with another branch.")
        .accessibilityLabel("Compare to Branch")
        .accessibilityHint("Opens a menu of branches so you can compare against one.")
    }
    
    private var compareCommitsMenu: some View {
        Menu {
            if model.repoPath.isEmpty {
                Text("Choose a repository first")
            } else if model.isLoadingRecentBranchCommits {
                Text("Loading commits...")
            } else if model.recentBranchCommits.isEmpty {
                Button("Load \(friendlyRefName(model.currentBranchRef)) commits") {
                    Task {
                        await model.loadRecentBranchCommits(force: true)
                    }
                }
            } else {
                compareCommitMenuLoadedContent
            }
        } label: {
            ToolbarSymbolLabel("Compare Commit", systemImage: "clock.badge.checkmark")
        }
        .help("Compare a past commit on the current branch against your current working state.")
        .accessibilityLabel("Compare to Past Commit")
        .accessibilityHint("Choose a commit from the current branch and compare it to what you have now.")
    }
    
    @ViewBuilder
    private var compareCommitMenuLoadedContent: some View {
        Section("Compare to Current State") {
            Text("Target: current working state (HEAD + staged + unstaged)")
            ForEach(model.recentBranchCommits, id: \.id) { entry in
                Button(compareCommitLabel(for: entry)) {
                    Task {
                        await model.compareAgainstCommit(entry.id)
                    }
                }
            }
        }
        
        Divider()
        
        Section("Compare Two Commits") {
            if let selectedBase = selectedTwoCommitBase {
                Text("Base: \(selectedBase.shortHash)")
                Button("Clear base selection") {
                    selectedTwoCommitBaseID = nil
                }
                Divider()
                ForEach(selectedTwoCommitHeads, id: \.id) { head in
                    Button(twoCommitCompareLabel(base: selectedBase, head: head)) {
                        Task {
                            await model.compareBetweenCommits(baseHash: selectedBase.id, headHash: head.id)
                        }
                    }
                }
            } else {
                Text("Pick the first commit (base)")
                ForEach(model.recentBranchCommits, id: \.id) { entry in
                    Button("Set base: \(compareCommitLabel(for: entry))") {
                        selectedTwoCommitBaseID = entry.id
                    }
                }
            }
        }
        
        Divider()
        Button("Refresh commit list") {
            Task {
                await model.loadRecentBranchCommits(force: true)
            }
        }
    }
}

// MARK: - Other Screen Toolbar Content
extension GitDiffToolbar {
    private var filterBranchesMenu: some View {
        Menu {
            ForEach(logBranchMenuOptions, id: \.self) { ref in
                Button(friendlyRefName(ref)) {
                    Task {
                        await model.loadCommitLog(branchFilter: ref)
                    }
                }
            }
        } label: {
            ToolbarSymbolLabel(logBranchFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color.accentColor)
        .disabled(model.repoPath.isEmpty || model.isLoadingLog)
        .help("Filter commit history and tree to one branch or show all branches.")
        .accessibilityLabel("Commit Log Branch Filter")
        .accessibilityHint("Select which branch history is visible in commit history screens.")
    }
    
    private var refreshLogsButton: some View {
        Button {
            Task {
                await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
            }
        } label: {
            ToolbarSymbolLabel("Refresh Log", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color.accentColor)
        .disabled(model.repoPath.isEmpty || model.isLoadingLog)
        .help("Reload commit history and tree from Git.")
        .accessibilityLabel("Refresh Commit History")
        .accessibilityHint("Refreshes commit history screens from Git with the current branch filter.")
    }
}

// MARK: - Helpers
extension GitDiffToolbar {
    private func friendlyRefName(_ ref: String) -> String {
        switch ref {
        case "HEAD":
            return "Current Commit"
        case "HEAD~1":
            return "Previous Commit"
        default:
            return ref
        }
    }
    
    private func compareCommitLabel(for entry: GitLogEntry) -> String {
        let subject = entry.subject.count > 64 ? "\(entry.subject.prefix(61))..." : entry.subject
        return "\(entry.shortHash)  \(subject)"
    }
    
    private func twoCommitCompareLabel(base: GitLogEntry, head: GitLogEntry) -> String {
        "\(base.shortHash) -> \(head.shortHash)  \(head.subject)"
    }
}
