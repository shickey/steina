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

class ClipsCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    
    var delegate : ClipsCollectionViewControllerDelegate? = nil
    
    var project : Project! = nil
    
    override func viewWillAppear(_ animated: Bool) {
        collectionView?.reloadData()
    }
    
    func selectAsset(_ assetId: AssetId) {
        if let idx = project.clipIds.firstIndex(of: assetId) {
            let indexPath = IndexPath(item: idx, section: 0)
            collectionView!.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
        }
        else if let idx = project.soundIds.firstIndex(of: assetId) {
            let indexPath = IndexPath(item: idx, section: 1)
            collectionView!.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
        }
    }

    // UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return project.clips.count
        }
        else {
            return project.sounds.count
        }
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ClipsCollectionViewCell
        
        if indexPath.section == 0 {
            // Video Asset
            let clipId = project.clipIds[indexPath.item]
            let clip = project.clips[clipId]!
            
            cell.thumbnailView.image = clip.thumbnail
        }
        else {
            // Audio Asset
            let soundId = project.soundIds[indexPath.item]
            let sound = project.sounds[soundId]!
            cell.thumbnailView.image = sound.thumbnail
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
            if indexPath.section == 0 {
                // Video Asset
                assetId = project.clipIds[indexPath.item]
            }
            else {
                // Audio Asset
                assetId = project.soundIds[indexPath.item]
            }
            d.clipsControllerDidSelect(clipsController: self, assetId: assetId)
        }
    }
    
    // UICollectionViewDelegateFlowLayout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if indexPath.section == 0 {
            return CGSize(width: 100, height: 75)
        }
        else {
            return CGSize(width: 200, height: 75)
        }
    }

}
