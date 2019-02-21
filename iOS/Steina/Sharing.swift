//
//  Sharing.swift
//  Steina
//
//  Created by Sean Hickey on 2/20/19.
//  Copyright © 2019 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

let BricoleurProjectUti = "edu.mit.media.llk.Bricoleur.bric"

class ProjectItemProvider : UIActivityItemProvider {
    
    var project : Project! = nil
    
    init(project newProject: Project) {
        super.init(placeholderItem: newProject.jsonUrl)
        project = newProject
    }
    
    override func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivityType?) -> String {
        return BricoleurProjectUti
    }
    
    override var item: Any {
        let tempFolder = DATA_DIRECTORY_URL.appendingPathComponent("Outbox")
        try! FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true, attributes: nil)
        let zipFileUrl = tempFolder.appendingPathComponent("MyBricoleurProject.bric")
        let success = SSZipArchive.createZipFile(atPath: zipFileUrl.path, withContentsOfDirectory: project.projectFolderUrl.path, keepParentDirectory: true)
        return zipFileUrl
    }
    
}
