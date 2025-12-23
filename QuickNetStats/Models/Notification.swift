//
//  Notification.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-23.
//

import Foundation

class Notification: Identifiable, Comparable {

    var id:UUID
    var title:String
    var body:String
    var priority:Int
    var created:Date
    
    init(title: String, body: String, priority: Int, created: Date) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.priority = priority
        self.created = created
    }
    
    static func < (lhs: Notification, rhs: Notification) -> Bool {
        lhs.priority < rhs.priority && lhs.created < rhs.created && lhs.title < rhs.title
    }
    
    static func == (lhs: Notification, rhs: Notification) -> Bool {
        lhs.id == rhs.id
    }

}

class InternetStatusNotification: Notification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 1, created: created)
    }
}

class InterfaceChangesStatusNotification: Notification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 2, created: created)
    }
}

class LinkQualityStatusNotification: Notification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 3, created: created)
    }
}
