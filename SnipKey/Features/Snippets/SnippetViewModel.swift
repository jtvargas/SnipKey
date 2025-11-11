//
//  SnippetViewModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/27/24.
//

import SwiftData
import SwiftUI

@Observable
class SnippetViewModel {
    var modelContext: ModelContext? = nil
    
    func fetchSnippets() -> [SnippetItem]? {
        let fetchDescriptor = FetchDescriptor<SnippetItem>()
        
        do {
            let snippets = try modelContext?.fetch(fetchDescriptor)
            
            return snippets
            
        } catch {
            print("FAILED TO FETCH SNIPPETS")
            return []
        }
    }
    
    func setupInitialTags(){
        let fetchDescriptor = FetchDescriptor<SnipTag>()
        
        do {
            let tags = try modelContext?.fetch(fetchDescriptor)
            
            
            let containsWorkTag = tags?.contains{ $0.name == "Work" } ?? false
            let containsPersonalTag = tags?.contains{ $0.name == "Personal" } ?? false
            let containsNoneTag = tags?.contains{ $0.name == "None" } ?? false
            
            if containsWorkTag && containsPersonalTag && containsNoneTag {
                print("INITIAL TAGS ALREADY SETUP!")
            } else {
                print("NEED TO SETUP INITIAL TAGS!...")
                self.setupTags()
            }
            
        } catch {
            print("FAILED TO SETUP INITIAL TAGS MODEL")
        }
    }
    
    func setupTags() {
        print("SETTING UP INITIAL TAGS...")
        let newNoneTag = SnipTag(name: "None",imageTag: "tag.fill")
        let newPersonalTag = SnipTag(name: "Personal",imageTag: "person.fill")
        let newWorkTag = SnipTag(name: "Work",imageTag: "suitcase.fill")
        self.modelContext?.insert(newPersonalTag)
        self.modelContext?.insert(newWorkTag)
        self.modelContext?.insert(newNoneTag)
        print("INITIAL TAGS SETUP!")
    }
    
    //    func createNewTagAndRelationship(tag: SnipTag, item: SnippetItem){
    ////        self.modelContext?.insert(tag)
    ////        item.customTag = tag
    //    }
    
    // via List onDelete
    func deleteItems(offsets: IndexSet, snippets:  [SnippetItem]) {
        withAnimation {
              for index in offsets {
                  self.modelContext?.delete(snippets[index])
              }
          }
        try? self.modelContext?.save()
    }
    
    // single
    func deleteItem(snippet: SnippetItem) {
        withAnimation {
            self.modelContext?.delete(snippet)
        }
        try? self.modelContext?.save()
    }
    
    // multiple
    func deleteSelectedItems(snippets: [SnippetItem]) {
        withAnimation {
            for snippet in snippets {
                self.modelContext?.delete(snippet)
            }
        }
        try? self.modelContext?.save()
    }
    
    func deleteTag(offsets: IndexSet, tags:  [SnipTag]) {
        for index in offsets {
            self.modelContext?.delete(tags[index])
        }
    }
    
    func createTag(name: String, iconName: String) -> SnipTag {
        print("CREATING NEW TAG: \(name)")
        let newTag = SnipTag(name: name,imageTag: iconName)
        self.modelContext?.insert(newTag)
        print("TAG CREATED: \(name)")
        return newTag
        
    }
    
    func createData(type: FileType, data: Data, fileFormatType: String) -> SnippetFile {
        print("CREATING NEW FILE-DOCUMENT: \(type)")
        let newFile = SnippetFile(type: type, formatType: fileFormatType, fileData: data)
        newFile.fileData = data
        self.modelContext?.insert(newFile)
        print("FILE CREATED: \(type) with ID: \(newFile.id)")
        return newFile
        
    }
    
    func trackSnippetUsage(snippet: SnippetItem) {
        print("Use snippet!")
        
        snippet.lastTimeUsed = Date.now
        snippet.usedCount += 1
    }
    
    func findTagCreated(tagName: String) -> SnipTag? {
        let fetchDescriptor = FetchDescriptor<SnipTag>()
        
        do {
            let tags = try modelContext?.fetch(fetchDescriptor)
            
            
            let tagFilteredByName = tags?.filter{ $0.name == tagName } ?? []
            
            if !tagFilteredByName.isEmpty {
                return tagFilteredByName.first
            } else {
                return nil
            }
            
        } catch {
            print("FAILED TO SETUP INITIAL TAGS MODEL")
            return nil
        }
    }
    
    func findFileCreated(fileId: String) -> SnippetFile? {
        let fetchDescriptor = FetchDescriptor<SnippetFile>()
        
        do {
            let snippetFiles = try modelContext?.fetch(fetchDescriptor)
            
            
            let snippetFileFilteredById = snippetFiles?.filter{ $0.id == fileId } ?? []
            
            if !snippetFileFilteredById.isEmpty {
                return snippetFileFilteredById.first
            } else {
                return nil
            }
            
        } catch {
            print("FAILED TO FIND FILE CREATED")
            return nil
        }
    }
    
  
    func deleteFile(fileId: String) {
        if let snippetFile = findFileCreated(fileId: fileId) {
            self.modelContext?.delete(snippetFile)
        }
    }
    
    func createSnippet(_ title: String, content: String, type: SnipType?, isSecure: Bool) -> SnippetItem {
        print("ADD FUNC CALLED!")
        let newItem = SnippetItem(title: title, content: content, type: type ?? .txt, isSecure: isSecure)
        self.modelContext?.insert(newItem)
        return newItem
        
    }

}

