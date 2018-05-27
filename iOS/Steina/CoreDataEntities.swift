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
    
    func createClip() -> Clip {
        let clip = Clip(context: self.managedObjectContext!)
        clip.id = UUID()
        self.addToClips(clip)
        return clip
    }
    
    var assetsDirectory : URL {
        get {
            let docsDirectoryUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
            let assetsUrl = docsDirectoryUrl.appendingPathComponent(self.id!.uuidString, isDirectory: true)
            try! FileManager.default.createDirectory(at: assetsUrl, withIntermediateDirectories: true, attributes: nil)
            return assetsUrl
        }
    }
    
}

extension Clip {
    
    var assetUrl : URL {
        get {
            return project!.assetsDirectory.appendingPathComponent("\(self.id!.uuidString).svc")
        }
    }
    
}
