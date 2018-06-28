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
    func clipsControllerDidSelect(clipsController: ClipsCollectionViewController, clipId: VideoClipId)
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
    
    var videoClipIds : [VideoClipId] = []
    var videoClips : [VideoClipId: InMemoryClip] = [:]
    
    override func viewWillAppear(_ animated: Bool) {
        collectionView?.reloadData()
    }

    // UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return videoClipIds.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! ClipsCollectionViewCell
    
        let clipId = videoClipIds[indexPath.item]
        let videoClip = videoClips[clipId]!
        
        let thumb = videoClip.videoClip.thumbnail!
        
        cell.thumbnailView.image = UIImage(cgImage: thumb)
        
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
            let clipId = videoClipIds[indexPath.item]
            d.clipsControllerDidSelect(clipsController: self, clipId: clipId)
        }
    }

}
