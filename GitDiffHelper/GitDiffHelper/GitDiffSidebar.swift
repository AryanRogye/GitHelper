//
//  GitDiffSidebar.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

struct GitDiffSidebar: View {
    
    @EnvironmentObject private var model: DiffViewModel
    
    @State private var librarySearchText = ""
    @State private var showRecentComparisons = false

    private var filteredLibrary: [RepoLibraryEntry] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return model.library
        }
        return model.library.filter { entry in
            entry.displayName.localizedCaseInsensitiveContains(query) ||
            entry.lastBranch.localizedCaseInsensitiveContains(query) ||
            entry.selectedPath.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var selectedLibraryEntry: RepoLibraryEntry? {
        guard let selectedID = model.selectedLibraryRepoID else {
            return nil
        }
        return model.library.first(where: { $0.id == selectedID })
    }
    
    private var displayedSessions: [RepoSessionEntry] {
        guard let entry = selectedLibraryEntry else {
            return []
        }
        return Array(entry.sessions.prefix(14))
    }

    var body: some View {
        List {
            Section {
                SidebarSearchField(text: $librarySearchText)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            
            Section {
                if filteredLibrary.isEmpty {
                    Text(model.library.isEmpty ? "No repositories saved yet." : "No repositories match your search.")
                        .foregroundStyle(NativeTheme.readableSecondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredLibrary) { entry in
                        let status = libraryStatus(for: entry)
                        Button {
                            Task {
                                await model.loadLibraryRepository(id: entry.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: status.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 16, alignment: .leading)
                                    .foregroundStyle(status.color)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.displayName)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(NativeTheme.fileListPrimary)
                                    HStack(spacing: 6) {
                                        Text(status.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(status.color)
                                        Text("• \(friendlyRefName(entry.lastBranch)) • \(entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(NativeTheme.readableSecondary)
                                    }
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .sidebarSelectableRow(isSelected: model.selectedLibraryRepoID == entry.id)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button(role: .destructive) {
                                model.removeLibraryRepository(id: entry.id)
                            } label: {
                                Label("Remove from Library", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                SidebarSectionHeader("Repository Library")
            }
            
            if let selectedEntry = selectedLibraryEntry {
                Section {
                    DisclosureGroup(isExpanded: $showRecentComparisons) {
                        if displayedSessions.isEmpty {
                            Text("No sessions yet for this repository.")
                                .foregroundStyle(NativeTheme.readableSecondary)
                                .padding(.top, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(displayedSessions) { session in
                                    Button {
                                        Task {
                                            await model.loadLibrarySession(repoID: selectedEntry.id, sessionID: session.id)
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(friendlyCompareLabel(session.compareLabel))
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(NativeTheme.fileListPrimary)
                                            Text("\(session.fileCount) files • \(session.hunkCount) hunks • \(session.bridgeCount) bridges")
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundStyle(NativeTheme.readableSecondary)
                                            Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 10, weight: .regular))
                                                .foregroundStyle(NativeTheme.readableSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .sidebarSelectableRow(isSelected: model.selectedLibrarySessionID == session.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NativeTheme.readableSecondary)
                            Text("Recent Comparisons")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(NativeTheme.readableSecondary)
                        }
                    }
                    .tint(NativeTheme.readableSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
    
    private func libraryStatus(for entry: RepoLibraryEntry) -> LibraryStatus {
        guard let latestSession = entry.sessions.first else {
            return .init(title: "No History", color: NativeTheme.readableSecondary, symbol: "clock.badge.questionmark")
        }
        
        if latestSession.baseRef.isEmpty && latestSession.headRef.isEmpty {
            return .init(title: "Working", color: NativeTheme.readableSecondary, symbol: "square.and.pencil")
        }
        if latestSession.baseRef == "HEAD~1" && latestSession.headRef == "HEAD" {
            return .init(title: "Commit", color: NativeTheme.readableSecondary, symbol: "clock")
        }
        if latestSession.headRef == "HEAD", latestSession.baseRef != "HEAD~1", !latestSession.baseRef.isEmpty {
            return .init(title: "Branch", color: NativeTheme.readableSecondary, symbol: "arrow.triangle.branch")
        }
        return .init(title: "Custom", color: NativeTheme.readableSecondary, symbol: "slider.horizontal.3")
    }
    
    private func friendlyCompareLabel(_ label: String) -> String {
        if label == "Uncommitted" {
            return "Working Changes"
        }
        
        return label
            .replacingOccurrences(of: "HEAD~1", with: "Previous Commit")
            .replacingOccurrences(of: "HEAD", with: "Current Commit")
            .replacingOccurrences(of: "->", with: "→")
    }
    
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
}
