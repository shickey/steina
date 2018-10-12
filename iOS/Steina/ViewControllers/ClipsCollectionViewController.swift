//
//  ClipsCollectionViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/14/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

private let reuseIdentifier = "ClipCell"

protocol ClipsCollectionViewControllerDelegate {
    func clipsControllerDidSelect(clipsController: ClipsCollectionViewController, assetId: AssetId)
}

class ClipsCollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var thumbnailView: UIImageView!
    
    override var isSelected: Bool {
        didSet {
            if isSelected {
                self.backgroundColor = UIColor.yellow
            }
            else {
                self.backgroundColor = UIColor.clear
            }
        }  
    }
}

class ClipsCollectionViewController: UICollectionViewController {
    
    var delegate : ClipsCollectionViewControllerDelegate? = nil
    
    var project : Project! = nil
    
    override func viewWillAppear(_ animated: Bool) {
        collectionView?.reloadData()
    }

    // UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return project.clips.count + project.sounds.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ClipsCollectionViewCell
        
        if indexPath.item < project.clips.count {
            // Video Asset
            let clipId = project.clipIds[indexPath.item]
            let clip = project.clips[clipId]!
            
            cell.thumbnailView.image = clip.thumbnail
        }
        else {
            // Audio Asset
            cell.thumbnailView.image = UIImage(named: "audio")!
        }
        
        
        
        if cell.isSelected {
            cell.backgroundColor = UIColor.yellow
        }
        else {
            cell.backgroundColor = UIColor.clear
        }
    
        return cell
    }
    
    // UICollectionViewDelegate
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let d = delegate {
            var assetId : AssetId = ""
            if indexPath.item < project.clips.count {
                // Video Asset
                assetId = project.clipIds[indexPath.item]
            }
            else {
                // Audio Asset
                assetId = project.soundIds[indexPath.item - project.clipIds.count]
            }
            d.clipsControllerDidSelect(clipsController: self, assetId: assetId)
        }
    }

}
