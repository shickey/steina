//
//  VideoEditorViewController.swift
//  Steina
//
//  Created by Sean Hickey on 2/26/19.
//  Copyright © 2019 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

class VideoTimelineView : UIView {
    
    let xPaddingInPixels : CGFloat = 4.0
    
    var clip : Clip! = nil {
        didSet {
            imageCache = Array<UIImage?>(repeating: nil, count: Int(clip.frames))
            totalRegion = Region(0, Int(clip.frames) - 1)
            visibleRegion = VisibleRange(CGFloat(totalRegion.start), CGFloat(totalRegion.end))
        }
    }
    
    var totalRegion = Region(0, 0)
    var visibleRegion = VisibleRange(0, 0)
    
    var pixelsPerFrame : CGFloat      { return bounds.width / visibleRegion.size }
    var effectiveBounds : CGSize      { return CGSize(width: pixelsPerFrame * CGFloat(totalRegion.size), height: bounds.height) }
    var drawableFrameAspect : CGFloat { return CGFloat(clip.width) / CGFloat(clip.height) }
    var drawableFrameHeight : CGFloat { return bounds.height }
    var drawableFrameWidth : CGFloat  { return bounds.height * drawableFrameAspect }
    
    var imageCache : [UIImage?]! = nil
    
    func imageForFrame(_ frame: Int) -> UIImage {
        if let img = imageCache[frame] { return img }
        
        let image = createImageForClip(clip, frame: frame, inverted: true)
        imageCache[frame] = image
        return image
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!
        
        // Determine buckets
        let maxFittableFrames = Int(effectiveBounds.width / (drawableFrameHeight * drawableFrameAspect))
        let minFrameSize = CGFloat(clip.frames) / CGFloat(maxFittableFrames)
        let largestPowerOfTwoLessThanMinFrameSize = largestPowerOfTwoLessThanOrEqualTo(UInt(minFrameSize))
        var framesPerBucket = 1
        if largestPowerOfTwoLessThanMinFrameSize != 0 {
            framesPerBucket = largestPowerOfTwoLessThanMinFrameSize << 1
        }
        
        let bucketWidth = pixelsPerFrame * CGFloat(framesPerBucket)
        
        let firstBucketToDraw = Int(visibleRegion.start / CGFloat(framesPerBucket)) * framesPerBucket
        var xOffset = -(pixelsPerFrame * fmod(visibleRegion.start, CGFloat(framesPerBucket)))
        let numBucketsToDraw = Int(ceil((bounds.width - xOffset) / (CGFloat(framesPerBucket) * pixelsPerFrame)))
        for i in 0..<numBucketsToDraw {
            
            let drawingFrame = (i * framesPerBucket) + firstBucketToDraw
            let image = imageForFrame(drawingFrame)
            let rect = CGRect(x: xOffset, y: 0, width: drawableFrameWidth, height: drawableFrameHeight).insetBy(dx: xPaddingInPixels, dy: xPaddingInPixels / drawableFrameAspect)
            context.draw(image.cgImage!, in: rect)
            
            xOffset += bucketWidth
        }
    }
    
}

protocol VideoEditorViewControllerDelegate {
    func videoEditorSavedClip(editor: VideoEditorViewController, clip: Clip)
}

class VideoEditorViewController: UIViewController, AssetEditorViewDelegate {
    
    var delegate : VideoEditorViewControllerDelegate? = nil
    
    var clip : Clip! = nil
    
    var markerSelected = false {
        didSet {
            if markerSelected {
                let deleteMarkerImage = UIImage(named: "editor-delete-marker")!
                addDeleteMarkerButton.setImage(deleteMarkerImage, for: .normal) 
            }
            else {
                let addMarkerImage = UIImage(named: "editor-add-marker")!
                addDeleteMarkerButton.setImage(addMarkerImage, for: .normal)
            }
        }
    }
    
    var displayLink : CADisplayLink! = nil
    
    var playing = false {
        didSet {
            if playing {
                let pauseImage = UIImage(named: "editor-pause")!
                playPauseButton.setImage(pauseImage, for: .normal)
            }
            else {
                let playImage = UIImage(named: "editor-play")!
                playPauseButton.setImage(playImage, for: .normal)
            }
        }
    }
    var playLooped = false
    var currentPlayingRegion : Region<Int>! = nil
    var currentPlayingFrame = 0
    
    @IBOutlet weak var clipImageView: UIImageView!
    @IBOutlet weak var videoTimelineView: VideoTimelineView!
    @IBOutlet weak var assetEditorView: AssetEditorView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var addDeleteMarkerButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        videoTimelineView.clip = clip
        clipImageView.image = createImageForClip(clip, frame: 0)
        
        assetEditorView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startDisplayLink()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        stopDisplayLink()
        super.viewDidDisappear(animated)
    }
    
    func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .current, forMode: .defaultRunLoopMode)
    }
    
    func stopDisplayLink() {
        displayLink.remove(from: .current, forMode: .defaultRunLoopMode)
    }
    
    @objc
    func tick(_ sender: CADisplayLink) {
        if playing {
            clipImageView.image = createImageForClip(clip, frame: currentPlayingFrame)
            assetEditorView.updatePlayhead(currentPlayingFrame)
            
            if currentPlayingFrame == currentPlayingRegion.end {
                if playLooped {
                    currentPlayingFrame = currentPlayingRegion.start
                }
                else {
                    playing = false
                    currentPlayingRegion = nil
                }
            }
            else {
                currentPlayingFrame += 1
            }
        }
    }
    
    @IBAction func closeButtonTapped(_ sender: Any) {
        let alert = UIAlertController(title: "Discard Clip?", message: "Do you want to discard this video clip?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Discard and Exit", style: .default, handler: { (_) in
            self.presentingViewController!.presentingViewController!.dismiss(animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Discard and Rerecord", style: .default, handler: { (_) in
            self.presentingViewController!.dismiss(animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func playPauseButtonTapped(_ sender: Any) {
        if playing {
            playing = false
        }
        else {
            var playRange = EditorRange(assetEditorView.playhead, assetEditorView.trimmedRange.end)
            if assetEditorView.playhead == assetEditorView.trimmedRange.end {
                playRange = assetEditorView.trimmedRange
                currentPlayingFrame = playRange.start
            }
            currentPlayingRegion = playRange
            playLooped = false
            playing = true
        }
    }
    
    @IBAction func addRemoveMarkerButtonTapped(_ sender: Any) {
        if markerSelected {
            assetEditorView.deleteSelectedMarker()
        }
        else {
            assetEditorView.createMarkerAtPlayhead()
        }
    }
    
    @IBAction func saveButtonTapped(_ sender: Any) {
        if playing {
            playing = false
        }
//        sound.markers = assetEditorView.markers
//        sound.trimmedRegion = assetEditorView.trimmedRange
//        sound.thumbnail = generateThumbnailForSound(sound)
        if let del = delegate {
            del.videoEditorSavedClip(editor: self, clip: clip)
        }
    }
    
    func totalRange(for: AssetEditorView) -> EditorRange {
        return EditorRange(0, Int(clip.frames - 1))
    }
    
    func assetEditorTappedPlayButton(editor: AssetEditorView, range: EditorRange) {
        playPauseButton.isEnabled = false
        saveButton.isEnabled = false
        closeButton.isEnabled = false
        
        currentPlayingRegion = range
        currentPlayingFrame = range.start
        playLooped = true
        playing = true
    }
    
    func assetEditorReleasedPlayButton(editor: AssetEditorView, range: EditorRange) {
        playing = false
        playLooped = false
        currentPlayingRegion = nil
        
        playPauseButton.isEnabled = true
        saveButton.isEnabled = true
        closeButton.isEnabled = true
    }
    
    func assetEditorMovedToVisibleRange(editor: AssetEditorView, range: VisibleRange) {
        videoTimelineView.visibleRegion = range
        videoTimelineView.setNeedsDisplay()
    }
    
    func assetEditorDidSelect(editor: AssetEditorView, marker: Marker, at index: Int) {
        markerSelected = true
    }
    
    func assetEditorDidDeselect(editor: AssetEditorView, marker: Marker, at index: Int) {
        markerSelected = false
    }
    
    func assetEditorPlayheadMoved(editor: AssetEditorView, to playhead: Int) {
        currentPlayingFrame = playhead
        clipImageView.image = createImageForClip(clip, frame: playhead)
    }
    
    func assetEditorBeganDraggingMarkerOrTrimmer(editor: AssetEditorView) {
        playPauseButton.isEnabled = false
        saveButton.isEnabled = false
        closeButton.isEnabled = false
        addDeleteMarkerButton.isEnabled = false
    }
    
    func assetEditorStoppedDraggingMarkerOrTrimmer(editor: AssetEditorView) {
        playPauseButton.isEnabled = true
        saveButton.isEnabled = true
        closeButton.isEnabled = true
        addDeleteMarkerButton.isEnabled = true
    }

}
