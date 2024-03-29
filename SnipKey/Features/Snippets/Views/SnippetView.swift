//
//  ContentView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftData
import SwiftUI

//TODO: Add OnBoarding Feature and Settings Feature, then try to see issue in SnippetForm is lag while oppening the first time

struct SnippetView: View {
  @State var showSnippedDetailSheet = false
  @State private var viewModel: ViewModel
  @State private var showModal = false
  @State private var selectedSnippet: SnippetItem?
  @State var isPresented: Bool = false

  @State private var selectedFilter: Tags = .none

  func toggleFormModal() {
    self.isPresented.toggle()
  }

  func handleOnSavePress(_ title: String, _ content: String, _ tag: Tags, _ type: SnipType) {
    print("Title: \(title), \(content)")
    viewModel.addItem(title, content: content, tag: tag, type: type)
    toggleFormModal()
  }

  func handleOnKeyboardStatusPress() {
    print("Keyboard Status press")
  }

  var body: some View {
    NavigationSplitView {
      VStack {
        if !viewModel.snippets.isEmpty {
          KeyboardStatusView(isActive: false, onKeyboardStatusPress: handleOnKeyboardStatusPress)
          Form {
            Section(header: Text("Snippets")) {
              SnippetList(
                items: viewModel.snippets, onDeleteHandler: viewModel.deleteItems(offsets:))
            }
          }
        }

      }
      .navigationTitle("SnipKey")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        if viewModel.snippets.isEmpty {
          SnippetListEmpty()
        }
      }
      .toolbar {
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
              Image(systemName: "line.3.horizontal.decrease.circle").tint(Color.black)
            })
        }

        ToolbarItem(placement: .topBarLeading) {
          if !viewModel.snippets.isEmpty {
            EditButton()
              .bold()
              .frame(maxWidth: .infinity, alignment: .leading)
              .tint(Color.black)
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
          }

        }

        ToolbarItem(placement: .bottomBar) {
          HStack(alignment: .center) {
            Button(action: toggleFormModal) {
              Image(systemName: "info.circle.fill")
                .tint(Color.black)
                .font(.system(size: 24))
            }.sheet(isPresented: $isPresented) {  // Passing the state to the sheet API
              SnippetForm(onClosePress: toggleFormModal, onSavePress: handleOnSavePress)
                .interactiveDismissDisabled()
            }
            Spacer()
            Button(action: toggleFormModal) {
              Image(systemName: "plus.app.fill")
                .tint(Color.black)
                .font(.system(size: 28))

            }
            .sheet(isPresented: $isPresented) {  // Passing the state to the sheet API
              SnippetForm(onClosePress: toggleFormModal, onSavePress: handleOnSavePress)
                .interactiveDismissDisabled()
            }

            Spacer()
            Button(action: toggleFormModal) {
              Image(systemName: "gearshape.circle.fill")
                .tint(Color.black)
                .font(.system(size: 24))
            }.sheet(isPresented: $isPresented) {  // Passing the state to the sheet API
              SnippetForm(onClosePress: toggleFormModal, onSavePress: handleOnSavePress)
                .interactiveDismissDisabled()
            }

          }
          .padding(.bottom, 10)
        }

      }

    } detail: {
      Text("DETAIL")
    }
  }

  init(modelContext: ModelContext) {
    let viewModel = ViewModel(modelContext: modelContext)
    _viewModel = State(initialValue: viewModel)
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

  return SnippetView(modelContext: sharedModelContainer.mainContext)
    .modelContainer(sharedModelContainer)
}
