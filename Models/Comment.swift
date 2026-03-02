//
//  Comment.swift
//  Project 2-3
//
//  Created by Abel Plascencia on 3/1/26.
//

import Foundation
import ParseSwift

struct Comment: ParseObject {

    // Required Parse fields
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    // Your fields
    var text: String?
    var post: Pointer<Post>?
    var user: User?
}
