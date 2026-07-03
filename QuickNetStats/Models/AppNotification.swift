//
//  AppNotification.swift
//  QuickNetStats
//
//  Created by Federico Imberti on 2025-12-23.
//

import Foundation

class AppNotification: Identifiable, Comparable {

    var id: UUID
    var title: String
    var body: String
    var priority: Int
    var created: Date

    init(title: String, body: String, priority: Int, created: Date) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.priority = priority
        self.created = created
    }

    static func < (lhs: AppNotification, rhs: AppNotification) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.created != rhs.created {
            return lhs.created < rhs.created
        }
        return lhs.title < rhs.title
    }

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.priority == rhs.priority && lhs.created == rhs.created && lhs.title == rhs.title
    }

}

class InternetStatusNotification: AppNotification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 1, created: created)
    }
}

class InterfaceChangesStatusNotification: AppNotification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 2, created: created)
    }
}

class LinkQualityStatusNotification: AppNotification {
    init(title: String, body: String, created: Date) {
        super.init(title: title, body: body, priority: 3, created: created)
    }
}
