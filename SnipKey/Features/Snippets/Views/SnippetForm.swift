//
//  SnippetForm.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/28/24.
//

import SwiftData
import SwiftUI

struct CustomRadioButtonGroup<T: Hashable>: View {
  let items: [T]
  @Binding var selection: T
  let labels: [T: String]

  var body: some View {
    HStack {
      ForEach(items, id: \.self) { item in
        Button(action: {
          let impactMed = UIImpactFeedbackGenerator(style: .medium)
          impactMed.impactOccurred()
          self.selection = item
          hideKeyboard()
        }) {
          VStack {
            SnippetImage(type: item as! SnipType)
              .frame(width: 35, height: 35)
              .background(Color.secondarySystemBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              .foregroundStyle(.white)
            Text(self.labels[item] ?? "")
              .foregroundColor(selection == item ? Color.label : .gray)
            if selection == item {
              Circle()
                .fill(Color.label)
                .frame(width: 10, height: 10)
            } else {
              Circle()
                .stroke(Color.label, lineWidth: 1)
                .frame(width: 10, height: 10)
            }
          }
          .padding()
          .frame(maxWidth: .infinity)
          .contentShape(Circle())

        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
          /// apply a rounded border
          selection == item
            ? RoundedRectangle(cornerRadius: 8)
              .stroke(Color.secondarySystemBackground, lineWidth: 4) : nil
        )

      }

    }
  }
}

func imageForTag(_ tag: Tags) -> String {
  switch tag {
  case .none:
    return "tag.slash.fill"
  case .personal:
    return "person.text.rectangle.fill"
  case .work:
    return "case.fill"
  }

}

let options: [SnipType] = [.txt, .url]
let labels: [SnipType: String] = [.txt: "text", .url: "url"]
let charLimit = 25
enum Field {
  case snippetTitle
  case snippetContent
}
//TODO: Investigate how to handle the data to be able to edit and create from specific view
struct SnippetForm: View {
  //    @Environment(\.modelContext) var modelContext
  @FocusState private var focusedField: Field?
  //    @State private var snippet: SnippetItem = SnippetItem(title: "", content: "", tag: Tags.none, type: SnipType.txt);
  @Binding var isFormVisible: Bool
  @Binding var snippetItem: SnippetItem

  func toggleFormVisibility() {
    if snippetItem.title.isEmpty || snippetItem.content.isEmpty {
      print("cant save empty")
    } else {
      isFormVisible.toggle()
    }

  }

  func onClosePress() {
    self.toggleFormVisibility()
  }

  var body: some View {
    Form {
      Section(header: Text("snippet type")) {
        CustomRadioButtonGroup(items: options, selection: $snippetItem.type, labels: labels)

      }
      .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))

      Section(
        header: Text("snippet title *"),
        footer: Text("Remaining: \(charLimit - snippetItem.title.count)")
      ) {
        TextField("Title", text: $snippetItem.title)
          .disableAutocorrection(true)
          .focused($focusedField, equals: .snippetTitle)
          .submitLabel(.return)
          .limitText($snippetItem.title, to: 25)

      }
      .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))

      Section(header: Text("snippet content *")) {
        TextField("Content", text: $snippetItem.content, axis: .vertical)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
          .lineLimit(5...10)
          .focused($focusedField, equals: .snippetContent)
          .submitLabel(.return)

      }
      .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))

      Section(
        header: Text("tag"),
        footer: Label(
          "Categorize your snippets for easy access", systemImage: "questionmark.circle")
      ) {
        Picker(selection: $snippetItem.tag, label: Image(systemName: "tag.fill")) {
          ForEach(Tags.allCases, id: \.id) { tag in
            HStack {
              Text(tag.rawValue)
              Spacer()
              Image(systemName: imageForTag(tag))
            }
            .tag(tag)
          }
        }
        .pickerStyle(.menu)
        .tint(Color.label)
        .onTapGesture {
          let impactMed = UIImpactFeedbackGenerator(style: .medium)
          impactMed.impactOccurred()
        }
      }
      .listRowBackground(EmptyView().background(Color.tertiarySystemBackground))

      .onSubmit {
        switch focusedField {
        default:
          print("SnippetContent")
        }
      }
    }
    .bold()
    .font(.custom("IBMPlexMono-Medium", size: 15))
    .toolbar {
        ToolbarItemGroup(placement: .keyboard){
            Spacer()
            Button("Done") {
                focusedField = nil
            }
            .font(.custom("IBMPlexMono-Bold", size: 14))
            .tint(Color.black)
            .background(Color.customSecondary)
            .cornerRadius(40)
        }
    }
  }
}

struct SnippetFormBindingPreview: View {
  @State private var value = false
  @State private var tempSnippet: SnippetItem = SnippetItem(
    title: "", content: "", tag: Tags.none, type: SnipType.txt)

  var body: some View {
    SnippetForm(isFormVisible: $value, snippetItem: $tempSnippet)
  }
}

#Preview {
  return SnippetFormBindingPreview()
}
