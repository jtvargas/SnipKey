//
//  SearchView.swift
//  SnipKey
//

import SwiftUI
import SwiftData
import AlertToast
import UniformTypeIdentifiers

struct SearchView: View {
    @Query(sort: \SnippetItem.creationDate, order: .reverse)
    private var allSnippets: [SnippetItem]
    
    @State private var searchText: String = ""
    @State private var showToast = false
    
    // Computed property for filtered snippets
    private var filteredSnippets: [SnippetItem] {
        if searchText.isEmpty {
            return allSnippets
        }
        
        return allSnippets.filter { snippet in
            let titleMatch = snippet.title?.localizedCaseInsensitiveContains(searchText) ?? false
            let contentMatch = snippet.content?.localizedCaseInsensitiveContains(searchText) ?? false
            let tagMatch = snippet.customTag?.name?.localizedCaseInsensitiveContains(searchText) ?? false
            return titleMatch || contentMatch || tagMatch
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    // Empty state when no search
                    ContentUnavailableView(
                        "Search Snippets",
                        systemImage: "magnifyingglass",
                        description: Text("Search by name, content, tags...")
                    )
                } else if filteredSnippets.isEmpty {
                    // No results state
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("No snippets found for '\(searchText)'")
                    )
                } else {
                    // Results list
                    List {
                        ForEach(filteredSnippets, id: \.id) { snippet in
                            NavigationLink(value: snippet) {
                                SnippetListItem(item: snippet)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    copyToClipboard(snippet)
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc.fill")
                                }
                                .tint(Color.quaternaryLabel)
                            }
                        }
                    }
                    .navigationDestination(for: SnippetItem.self) { item in
                        SnippetViewDetail(item: item)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Type here..."
            )
        }
        .toast(isPresenting: $showToast) {
            AlertToast(
                displayMode: .banner(.pop),
                type: .systemImage("doc.on.clipboard", .label),
                title: "Copied!",
                style: .style(
                    backgroundColor: Color.tertiarySystemBackground,
                    titleFont: .custom("IBMPlexMono-Medium", size: 14)
                )
            )
        }
    }
    
    // Helper function to copy snippet to clipboard
    private func copyToClipboard(_ snippet: SnippetItem) {
        guard let content = snippet.content else { return }
        let clipboard = UIPasteboard.general
        clipboard.setValue(content, forPasteboardType: UTType.plainText.identifier)
        showToast = true
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()
    
    SearchView()
        .modelContainer(container)
}
