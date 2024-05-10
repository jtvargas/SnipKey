//
//  TestSplitView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 5/10/24.
//

import SwiftUI

struct Request: Identifiable, Hashable {
    let id = UUID()
    let url: String
}

struct TestSplitView: View {
    @State private var selectedRequest: Request?
    @State private var requests = [
        Request(url: "https://example.com"),
        Request(url: "https://httpbin.org/")
    ]
    
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(
                requests,
                selection: $selectedRequest
            ) { request in
                NavigationLink(request.url, value: request)
            }
            .navigationTitle("Requests")
            .toolbar {
                Button.init(action: {
                    // add request here
                }) {
                    Label("Add Request", systemImage: "plus")
                }
            }
        } detail: {
//            ZStack {
                if let request = selectedRequest {
                    VStack(spacing: 40) {
                        Text("Request URL: \(request.url)")
                        Button("Send Request") {
                            // send request here
                        }
                        Button("Delete Request", role: .destructive) {
                            requests.removeAll { $0.id == request.id }
                            selectedRequest = nil
                            
                            columnVisibility = .all
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Nothing Selected")
                }
//            }
        }
    }
}



#Preview {
    TestSplitView()
}
