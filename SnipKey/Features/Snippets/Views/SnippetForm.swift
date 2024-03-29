//
//  SnippetForm.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/28/24.
//

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
        }) {
          VStack {
            SnippetImage(type: item as! SnipType)
            Text(self.labels[item] ?? "")
              .foregroundColor(selection == item ? Color.black : .gray)
            if selection == item {
              Circle()
                .fill(Color.black)
                .frame(width: 10, height: 10)
            } else {
              Circle()
                .stroke(Color.gray, lineWidth: 1)
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
              .stroke(Color.black, lineWidth: 2) : nil
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

struct SnippetForm: View {
  enum Field {
    case snippetTitle
    case snippetContent
  }

  var onClosePress: () -> Void
  var onSavePress: (_ title: String, _ content: String, _ tag: Tags, _ option: SnipType) -> Void
  @State private var snippetTitle: String = ""
  @State private var selectedTag: Tags = .none
  @State private var snippetContent: String = ""
  @State private var selectedOption: SnipType = .txt
  @FocusState private var focusedField: Field?

  let options: [SnipType] = [.txt, .url]
  let labels: [SnipType: String] = [.txt: "text", .url: "url"]

  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text("snippet type")) {
          CustomRadioButtonGroup(items: options, selection: $selectedOption, labels: labels)

        }
        .listRowBackground(EmptyView().background(Color.customSecondary))

        Section(header: Text("snippet title")) {
          TextField("Title", text: $snippetTitle)
            .disableAutocorrection(true)
            .focused($focusedField, equals: .snippetTitle)
            .submitLabel(.next)

        }
        .listRowBackground(EmptyView().background(Color.customSecondary))

        Section(header: Text("snippet content")) {
          TextField("Content", text: $snippetContent, axis: .vertical)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .lineLimit(5...10)
            .focused($focusedField, equals: .snippetContent)
            .submitLabel(.return)
        }
        .listRowBackground(EmptyView().background(Color.customSecondary))

        Section(
          header: Text("tag"),
          footer: Label(
            "Categorize your snippets for easy access", systemImage: "questionmark.circle")
        ) {
          Picker(selection: $selectedTag, label: Image(systemName: "tag.fill")) {
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
          .tint(Color.black)
          .onTapGesture {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
          }
        }
        .listRowBackground(EmptyView().background(Color.customSecondary))

      }
      .onAppear {
        self.focusedField = .snippetTitle
      }
      .onSubmit {
        switch focusedField {
        case .snippetTitle:
          focusedField = .snippetContent
        default:
          print("SnippetContent")
        }
      }
      .navigationTitle("Snippet")
      .font(.custom("IBMPlexMono-Bold", size: 14))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()

          Button("Done") {
            focusedField = nil
          }
          .font(.custom("IBMPlexMono-Bold", size: 14))
          .tint(Color.black)
          .background(Color.customSecondary)
          .cornerRadius(40)
        }

        ToolbarItem(placement: .topBarLeading) {
          Button(action: self.onClosePress) {
            Text("Close")
              .tint(Color.black)
              .bold()
              .underline()
              .font(.custom("IBMPlexMono-Medium", size: 15))
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button(action: {
            self.onSavePress(snippetTitle, snippetContent, selectedTag, selectedOption)
          }) {
            Text("Save")
              .tint(Color.black)
              .bold()
              .underline()
              .font(.custom("IBMPlexMono-Medium", size: 15))
          }
          .disabled(snippetTitle.isEmpty || snippetContent.isEmpty)
        }
      }
    }
  }
}

#Preview {
  func handleOnClosePress() {
    print("on close press")
  }

  func handleOnSavePress(_ title: String, _ content: String, _ tag: Tags, _ type: SnipType) {
    print("Title: \(title), \(content), \(tag), \(type)")
  }

  return SnippetForm(onClosePress: handleOnClosePress, onSavePress: handleOnSavePress)
}
