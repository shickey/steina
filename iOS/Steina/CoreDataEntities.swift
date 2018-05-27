//
//  CoreDataEntities.swift
//  Steina
//
//  Created by Sean Hickey on 5/27/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import CoreData

// NSManagedObject Extensions
extension Project {
    
    static func create(context moc: NSManagedObjectContext) -> Project {
        let project = self.init(context: moc)
        project.id = UUID()
        return project
    }
    
    func createClip(context moc: NSManagedObjectContext) -> Clip {
        let clip = Clip(context: moc)
        self.addToClips(clip)
        return clip
    }
    
    var mediaDirectory : URL {
        get {
            let docsDirectoryUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
            let mediaUrl = docsDirectoryUrl.appendingPathComponent(self.id!.uuidString, isDirectory: true)
            try! FileManager.default.createDirectory(at: mediaUrl, withIntermediateDirectories: true, attributes: nil)
            return mediaUrl
        }
    }
    
}

extension Clip {
    
}
