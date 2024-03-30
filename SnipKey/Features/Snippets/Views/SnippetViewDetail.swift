//
//  SnippetViewDetail.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftData
import SwiftUI

struct SnippetViewDetail: View {
  @State var isEditFormVisible: Bool = false
  @State private var snippet: SnippetItem = SnippetItem(
    title: "", content: "", tag: Tags.none, type: SnipType.txt)

  func toggleEditForm() {
    self.isEditFormVisible.toggle()
    //        snippet = SnippetItem(title: "", content: "", tag: Tags.none, type: SnipType.txt);
  }

  var body: some View {
    Form {
      Section(header: Text("Type")) {
        HStack {
          Spacer()
          VStack {
            SnippetImage(type: snippet.type)
              .font(.system(size: 44))
              .frame(width: 82, height: 82)
              .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              .foregroundStyle(.white)
            Text("\(snippet.type)")
          }
          Spacer()

        }
      }
      .listRowBackground(Color.customSecondary)

      Section(header: Text("title")) {
        HStack {
          Spacer()
          VStack {
            Text("\(snippet.title)")
          }
          Spacer()

        }
      }
      .frame(alignment: .center)
      .listRowBackground(Color.customSecondary)

      Section(
        header: Text("Content"),
        footer: Label("\(snippet.tag)", systemImage: imageForTag(snippet.tag))
      ) {
        ScrollView {
          Text("\(snippet.content)")
            .multilineTextAlignment(.leading)
            .padding(.top, 8)
        }.frame(height: 180)

      }
      .listRowBackground(Color.customSecondary)

    }
    .navigationTitle("\(snippet.title)")
    .font(.custom("IBMPlexMono-Medium", size: 15))
    .bold()
    .tint(Color.black)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: toggleEditForm) {
          Text("Edit")
            .bold()
            .font(.custom("IBMPlexMono-Medium", size: 15))
            .underline()
        }.sheet(isPresented: $isEditFormVisible) {
          NavigationStack {
            Label("Changes are saved automatically", systemImage: "info.square.fill")
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 15))
            SnippetForm(isFormVisible: $isEditFormVisible, snippetItem: $snippet)
              .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                  Button(action: toggleEditForm) {
                    Text("Close")
                      .tint(Color.black)
                      .bold()
                      .underline()
                      .font(.custom("IBMPlexMono-Medium", size: 15))
                  }
                }
              }
          }

        }
      }
    }
    //        .onAppear(){
    //            viewModel.modelContext = modelContext
    //        }
  }

  init(item: SnippetItem) {
    _snippet = State(initialValue: item)
  }
}

#Preview {
  SnippetViewDetail(item: .dummy)
}
