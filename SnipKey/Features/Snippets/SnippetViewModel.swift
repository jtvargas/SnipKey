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
        let newPersonalTag = SnipTag(name: "Personal",imageTag: "circle.fill")
        let newWorkTag = SnipTag(name: "Work",imageTag: "circle")
        self.modelContext?.insert(newPersonalTag)
        self.modelContext?.insert(newWorkTag)
        self.modelContext?.insert(newNoneTag)
        print("INITIAL TAGS SETUP!")
    }
    
//    func createNewTagAndRelationship(tag: SnipTag, item: SnippetItem){
////        self.modelContext?.insert(tag)
////        item.customTag = tag
//    }
    
    func deleteItems(offsets: IndexSet, snippets:  [SnippetItem]) {
        for index in offsets {
            self.modelContext?.delete(snippets[index])
        }
    }
    
    func createTag(name: String, iconName: String) -> SnipTag {
        print("CREATING NEW TAG: \(name)")
        let newTag = SnipTag(name: name,imageTag: iconName)
        self.modelContext?.insert(newTag)
        print("TAG CREATED: \(name)")
        return newTag
   
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
    
    func createSnippet(_ title: String, content: String, type: SnipType?) -> SnippetItem {
            print("ADD FUNC CALLED!")
            let newItem = SnippetItem(title: title, content: content, type: type ?? .txt)
            self.modelContext?.insert(newItem)
            return newItem
           
//            
//            if validateTagAlreadyExist(tagName: customTag!.name) {
//                print("TAG ALREADY EXIST")
//                customTag?.snippets?.append(newItem)
//            }else {
//                print("CREATING TAG...")
//                createTag(name: customTag!.name, iconName: customTag!.imageTag)
//                customTag?.snippets?.append(newItem)
//            }
            
            
    }
    
//    func addItem(_ title: String, content: String, tag: Tags?, type: SnipType?, customTag: SnipTag?) {
//        if (title.isEmpty && content.isEmpty){
//            print("empty, no add")
//        } else {
//            print("ADD FUNC CALLED!")
//            let newItem = SnippetItem(title: title, content: content, tag: tag, type: type ?? .txt)
//            self.modelContext?.insert(newItem)
//            
//        }
//    }
}

