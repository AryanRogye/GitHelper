//
//  GitCommitTreeArea.swift
//  GitDiffHelper
//
//  Created by Aryan Rogye on 4/16/26.
//

import SwiftUI

struct GitCommitTreeArea: View {
    
    @EnvironmentObject private var model: DiffViewModel
    @Binding var storedTreeScale: Double
    
    private var treeTypography: CommitTreeTypography {
        CommitTreeTypography(scale: CGFloat(storedTreeScale))
    }

    var body: some View {
        if model.repoPath.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No repository selected")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Choose a repository, then open Commit Tree.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
        } else if model.isLoadingLog && model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView("Building commit tree...")
                    .controlSize(.regular)
                Text("Reading commit ancestry and branch paths from Git.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await model.ensureCommitLogLoaded()
            }
        } else if model.logEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No commits found")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(model.logStatusLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await model.loadCommitLog(branchFilter: model.selectedLogBranchFilter)
                    }
                } label: {
                    Label("Reload Commit Tree", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .glassCard()
            .task {
                await model.ensureCommitLogLoaded()
            }
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        CommitTreeLegendCard()
                        CommitTreeGraphList(entries: model.logEntries, typography: treeTypography)
                    }
                    .padding(8)
                }
                
                if model.isLoadingLog {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .glassCard()
            .task {
                await model.ensureCommitLogLoaded()
            }
        }
    }
}
