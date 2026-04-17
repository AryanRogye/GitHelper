//
//  GitDiffSidebar.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

/*
 * Sidebar:
 *
 * ContentView sidebar List
 * +-- SidebarSearchField
 * +-- SidebarSectionHeader
 * +-- row.sidebarSelectableRow(isSelected:)
 * +-- SidebarSelectableRowModifier
 */

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
                searchBarView
            }

            Section {
                if filteredLibrary.isEmpty {
                    repositoriesEmtpy
                } else {
                    ForEach(filteredLibrary) { entry in
                        Button {
                            Task {
                                await model.loadLibraryRepository(id: entry.id)
                            }
                        } label: {
                            sidebarRepoCard(entry)
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
                                    displayedSessionCard(
                                        selectedEntry: selectedEntry,
                                        session: session
                                    )
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
    
    // MARK: - Search Bar View
    private var searchBarView: some View {
        SidebarSearchField(text: $librarySearchText)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
    
    // MARK: - Repositories Empty
    private var repositoriesEmtpy: some View {
        Text(model.library.isEmpty ? "No repositories saved yet." : "No repositories match your search.")
            .foregroundStyle(NativeTheme.readableSecondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
    
    // MARK: - Sidebar Repo Card
    private func sidebarRepoCard(_ entry: RepoLibraryEntry) -> some View {
        HStack(alignment: .center) {
            Image(systemName: entry.status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, alignment: .leading)
                .foregroundStyle(entry.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NativeTheme.fileListPrimary)
                HStack(spacing: 6) {
                    Text(entry.status.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(entry.status.color)
                    Text("• \(entry.friendlyRefName) • \(entry.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(NativeTheme.readableSecondary)
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarSelectableRow(isSelected: model.selectedLibraryRepoID == entry.id)
    }
    
    // MARK: - Displayed Session Card
    private func displayedSessionCard(selectedEntry: RepoLibraryEntry, session: RepoSessionEntry) -> some View {
        Button {
            Task {
                await model.loadLibrarySession(repoID: selectedEntry.id, sessionID: session.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.friendlyCompareLabel)
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
