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
            visibleRegion = totalRegion
        }
    }
    
    var totalRegion = Region(0, 0)
    var visibleRegion = Region(0, 0)
    
    var pixelsPerFrame : CGFloat      { return bounds.width / CGFloat(visibleRegion.size) }
    var effectiveBounds : CGSize      { return CGSize(width: pixelsPerFrame * CGFloat(totalRegion.size), height: bounds.height) }
    var drawableFrameAspect : CGFloat { return CGFloat(clip.width) / CGFloat(clip.height) }
    var drawableFrameWidth : CGFloat  { return effectiveBounds.height * drawableFrameAspect }
    var drawableFrameHeight : CGFloat { return effectiveBounds.height }
    var numFittableFrames : Int {
        let minFittableFrames = Int(bounds.width / drawableFrameWidth)
        let boundsRatio = effectiveBounds.width / bounds.width
        let powerOfTwo = largestPowerOfTwoLessThanOrEqualTo(UInt(boundsRatio))
        
        return minFittableFrames * powerOfTwo
    }
    
    var imageCache : [UIImage?]! = nil
    
    func imageForFrame(_ frame: Int) -> UIImage {
        if let img = imageCache[frame] { return img }
        
        let image = createImageForClip(clip, frame: frame, inverted: true)
        imageCache[frame] = image
        return image
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!
        
        let totalFrameWidth = effectiveBounds.width / CGFloat(numFittableFrames)
        let framesToDraw = Int(ceil(bounds.width / totalFrameWidth))
        let frameIncrement = CGFloat(clip.frames) / CGFloat(numFittableFrames - 1)
        let firstFrameToDraw = Int(CGFloat(Int(CGFloat(visibleRegion.start) / frameIncrement)) * frameIncrement)
        var xOffset = -(pixelsPerFrame * CGFloat(visibleRegion.start - firstFrameToDraw))
        
        let drawFrameOffset = (totalFrameWidth - drawableFrameWidth) / 2.0
        for i in 0..<framesToDraw {
            let drawingFrame = clamp(Int(CGFloat(i) * frameIncrement) + firstFrameToDraw, 0, Int(clip.frames) - 1)
            let image = imageForFrame(drawingFrame)
            let rect = CGRect(x: xOffset + drawFrameOffset, y: 0, width: drawableFrameWidth, height: drawableFrameHeight).insetBy(dx: xPaddingInPixels, dy: xPaddingInPixels / drawableFrameAspect)
            context.draw(image.cgImage!, in: rect)
            xOffset += totalFrameWidth
        }
    }
    
}

class VideoEditorViewController: UIViewController, AssetEditorViewDelegate {
    
    var clip : Clip! = nil
    
    @IBOutlet weak var clipImageView: UIImageView!
    @IBOutlet weak var videoTimelineView: VideoTimelineView!
    @IBOutlet weak var assetEditorView: AssetEditorView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var deleteMarkerButton: UIButton!
    @IBOutlet weak var addMarkerButton: UIButton!
    @IBOutlet weak var rerecordButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let project = Project(id: UUID())
        let uuid = UUID()
        
        clip = Clip(id: uuid, project: project)
        let clipUrl = Bundle.main.url(forResource: "leaves", withExtension: "svc")!
        let clipData = try! Data(contentsOf: clipUrl)
        deserializeClip(clip, clipData)
        
        videoTimelineView.clip = clip
        
        clipImageView.image = createImageForClip(clip, frame: 0)
        
        assetEditorView.delegate = self
    }
    
    @IBAction func closeButtonTapped(_ sender: Any) {
//        if sound.length == 0 {
//            self.presentingViewController!.dismiss(animated: true, completion: nil)
//        }
//        else {
//            let alert = UIAlertController(title: "Discard audio?", message: "Are you sure you want to discard this audio clip?", preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "Discard and Exit", style: .default, handler: { (_) in
//                self.presentingViewController!.dismiss(animated: true, completion: nil)
//            }))
//            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
//            self.present(alert, animated: true, completion: nil)
//        }
    }
    
    @IBAction func playPauseButtonTapped(_ sender: Any) {
//        if playing {
//            stopSound(playingSoundId)
//            playing = false
//        }
//        else {
//            var playRange = EditorRange(assetEditorView.playhead, assetEditorView.trimmedRange.end)
//            if assetEditorView.playhead == assetEditorView.trimmedRange.end {
//                playRange = assetEditorView.trimmedRange
//            }
//            playing = true
//            playingSoundId = playSound(sound, playRange, looped: false) { stoppedId in
//                if stoppedId == self.playingSoundId {
//                    self.playingSoundId = nil
//                    self.playing = false
//                }
//            }
//        }
    }
    
    @IBAction func addMarkerButtonTapped(_ sender: Any) {
//        assetEditorView.createMarkerAtPlayhead()
    }
    
    @IBAction func deleteMarkerButtonTapped(_ sender: Any) {
//        if markerSelected {
//            assetEditorView.deleteSelectedMarker()
//        }
    }
    
    @IBAction func saveButtonTapped(_ sender: Any) {
//        if playing {
//            stopSound(playingSoundId)
//        }
//        sound.markers = assetEditorView.markers
//        sound.trimmedRegion = assetEditorView.trimmedRange
//        sound.thumbnail = generateThumbnailForSound(sound)
//        if let d = delegate {
//            d.audioCaptureViewControllerDidCreateSound(audioView.sound!)
//        }
//        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func rerecordButtonTapped(_ sender: Any) {
//        if playing {
//            stopSound(playingSoundId)
//        }
//        sound = Sound(bytesPerSample: 2)
//        audioView.sound = sound
//        
//        assetEditorView.markers = []
//        assetEditorView.totalRange = EditorRange(0, 0)
//        assetEditorView.trimmedRange = EditorRange(0, 0)
//        assetEditorView.visibleRange = EditorRange(0, 0)
//        assetEditorView.showMarkers = false
//        assetEditorView.showPlayhead = false
//        assetEditorView.isUserInteractionEnabled = false
//        
//        markerSelected = false
//        recordButton.isHidden = false
//        playPauseButton.isHidden = true
//        addMarkerButton.isHidden = true
//        deleteMarkerButton.isHidden = true
//        rerecordButton.isHidden = true
//        saveButton.isHidden = true
    }
    
    func totalRange(for: AssetEditorView) -> EditorRange {
        return EditorRange(0, Int(clip.frames - 1))
    }
    
    func assetEditorTappedPlayButton(for: AssetEditorView, range: EditorRange) {
        
    }
    
    func assetEditorReleasedPlayButton(for: AssetEditorView, range: EditorRange) {
        
    }
    
    func assetEditorMovedToRange(editor: AssetEditorView, range: EditorRange) {
        videoTimelineView.visibleRegion = range
        videoTimelineView.setNeedsDisplay()
    }
    
    func assetEditorDidSelect(editor: AssetEditorView, marker: Marker, at index: Int) {
        
    }
    
    func assetEditorDidDeselect(editor: AssetEditorView, marker: Marker, at index: Int) {
        
    }

}
