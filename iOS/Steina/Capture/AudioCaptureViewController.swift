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

class AudioCaptureViewController: UIViewController, AssetEditorViewDelegate {
    
    var delegate : AudioCaptureViewControllerDelegate? = nil
    
    var sound : Sound! = nil
    var playingSoundId : PlayingSoundId! = nil
    var recording = false
    
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
    
    var markerSelected = false {
        didSet {
            if markerSelected {
                addMarkerButton.isEnabled = false
                deleteMarkerButton.isEnabled = true
            }
            else {
                addMarkerButton.isEnabled = true
                deleteMarkerButton.isEnabled = false
            }
        }
    }
    
    @IBOutlet weak var assetEditorView: AssetEditorView!
    @IBOutlet weak var audioView: AudioView!
    
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var deleteMarkerButton: UIButton!
    @IBOutlet weak var addMarkerButton: UIButton!
    @IBOutlet weak var rerecordButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        changeAudioOutputSource(.ios)
        
        audioRenderContext.callback = { (updatedPlayheads) in
            if let _ = self.playingSoundId, let newPlayhead = updatedPlayheads[self.playingSoundId] {
                self.assetEditorView.updatePlayhead(newPlayhead)
            }
        }
        
        if (sound == nil) {
            sound = Sound(bytesPerSample: 2)
        }
        
        audioView.sound = sound
        
        assetEditorView.delegate = self
        assetEditorView.markers = []
        assetEditorView.showMarkers = false
        assetEditorView.showPlayhead = false
    }
    
    @IBAction func closeButtonTapped(_ sender: Any) {
        if sound.length == 0 {
            self.presentingViewController!.dismiss(animated: true, completion: nil)
        }
        else {
            let alert = UIAlertController(title: "Discard audio?", message: "Are you sure you want to discard this audio clip?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Discard and Exit", style: .default, handler: { (_) in
                self.presentingViewController!.dismiss(animated: true, completion: nil)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @IBAction func recordingButtonTapped(_ sender: Any) {
        if !recording {
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
                self.recordButton.isHidden = true
                self.playPauseButton.isHidden = false
                self.addMarkerButton.isHidden = false
                self.deleteMarkerButton.isHidden = false
                self.rerecordButton.isHidden = false
                self.saveButton.isHidden = false
                self.assetEditorView.totalRange = self.audioView.sampleWindow
                self.assetEditorView.trimmedRange = self.audioView.sampleWindow
                self.assetEditorView.visibleRange = self.audioView.sampleWindow
                self.assetEditorView.playhead = 0
                self.assetEditorView.showMarkers = true
                self.assetEditorView.showPlayhead = true
                self.assetEditorView.isUserInteractionEnabled = true
            }
        }
    }
    
    @IBAction func playPauseButtonTapped(_ sender: Any) {
        if playing {
            stopSound(playingSoundId)
            playing = false
        }
        else {
            var playRange = EditorRange(assetEditorView.playhead, assetEditorView.trimmedRange.end)
            if assetEditorView.playhead == assetEditorView.trimmedRange.end {
                playRange = assetEditorView.trimmedRange
            }
            playing = true
            playingSoundId = playSound(sound, playRange, looped: false) { stoppedId in
                if stoppedId == self.playingSoundId {
                    self.playingSoundId = nil
                    self.playing = false
                }
            }
        }
    }
    
    @IBAction func addMarkerButtonTapped(_ sender: Any) {
        assetEditorView.createMarkerAtPlayhead()
    }
    
    @IBAction func deleteMarkerButtonTapped(_ sender: Any) {
        if markerSelected {
            assetEditorView.deleteSelectedMarker()
        }
    }
    
    @IBAction func saveButtonTapped(_ sender: Any) {
        if playing {
            stopSound(playingSoundId)
        }
        sound.markers = assetEditorView.markers
        if let d = delegate {
            d.audioCaptureViewControllerDidCreateSound(audioView.sound!)
        }
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func rerecordButtonTapped(_ sender: Any) {
        if playing {
            stopSound(playingSoundId)
        }
        sound = Sound(bytesPerSample: 2)
        audioView.sound = sound

        assetEditorView.markers = []
        assetEditorView.totalRange = EditorRange(0, 0)
        assetEditorView.trimmedRange = EditorRange(0, 0)
        assetEditorView.visibleRange = EditorRange(0, 0)
        assetEditorView.showMarkers = false
        assetEditorView.showPlayhead = false
        assetEditorView.isUserInteractionEnabled = false
        
        markerSelected = false
        recordButton.isHidden = false
        playPauseButton.isHidden = true
        addMarkerButton.isHidden = true
        deleteMarkerButton.isHidden = true
        rerecordButton.isHidden = true
        saveButton.isHidden = true
    }
    
    func totalRange(for: AssetEditorView) -> EditorRange {
        return EditorRange(0, sound.length)
    }
    
    func assetEditorTappedPlayButton(for: AssetEditorView, range: EditorRange) {
        rerecordButton.isEnabled = false
        playPauseButton.isEnabled = false
        saveButton.isEnabled = false
        closeButton.isEnabled = false
        
        if playing {
            stopSound(playingSoundId)
        }
        let sampleRange = SampleRange(range.start, range.end)
        playingSoundId = playSound(sound, sampleRange, looped: true)
        playing = true
    }
    
    func assetEditorReleasedPlayButton(for: AssetEditorView, range: EditorRange) {
        stopSound(playingSoundId)
        playing = false
        playingSoundId = nil
        rerecordButton.isEnabled = true
        playPauseButton.isEnabled = true
        saveButton.isEnabled = true
        closeButton.isEnabled = true
    }
    
    func assetEditorMovedToRange(editor: AssetEditorView, range: EditorRange) {
        audioView.sampleWindow = range
        audioView.setNeedsDisplay()
    }
    
    func assetEditorDidSelect(editor: AssetEditorView, marker: Marker, at: Int) {
        markerSelected = true
    }
    
    func assetEditorDidDeselect(editor: AssetEditorView, marker: Marker, at: Int) {
        markerSelected = false
    }
    
}
