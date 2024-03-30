//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftData
import SwiftUI

struct SnippetView: View {
  @State var showSnippedDetailSheet = false
  @Environment(\.modelContext) var modelContext
  @State var viewModel = ViewModel()
  @Query(sort: \SnippetItem.timestamp, order: .reverse) private var snippets: [SnippetItem]

  @State private var showModal = false
  @State var isPresentedFormModal: Bool = false
  @State var isPresentedWelcomeInfo: Bool = false
  @State private var selectedFilter: Tags = .none

  @State private var snippet: SnippetItem = SnippetItem(
    title: "", content: "", tag: Tags.none, type: SnipType.txt)

  func toggleFormModal() {
    snippet = SnippetItem(title: "", content: "", tag: Tags.none, type: SnipType.txt)
    self.isPresentedFormModal.toggle()
  }

  func toggleWelcomeInfo() {
    self.isPresentedWelcomeInfo.toggle()
  }
  func toggleSettingsModal() {
    print("toggleSettingsModal")
  }

  func handleOnKeyboardStatusPress() {
    print("Keyboard Status press")
  }

  func getSnippetItems() -> [SnippetItem] {
    if selectedFilter == .none {
      return snippets
    }

    let snippetsFiltered = snippets.filter { snippetItem in
      return snippetItem.tag == selectedFilter
    }

    return snippetsFiltered
  }

  func handleDeleteSnippet(offsets: IndexSet) {
    viewModel.deleteItems(offsets: offsets, snippets: snippets)
  }

  func onCreateSnippet() {
    if snippet.title.isEmpty || snippet.content.isEmpty {
      print("cant save empty")
    } else {
      viewModel.addItem(
        snippet.title, content: snippet.content, tag: snippet.tag, type: snippet.type)

      self.toggleFormModal()
      print("Snippet CREATED")
    }

  }

  var body: some View {
    NavigationStack {
      VStack {
        if !snippets.isEmpty {
          KeyboardStatusView(isActive: false, onKeyboardStatusPress: handleOnKeyboardStatusPress)
          Form {
            Section(header: Text("Snippets")) {
              //              SnippetList(
              //                items: getSnippetItems(), onDeleteHandler: handleDeleteSnippet)
              List {
                ForEach(getSnippetItems(), id: \.self.id) { snippetItem in
                  NavigationLink(destination: SnippetViewDetail(item: snippetItem)) {
                    SnippetListItem(item: snippetItem)
                  }
                  .listRowBackground(Color.customSecondary)
                }
                .onDelete(perform: { indexSet in
                  self.handleDeleteSnippet(offsets: indexSet)
                })
              }
            }
          }
        }

      }
      .navigationTitle(snippets.isEmpty ? "" : "SnipKey")
      .font(.custom("IBMPlexMono-Medium", size: 16))
      .navigationBarTitleDisplayMode(.large)
      .safeAreaInset(edge: .bottom) {
        if snippets.isEmpty {
          SnippetListEmpty()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          if !snippets.isEmpty {
            EditButton()
              .frame(maxWidth: .infinity, alignment: .leading)
              .tint(Color.black)
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
          }

        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu(
            content: {
              Picker(selection: $selectedFilter, label: Image(systemName: "tag.fill")) {
                ForEach(Tags.allCases, id: \.id) { tag in
                  HStack {
                    Text(tag.rawValue)
                    Spacer()
                    Image(systemName: imageForTag(tag))
                  }
                  .tag(tag)
                }
              }
            },
            label: {
              Image(
                systemName: selectedFilter != Tags.none
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
              )
              .tint(Color.black)
            })
        }

        ToolbarItem(placement: .bottomBar) {
          HStack(alignment: .center) {
            Button(action: toggleWelcomeInfo) {
              Image(systemName: "info.circle.fill")
                .tint(Color.black)
                .font(.system(size: 24))
            }.sheet(isPresented: $isPresentedWelcomeInfo) {
              WelcomeView(skipCallback: toggleWelcomeInfo)
            }
            Spacer()
            Button(action: toggleFormModal) {
              Image(systemName: "plus.app.fill")
                .tint(Color.black)
                .font(.system(size: 28))

            }
            .sheet(isPresented: $isPresentedFormModal) {
              NavigationStack {
                SnippetForm(isFormVisible: $isPresentedFormModal, snippetItem: $snippet)
                  .navigationTitle("New Snippet")
                  .font(.custom("IBMPlexMono-Bold", size: 14))
                  .navigationBarTitleDisplayMode(.inline)
                  .interactiveDismissDisabled()
                  .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                      Button(action: toggleFormModal) {
                        Text("Close")
                          .tint(Color.black)
                          .bold()
                          .underline()
                          .font(.custom("IBMPlexMono-Medium", size: 15))
                      }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                      Button(action: onCreateSnippet) {
                        Text("Save")
                          .tint(Color.black)
                          .bold()
                          .underline()
                          .font(.custom("IBMPlexMono-Medium", size: 15))
                      }
                    }
                  }
              }
            }

            Spacer()
            Button(action: toggleSettingsModal) {
              Image(systemName: "gearshape.circle.fill")
                .tint(Color.black)
                .font(.system(size: 24))
            }

          }
          .padding(.bottom, 10)

        }
      }
    }
    .tint(Color.black)
    .onAppear {
      viewModel.modelContext = modelContext
      //      viewModel.fetchData()
    }
  }

  init() {
    UINavigationBar.appearance().largeTitleTextAttributes = [
      .font: UIFont(name: "IBMPlexMono-Bold", size: 34)!
    ]
    UINavigationBar.appearance().titleTextAttributes = [
      .font: UIFont(name: "IBMPlexMono-Bold", size: 20)!
    ]
  }
}

#Preview {
  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      SnippetItem.self
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  return SnippetView()
    .modelContainer(sharedModelContainer)

}
