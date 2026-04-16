//
//  DiffArea.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI
import AppKit

struct DiffArea: View {
    
    @EnvironmentObject private var model: DiffViewModel
    
    @Binding var selectedScreen: WorkbenchScreen
    @Binding var visibleFileCount : Int
    @Binding var focusedHunkID: UUID?
    
    @AppStorage("BridgeDiff.diffTextScale") private var storedDiffTextScale = 1.0
    
    private var visibleFiles: ArraySlice<DiffFile> {
        let maxVisible = min(visibleFileCount, model.files.count)
        return model.files.prefix(maxVisible)
    }
    
    private var diffTextScale: CGFloat {
        DiffTypography.clamp(CGFloat(storedDiffTextScale))
    }
    private var diffTypography: DiffTypography {
        DiffTypography(scale: diffTextScale)
    }
    
    private var activeFileID: UUID? {
        if let focusedHunkID,
           let focusedFile = model.files.first(where: { file in
               file.hunks.contains(where: { $0.id == focusedHunkID })
           }) {
            return focusedFile.id
        }
        return visibleFiles.first?.id
    }
    
    private static let fileRenderBatchSize = 24
    
    var body: some View {
        if model.isLoadingDiff && model.files.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView("Loading diff...")
                    .controlSize(.regular)
                Text("Parsing changes. Large diffs can take a moment.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else if model.files.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No diff loaded")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Click Choose Repository, then Working Changes.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else {
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        diffList
                    }
                    
                    if model.isLoadingDiff {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8)
                    }
                }
                .onChange(of: model.pendingRevealFilePath) { _, pendingPath in
                    guard let pendingPath else {
                        return
                    }
                    selectedScreen = .diff
                    Task {
                        await revealFileInDiff(path: pendingPath, using: proxy)
                    }
                }
            }
            .glassCard()
        }
    }
    
    private var diffList: some View {
        LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
            ForEach(visibleFiles) { file in
                Section {
                    DiffFileCard(
                        file: file,
                        focusedHunkID: $focusedHunkID,
                        typography: diffTypography
                    )
                } header: {
                    DiffFileStickyHeader(
                        file: file,
                        isActive: file.id == activeFileID
                    ) { seen in
                        model.markFileSeen(file: file, seen: seen)
                        
                    }
                    .id(file.id)
                }
            }
            
            if visibleFileCount < model.files.count {
                ProgressView("Loading more files...")
                    .controlSize(.small)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        loadMoreFilesIfNeeded(totalFiles: model.files.count)
                    }
            }
        }
    }
    
    private func loadMoreFilesIfNeeded(totalFiles: Int) {
        guard visibleFileCount < totalFiles else {
            return
        }
        visibleFileCount = min(totalFiles, visibleFileCount + Self.fileRenderBatchSize)
    }
    
    @MainActor
    private func revealFileInDiff(path: String, using proxy: ScrollViewProxy) async {
        let targetPath = normalizedDiffPath(path)
        guard !targetPath.isEmpty else {
            model.clearPendingRevealFilePath()
            return
        }
        
        guard let targetIndex = model.files.firstIndex(where: { file in
            diffFile(file, matchesPath: targetPath)
        }) else {
            model.clearPendingRevealFilePath()
            return
        }
        
        if visibleFileCount <= targetIndex {
            visibleFileCount = targetIndex + 1
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        
        guard targetIndex < model.files.count else {
            model.clearPendingRevealFilePath()
            return
        }
        let targetFile = model.files[targetIndex]
        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(targetFile.id, anchor: .top)
        }
        focusedHunkID = targetFile.hunks.first?.id
        model.clearPendingRevealFilePath()
    }
    
    private func diffFile(_ file: DiffFile, matchesPath targetPath: String) -> Bool {
        let candidates = [file.displayPath, file.oldPath, file.newPath]
            .map { normalizedDiffPath($0) }
            .filter { !$0.isEmpty && $0 != "/dev/null" }
        return candidates.contains(targetPath)
    }
    
    private func normalizedDiffPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }
}
