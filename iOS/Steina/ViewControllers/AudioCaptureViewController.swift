//
//  AudioCaptureViewController.swift
//  Steina
//
//  Created by Sean Hickey on 8/31/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

class AudioView : UIView {
    var sound : Sound? {
        didSet {
            if let s = sound {
                sampleWindow = SampleRange(0, s.length)
                isUserInteractionEnabled = true
            }
            else {
                isUserInteractionEnabled = false
            }
            setNeedsDisplay()
        }
    }
    
    var sampleWindow : SampleRange = SampleRange(0, 0)
    
    var samplesPerPixel : Int {
        return Int((CGFloat(sampleWindow.size) / bounds.size.width))
    }
    
    override func draw(_ rect: CGRect) {
        
        if (sound == nil) { return }
        
        // Draw the waveform
        let nsData = sound!.samples as NSData
        let data = nsData.bytes.bindMemory(to: Int16.self, capacity: sound!.length)
        
        let context = UIGraphicsGetCurrentContext()!
        var currentX = CGFloat(0.0)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(1.0)
        
        // For each pixel in the horizontal direction, draw a vertical line
        // between the maximum and minimum amplitude of that part of the waveform
        var currentSampleIdx = sampleWindow.start
        for _ in 0..<Int(rect.size.width) {
            var min : Int16 = 0
            var max : Int16 = 0
            for sampleIdx in currentSampleIdx..<currentSampleIdx + samplesPerPixel {
                let sample = data[sampleIdx];
                if sample < min {
                    min = sample
                }
                else if sample > max {
                    max = sample
                }
            }
            context.beginPath()
            let minY = (rect.size.height / 2.0) - (CGFloat(min) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
            let maxY = (rect.size.height / 2.0) - (CGFloat(max) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
            
            context.move(to: CGPoint(x: currentX, y: minY))
            context.addLine(to: CGPoint(x: currentX, y: maxY))
            context.strokePath()
            currentSampleIdx += samplesPerPixel
            currentX += 1.0
        }
    }
}

protocol AudioCaptureViewControllerDelegate {
    func audioCaptureViewControllerDidCreateSound(_ sound: Sound)
}

class AudioCaptureViewController: UIViewController, AssetEditorViewDataSource {
    
    var delegate : AudioCaptureViewControllerDelegate? = nil
    
    var sound : Sound! = nil
    var playingSoundId : PlayingSoundId! = nil
    var recording = false
    
    @IBOutlet weak var assetEditorView: AssetEditorView!
    @IBOutlet weak var audioView: AudioView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        changeAudioOutputSource(.ios)
        
        audioRenderContext.callback = { (updatedPlayheads) in
            if let _ = self.playingSoundId, let newPlayhead = updatedPlayheads[self.playingSoundId] {
                self.assetEditorView.playhead = newPlayhead
            }
        }
        
        if (sound == nil) {
            sound = Sound(bytesPerSample: 2)
        }
        
        audioView.sound = sound
        
        assetEditorView.dataSource = self
        assetEditorView.markers = [] //[100000, 500000, 1000000]
    }
    
    @IBAction func closeButtonTapped(_ sender: Any) {
        sound.markers = assetEditorView.markers
        if let d = delegate {
            d.audioCaptureViewControllerDidCreateSound(audioView.sound!)
        }
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func recordingButtonTapped(_ sender: Any) {
        if !recording {
            assetEditorView.isUserInteractionEnabled = false
            assetEditorView.markers = []
            assetEditorView.showMarkers = false
            assetEditorView.showPlayhead = false
            beginRecordingAudio() { (recordingBuffer) in
                self.sound.samples = Data(bytes: recordingBuffer.data, count: recordingBuffer.samples * 2)
                self.audioView.sampleWindow = SampleRange(0, self.sound.length)
                self.audioView.setNeedsDisplay()
            }
            recording = true
        }
        else {
            stopRecordingAudio() { recordingBuffer in
                self.sound.samples = Data(bytes: recordingBuffer.data, count: recordingBuffer.samples * 2)
                self.recording = false
                self.assetEditorView.unitRange = self.audioView.sampleWindow
                self.assetEditorView.visibleRange = self.audioView.sampleWindow
                self.assetEditorView.playhead = 0
                self.assetEditorView.showMarkers = true
                self.assetEditorView.showPlayhead = true
                self.assetEditorView.isUserInteractionEnabled = true
            }
        }
    }
    
    func totalRange(for: AssetEditorView) -> EditorRange {
        return EditorRange(0, sound.length)
    }
    
    func drawDataView(for editorView: AssetEditorView, range: EditorRange, in context: CGContext, rect: CGRect) {
        if (sound == nil) { return }
        
        // Fill the background
        context.setFillColor(red: 90.0 / 255.0, green: 125.0 / 255.0, blue: 199.0 / 255.0, alpha: 1.0)
        context.fill(rect)
        
        // Draw the waveform
        let nsData = sound!.samples as NSData
        let data = nsData.bytes.bindMemory(to: Int16.self, capacity: sound!.length)
        
        var currentX = CGFloat(0.0)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(1.0)
        
        // For each pixel in the horizontal direction, draw a vertical line
        // between the maximum and minimum amplitude of that part of the waveform
        var currentSampleIdx = range.start
        for _ in 0..<Int(rect.size.width) {
            var min : Int16 = 0
            var max : Int16 = 0
            for sampleIdx in currentSampleIdx..<currentSampleIdx + Int(editorView.unitsPerPixel) {
                let sample = data[sampleIdx];
                if sample < min {
                    min = sample
                }
                else if sample > max {
                    max = sample
                }
            }
            context.beginPath()
            let minY = rect.origin.y + (rect.size.height / 2.0) - (CGFloat(min) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
            let maxY = rect.origin.y + (rect.size.height / 2.0) - (CGFloat(max) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
            
            context.move(to: CGPoint(x: currentX, y: minY))
            context.addLine(to: CGPoint(x: currentX, y: maxY))
            context.strokePath()
            currentSampleIdx += Int(editorView.unitsPerPixel)
            currentX += 1.0
        }
    }
    
    func assetEditorTappedPlayButton(for: AssetEditorView, range: EditorRange) {
        let sampleRange = SampleRange(range.start, range.end)
        playingSoundId = playSound(sound, sampleRange, looped: true)
    }
    
    func assetEditorReleasedPlayButton(for: AssetEditorView, range: EditorRange) {
        stopSound(playingSoundId)
        playingSoundId = nil
    }
    
    func assetEditorMovedToRange(editor: AssetEditorView, range: EditorRange) {
        audioView.sampleWindow = range
        audioView.setNeedsDisplay()
    }
    
}
