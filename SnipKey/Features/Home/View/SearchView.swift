//
//  SearchView.swift
//  SnipKey

import SwiftUI
import SwiftData
import AlertToast
import UniformTypeIdentifiers

struct SearchView: View {
    @Query(sort: \SnippetItem.creationDate, order: .reverse)
    private var allSnippets: [SnippetItem]

    @Query(sort: \SnipTag.creationDate, order: .reverse)
    private var tags: [SnipTag]

    @State private var searchText: String = ""
    @State private var showToast = false
    @State private var selectedTag: SnipTag? = nil
    @State private var resultRows: [SearchResultRow] = []
    @State private var isPresentingSnippetForm = false
    @State private var snippetFormDraft: SnippetFormDraft?

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Tags sorted by popularity (snippet count) then by creation date
    private var sortedTags: [SnipTag] {
        tags.sorted { tag1, tag2 in
            let count1 = tag1.snippets?.count ?? 0
            let count2 = tag2.snippets?.count ?? 0
            if count1 != count2 {
                return count1 > count2
            }
            return (tag1.creationDate) > (tag2.creationDate)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty && selectedTag == nil {
                    // Empty state when no search and no tag selected - show tag browser
                    EmptyStateView()
                } else if resultRows.isEmpty {
                    // No results state
                    NoResultsView()
                } else {
                    // Results list
                    ResultsListView()
                }
            }
            .navigationTitle(selectedTag != nil ? "Search in Tag" : "Search")
            .navigationSubtitle(selectedTag != nil ? "Filtered by \"\(selectedTag?.name ?? "")\"" : "")
            .searchable(
                text: Binding(
                    get: { searchText },
                    set: { newValue in
                        searchText = newValue
                        updateResultRows(searchText: newValue, selectedTag: selectedTag)
                    }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: selectedTag != nil ? "Search in \(selectedTag?.name ?? "tag")..." : "Search snippets..."
            )
            .toolbar {
                if selectedTag != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTag = nil
                                searchText = ""
                            }
                            updateResultRows(searchText: "", selectedTag: nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondaryLabel)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingSnippetForm, onDismiss: {
            snippetFormDraft = nil
        }) {
            NavigationStack {
                SnippetForm(
                    snippet: nil,
                    initialDraft: snippetFormDraft,
                    isFormVisible: $isPresentingSnippetForm
                )
            }
            .presentationBackground(Color.clear)
        }
        .task {
            updateResultRows()
        }
        .onChange(of: allSnippets.count) { _, _ in
            updateResultRows()
        }
        .onChange(of: selectedTag?.id) { _, _ in
            updateResultRows()
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

    // MARK: - Empty State View (with tag browser)
    @ViewBuilder
    func EmptyStateView() -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header section
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.secondaryLabel)

                    Text("Search Snippets")
                        .font(.custom("IBMPlexMono-SemiBold", size: 20))
                        .foregroundStyle(Color.label)

                    Text("Search by name, content, or tags")
                        .font(.custom("IBMPlexMono-Regular", size: 14))
                        .foregroundStyle(Color.secondaryLabel)
                }
                .padding(.top, 40)

                // Tag browser section
                if !sortedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        // Section header
                        HStack {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.yellow)

                            Text("Browse by Tag")
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .foregroundStyle(Color.label)

                            Spacer()

                            Text("\(sortedTags.count) tags")
                                .font(.custom("IBMPlexMono-Regular", size: 12))
                                .foregroundStyle(Color.tertiaryLabel)
                        }
                        .padding(.horizontal, 4)

                        // Tag grid
                        TagGridView()
                    }
                    .padding(.horizontal)
                } else {
                    // No tags available
                    VStack(spacing: 12) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Color.tertiaryLabel)

                        Text("No tags yet")
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundStyle(Color.secondaryLabel)

                        Text("Create snippets with tags to browse them here")
                            .font(.custom("IBMPlexMono-Regular", size: 12))
                            .foregroundStyle(Color.tertiaryLabel)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                }

                Spacer(minLength: 100)
            }
        }
    }

    // MARK: - Tag Grid View
    @ViewBuilder
    func TagGridView() -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(sortedTags, id: \.id) { tag in
                TagCardView(tag: tag)
            }
        }
    }

    // MARK: - Individual Tag Card
    @ViewBuilder
    func TagCardView(tag: SnipTag) -> some View {
        let snippetCount = tag.snippets?.count ?? 0

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTag = tag
            }
            updateResultRows(selectedTag: tag)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Icon and color indicator row
                HStack {
                    Image(systemName: tag.imageTag ?? "tag.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.label)

                    Spacer()

                    if let colorHex = tag.colorHex, let color = Color(hex: colorHex) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                    }
                }

                Spacer()

                // Tag name
                Text(tag.name ?? "Unnamed")
                    .font(.custom("IBMPlexMono-Medium", size: 15))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)

                // Snippet count
                Text("\(snippetCount) snippet\(snippetCount == 1 ? "" : "s")")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
                    .foregroundStyle(Color.secondaryLabel)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Tag Header
    @ViewBuilder
    func SelectedTagHeaderView() -> some View {
        if let tag = selectedTag {
            HStack(spacing: 10) {
                Image(systemName: tag.imageTag ?? "tag.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.yellow)

                Text("Filtered by")
                    .font(.custom("IBMPlexMono-Regular", size: 13))
                    .foregroundStyle(Color.secondaryLabel)

                HStack(spacing: 4) {
                    Text(tag.name ?? "")
                        .font(.custom("IBMPlexMono-Medium", size: 13))
                        .foregroundStyle(Color.label)

                    if let colorHex = tag.colorHex {
                        TagColorIndicator(colorHex: colorHex, size: 6)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTag = nil
                    }
                    updateResultRows(selectedTag: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.tertiaryLabel)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - No Results View
    @ViewBuilder
    func NoResultsView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.secondaryLabel)

            if let tag = selectedTag {
                // No results within selected tag
                Text("No Results")
                    .font(.custom("IBMPlexMono-SemiBold", size: 18))
                    .foregroundStyle(Color.label)

                VStack(spacing: 4) {
                    if searchText.isEmpty {
                        Text("No snippets in \"\(tag.name ?? "")\"")
                            .font(.custom("IBMPlexMono-Regular", size: 14))
                            .foregroundStyle(Color.secondaryLabel)
                    } else {
                        Text("No snippets found for \"\(searchText)\"")
                            .font(.custom("IBMPlexMono-Regular", size: 14))
                            .foregroundStyle(Color.secondaryLabel)

                        Text("in tag \"\(tag.name ?? "")\"")
                            .font(.custom("IBMPlexMono-Regular", size: 13))
                            .foregroundStyle(Color.tertiaryLabel)
                    }
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    if !normalizedSearchText.isEmpty {
                        CreateSearchSnippetButton()
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTag = nil
                        }
                        updateResultRows(selectedTag: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 12, weight: .medium))
                            Text("Clear filter")
                                .font(.custom("IBMPlexMono-Medium", size: 13))
                        }
                        .foregroundStyle(Color.yellow)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule()
                                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                                }
                        }
                    }
                }
                .padding(.top, 8)
            } else {
                // Regular no results (searching all snippets)
                Text("No Results")
                    .font(.custom("IBMPlexMono-SemiBold", size: 18))
                    .foregroundStyle(Color.label)

                Text("No snippets found for \"\(searchText)\"")
                    .font(.custom("IBMPlexMono-Regular", size: 14))
                    .foregroundStyle(Color.secondaryLabel)
                    .multilineTextAlignment(.center)

                if !normalizedSearchText.isEmpty {
                    CreateSearchSnippetButton()
                        .padding(.top, 8)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    func CreateSearchSnippetButton() -> some View {
        Button(action: presentSearchDraft) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Create New One")
                    .font(.custom("IBMPlexMono-Medium", size: 13))
            }
            .foregroundStyle(Color.label)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(Color.yellow.opacity(0.18))
                    .overlay {
                        Capsule()
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create new snippet from search")
    }

    // MARK: - Results List View
    @ViewBuilder
    func ResultsListView() -> some View {
        List {
            // Show selected tag header if filtering by tag
            if selectedTag != nil {
                Section {
                    SelectedTagHeaderView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // Results section
            Section {
                ForEach(resultRows) { result in
                    NavigationLink(value: result.item) {
                        SearchResultRowView(result: result)
                            .equatable()
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            copyToClipboard(result)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc.fill")
                        }
                        .tint(Color.quaternaryLabel)
                    }
                }
            } header: {
                if selectedTag != nil {
                    Text("\(resultRows.count) result\(resultRows.count == 1 ? "" : "s")")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundStyle(Color.tertiaryLabel)
                }
            }
        }
        .navigationDestination(for: SnippetItem.self) { item in
            SnippetViewDetail(item: item)
        }
    }

    // MARK: - Helper Functions

    // Helper function to copy snippet to clipboard
    private func updateResultRows(
        searchText overrideSearchText: String? = nil,
        selectedTag overrideSelectedTag: SnipTag? = nil
    ) {
        let query = (overrideSearchText ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = overrideSelectedTag ?? selectedTag
        let tagID = tag?.id

        let nextRows = allSnippets.compactMap { snippet -> SearchResultRow? in
            if let tagID, snippet.customTag?.id != tagID {
                return nil
            }

            if !query.isEmpty {
                let titleMatch = snippet.title?.localizedCaseInsensitiveContains(query) ?? false
                let contentMatch = snippet.content?.localizedCaseInsensitiveContains(query) ?? false
                let tagMatch = snippet.customTag?.name?.localizedCaseInsensitiveContains(query) ?? false

                if !titleMatch && !contentMatch && !tagMatch {
                    return nil
                }
            }

            return SearchResultRow(item: snippet)
        }

        if resultRows != nextRows {
            resultRows = nextRows
        }
    }

    private func presentSearchDraft() {
        let draftTitle = String(normalizedSearchText.prefix(titleCharLimit))
        guard !draftTitle.isEmpty else { return }

        snippetFormDraft = SnippetFormDraft(
            type: .txt,
            pasteClipboardOnAppear: false,
            initialTitle: draftTitle,
            initialTag: selectedTag
        )
        isPresentingSnippetForm = true
    }

    private func copyToClipboard(_ result: SearchResultRow) {
        guard !result.content.isEmpty else { return }
        let clipboard = UIPasteboard.general
        clipboard.setValue(result.content, forPasteboardType: UTType.plainText.identifier)
        showToast = true
    }
}

private struct SearchResultRow: Identifiable, Equatable {
    let item: SnippetItem
    let id: String
    let title: String
    let content: String
    let tagName: String?
    let tagColorHex: String?
    let type: SnipType
    let isSecure: Bool

    init(item: SnippetItem) {
        self.item = item
        self.id = item.id ?? String(describing: ObjectIdentifier(item))
        self.title = item.title ?? ""
        self.content = item.content ?? ""
        self.tagName = item.customTag?.name
        self.tagColorHex = item.customTag?.colorHex
        self.type = item.type ?? .txt
        self.isSecure = item.isSecure
    }

    static func == (lhs: SearchResultRow, rhs: SearchResultRow) -> Bool {
        lhs.item === rhs.item &&
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.content == rhs.content &&
        lhs.tagName == rhs.tagName &&
        lhs.tagColorHex == rhs.tagColorHex &&
        lhs.type == rhs.type &&
        lhs.isSecure == rhs.isSecure
    }
}

private struct SearchResultRowView: View, Equatable {
    let result: SearchResultRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.type.snipTypeImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.label)
                .frame(width: 36, height: 36)
                .background(Color.secondarySystemBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.custom("IBMPlexMono-Medium", size: 14))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("#\(result.tagName?.isEmpty == false ? result.tagName! : "None")")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundStyle(Color.secondaryLabel)
                        .lineLimit(1)

                    TagColorIndicator(colorHex: result.tagColorHex, size: 7)
                }
            }

            Spacer(minLength: 8)

            if result.isSecure {
                Image(systemName: "lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondaryLabel)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let container = SnipKeyDataManager().makeSharedContainer()

    SearchView()
        .modelContainer(container)
}
