//
//  SnippetViewDetail.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import AlertToast
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SnippetViewDetail: View {
  @State private var showToast = false
  @State var isEditFormVisible: Bool = false
  @State private var snippet: SnippetItem = SnippetItem(
    title: "", content: "", type: SnipType.txt)

  var body: some View {
    Form {
      Section(header: Text("Type")) {
        HStack {
          Spacer()
          VStack {
            SnippetImage(type: snippet.type)
              .font(.system(size: 44))
              .frame(width: 82, height: 82)
              .background(
                Color.secondarySystemBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
              )
              .foregroundStyle(.white)
            Text("\(snippet.type)")
          }
          Spacer()

        }
      }
      .listRowBackground(Color.tertiarySystemBackground)

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
      .listRowBackground(Color.tertiarySystemBackground)

      Section(
        header: Text("Content"),
        footer: HStack {
          Label("\(snippet.customTag?.name ?? "None")", systemImage: "tag.fill")
            .tint(.label)
          Spacer()
          Button(action: copyToClipboard) {
            Text("Copy")
              .bold()
              .font(.custom("IBMPlexMono-Medium", size: 16))
              .underline()
              .tint(Color.label)
          }
        }
      ) {
        ScrollView {
          Text("\(snippet.content)")
            .multilineTextAlignment(.leading)
            .padding(.top, 8)
            .tint(Color.label)
        }.frame(height: 180)

      }
      .listRowBackground(Color.tertiarySystemBackground)

    }
    .navigationTitle("\(snippet.title)")
    .font(.custom("IBMPlexMono-Medium", size: 15))
    .bold()
    .tint(Color.label)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: toggleEditForm) {
          Text("Edit")
            .bold()
            .font(.custom("IBMPlexMono-Medium", size: 15))
            .underline()
            .tint(Color.label)
        }.sheet(isPresented: $isEditFormVisible) {
          NavigationStack {
            SnippetForm(snippet: snippet, isFormVisible: $isEditFormVisible)
          }

        }
      }
    }
    .toast(isPresenting: $showToast) {
      AlertToast(
        displayMode: .banner(.pop), type: .systemImage("doc.on.clipboard", .label),
        title: "Copied!",
        style: .style(
          backgroundColor: Color.tertiarySystemBackground,
          titleFont: .custom("IBMPlexMono-Medium", size: 14)))
    }
  }

  init(item: SnippetItem) {
    _snippet = State(initialValue: item)
  }

  func toggleEditForm() {
    self.isEditFormVisible.toggle()
  }

  func copyToClipboard() {
    let clipboard = UIPasteboard.general
    clipboard.setValue(snippet.content, forPasteboardType: UTType.plainText.identifier)
    showToast.toggle()
  }
}

#Preview {
  SnippetViewDetail(item: .dummy)
}
