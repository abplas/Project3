import Foundation

import ParseSwift


struct Post: ParseObject {
    
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?
    var locationName: String?

    var caption: String?
    var user: User?
    var imageFile: ParseFile?
    
}
