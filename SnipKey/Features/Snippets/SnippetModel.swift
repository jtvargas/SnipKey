//
//  Item.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import Foundation
import SwiftData

enum SnipType:  String, CaseIterable, Identifiable, Codable  {
    case txt
    case url
    case file
    case image
    
    var id: String { return self.rawValue }
    
    var displayText: String {
        switch self {
        case .txt:
            return "Text"
        case .url:
            return "URL"
        case .file:
            return "File"
        case .image:
            return "Image"
        }
    }
    
    var snipTypeImage: String {
        switch self {
        case .txt:
            return "character.cursor.ibeam"
        case .url:
            return "link.circle"
        case .file:
            return "doc.circle.fill"
        case .image:
            return "photo.circle.fill"
        }
    }
}

enum FileType: String, CaseIterable, Identifiable, Codable   {
    case document, image
    var id: String { return self.rawValue }
    
    var displayText: String {
        switch self {
        case .document:
            return "Document"
        case .image:
            return "Image"
        }
    }
    
    var imageFile: String {
        switch self {
        case .document:
            return "doc.circle.fill"
        case .image:
            return "photo.artframe.circle.fill"
        }
    }
}

enum Tags: String, CaseIterable, Identifiable, Codable   {
    case none, personal, work
    var id: String { return self.rawValue }
    
    var displayText: String {
        switch self {
        case .none:
            return "None"
        case .personal:
            return "Personal"
        case .work:
            return "Work"
        }
    }
    
    var imageTag: String {
        switch self {
        case .none:
            return "tag.slash.fill"
        case .personal:
            return "person.text.rectangle.fill"
        case .work:
            return "case.fill"
        }
    }
}

@Model
final class SnipTag {
    var creationDate: Date = Date.now
    var name: String;
    var imageTag: String
    var id: String
    
    @Relationship(inverse: \SnippetItem.customTag)
    var snippets: [SnippetItem]?
  
    
    
    init(name: String, imageTag: String) {
        self.id = UUID().uuidString 
        self.name = name
        self.imageTag = imageTag
    }
}

//TODO: clean code, separate files, models, and fns...
//TODO: Implement TextField remaining with circle
@Model
final class SnippetFile {
    var id: String
    var fileType: FileType?
    var fileFormatType: String?
    @Attribute(.externalStorage) var fileData: Data?
    
    @Relationship(deleteRule: .cascade, inverse: \SnippetItem.file)
    var snippet: [SnippetItem]?
    
    init(type: FileType = .image, formatType: String) {
        self.id = UUID().uuidString
        self.fileType = type
        self.fileFormatType = formatType
    }
    
}


@Model
final class SnippetItem {
    var creationDate: Date = Date.now
    var updatedDate: Date?
    var id: String
    var title: String
    var content: String
    var customTag: SnipTag?
    var type: SnipType
    var isSecure: Bool = false
    
    var file: SnippetFile?
    
    init(title: String, content: String , type: SnipType, isSecure: Bool) {
        self.id = UUID().uuidString // create SHA-256 more unique id creation
        self.title = title
        self.content = content
        self.type = type
        self.isSecure = isSecure
    }
}
let st = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Etiam lobortis tempor tempus. Nunc elementum sit amet odio ac sollicitudin. Vestibulum velit dolor, commodo eu\n\n\nvelit sit amet, dignissim volutpat risus. Nullam in lacus ante. Vestibulum viverra, eros nec pulvinar finibus, sapien lacus pellentesque nisl, id condimentum orci velit vitae risus. Fusce auctor quam at luctus semper. Pellentesque sed risus mauris. Duis id risus bibendum, scelerisque neque sed, imperdiet diam.Donec gravida massa et mattis volutpat. Proin ut dictum purus, nec varius purus. Maecenas nec porta nibh. Vestibulum faucibus risus molestie mattis tempus. Proin et enim orci. Donec porttitor ante a libero vestibulum placerat. Orci varius natoque penatibus\n et magnis dis parturient montes, nascetur ridiculus mus.Quisque congue congue laoreet. Vestibulum porta dolor velit, id commodo ligula ornare sed. Morbi porta enim enim, non varius est congue eget. Phasellus nisl quam, tincidunt ut feugiat non, molestie ac nisi. Integer tempor diam eget ligula aliquam egestas. Morbi a nibh molestie, bibendum turpis id, condimentum lacus. Proin mollis risus ut neque semper tempor. Integer ut arcu velit. Sed est massa, feugiat quis lobortis vitae, sodales id quam. Nam porttitor mattis turpis eu aliquet.Duis augue tellus, lacinia sit amet libero ut, efficitur tincidunt nulla. Curabitur feugiat bibendum urna ac feugiat. Integer quis leo non est mattis volutpat. Quisque ut massa id nisl scelerisque aliquet ac vitae est. Quisque venenatis a arcu vitae dignissim. Nunc quis sem quis nibh mollis auctor a quis sem. Aenean efficitur eget nisl vitae vestibulum. Fusce suscipit mollis dignissim. In hendrerit auctor pharetra. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Quisque maximus nec est quis scelerisque.Morbi vel aliquet augue. Nulla accumsan dolor mollis, sollicitudin mi a, mattis quam. Nunc felis metus, cursus a dignissim quis, tincidunt non odio. Etiam tempus elementum libero, id dictum odio pellentesque sit amet. Sed ac elit quis leo porttitor ultricies. Morbi laoreet scelerisque justo eu venenatis. Vestibulum in auctor quam. Curabitur felis erat, consequat nec nisl non, viverra efficitur ex. Aliquam erat volutpat. Ut tristique hendrerit varius. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Aliquam lobortis viverra massa in ullamcorper. Etiam cursus, mi ac euismod molestie, elit turpis gravida nulla, ut pellentesque turpis nulla in ante.Aliquam consectetur, urna eget fringilla dignissim, nulla orci fringilla lectus, a gravida arcu neque et turpis. Etiam tincidunt, erat a pharetra aliquam, augue nulla molestie risus, ut ultrices tortor nisl quis sem. Ut rutrum porttitor lobortis. Vestibulum interdum, lectus ut ultricies bibendum, ipsum leo efficitur massa, vel molestie risus nulla nec metus. Aliquam laoreet ex quis placerat tincidunt. Donec mauris nisi, commodo vitae elementum ac, aliquam ut turpis. Praesent eros risus, fermentum eget lacinia at, imperdiet a leo. Nulla sed sapien nec ex facilisis cursus a sed lectus.Vestibulum sed ligula ac sapien ornare suscipit non sed lacus. Vestibulum aliquet mi sed nisi vehicula, sit amet fermentum quam faucibus. Ut sed maximus risus, quis maximus lacus. Praesent fermentum volutpat nisi in tempor. Phasellus molestie congue facilisis. Quisque justo orci, dictum non mi vel, vehicula vehicula ligula. Fusce eget. "
extension SnippetItem {
    static var dummy: SnippetItem {
        .init(title: "Dummy Test", content: st, type: .url, isSecure: false)
    }
}
