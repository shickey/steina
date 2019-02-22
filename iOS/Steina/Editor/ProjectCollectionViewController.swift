//
//  ProjectCollectionViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/27/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

private let projectReuseIdentifier = "ProjectCell"
private let addReuseIdentifier = "AddProjectCell"

class ProjectCell : UICollectionViewCell {
    @IBOutlet weak var projectThumbnail: UIImageView!
}

class AddProjectCell : UICollectionViewCell {}

class EqualSpacingFlowLayout : UICollectionViewFlowLayout {
    
    override func prepare() {
        super.prepare()
        
        let itemsPerRow = Int(collectionViewContentSize.width) / Int(itemSize.width)
        let leftoverPixels = Int(collectionViewContentSize.width) % Int(itemSize.width)
        
        let spacing = CGFloat(Int(CGFloat(leftoverPixels) / CGFloat(itemsPerRow + 1)))
        
        sectionInset = UIEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        minimumLineSpacing = spacing
        minimumInteritemSpacing = spacing
    }
    
}

class ProjectCollectionViewController : UICollectionViewController {
    
    var projects : NSMutableArray! = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        projects = SteinaStore.projects
        
        NotificationCenter.default.addObserver(self, selector: #selector(importedProjectNotification), name: ImportedProjectNotification.name, object: nil)
    }
    
    @objc
    func importedProjectNotification(notification: Notification) {
        collectionView?.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        collectionView?.reloadData()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let dest = segue.destination as! EditorViewController
        if let _ = sender as? AddProjectCell {
            let project = SteinaStore.insertProject()
            dest.project = project
        }
        else if let projectCell = sender as? ProjectCell {
            let indexPath = collectionView!.indexPath(for: projectCell)!
            dest.project = (projects[indexPath.item - 1] as! Project)
        }
        
    }

    // MARK: UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return projects.count + 1
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {
            return collectionView.dequeueReusableCell(withReuseIdentifier: addReuseIdentifier, for: indexPath) as! AddProjectCell
        }
        
        let project = projects[indexPath.item - 1] as! Project
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: projectReuseIdentifier, for: indexPath) as! ProjectCell
        cell.projectThumbnail.image = project.thumbnail
    
        return cell
    }

}
