//
//  AudioCaptureViewController.swift
//  Steina
//
//  Created by Sean Hickey on 8/31/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import AVKit

class AudioView : UIView {
    
    var markers = [144336, 250000, 500000, 1000000, 1350000] // In samples
    
    var dragging = false
    var draggingIdx : Int! = nil
    
    var panStartSample : Int! = nil
    var panning = false
    
    var sampleWindowStart = 0
    var sampleWindowEnd = 0
    
    var longPressRecognizer : UILongPressGestureRecognizer! = nil
    
    var totalSamples : Int {
        return Int(buffer.frameLength)
    }
    
    var samplesPerPixel : Int {
        return Int((CGFloat(sampleWindowEnd - sampleWindowStart) / bounds.size.width))
    }
    
    var pixelsPerSample : CGFloat {
        return CGFloat(bounds.size.width) / CGFloat(sampleWindowEnd - sampleWindowStart)
    }
    
    @inline(__always)
    func xPositionForSample(_ sample: Int) -> CGFloat? {
        if sample < sampleWindowStart || sample > sampleWindowEnd { return nil } 
        return (CGFloat(sample - sampleWindowStart) / CGFloat(sampleWindowEnd - sampleWindowStart)) * bounds.size.width
    }
    
    @inline(__always)
    func sampleForXPosition(_ xPosition: CGFloat) -> Int? {
        if xPosition < 0 || xPosition > bounds.size.width { return nil }
        return Int((CGFloat(sampleWindowEnd - sampleWindowStart) / bounds.size.width) * xPosition) + sampleWindowStart
    }
    
    let buffer : AVAudioPCMBuffer = {
        let cyndiUrl = Bundle.main.url(forResource: "cyndi", withExtension: "wav")!
        let audioFile = try! AVAudioFile(forReading: cyndiUrl)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length))!
        try! audioFile.read(into: buffer)
        return buffer
    }()
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        sampleWindowStart = 0
        sampleWindowEnd = totalSamples
        
        // Set up gesture recognition
        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(doubleTapRecognized))
        doubleTapRecognizer.numberOfTapsRequired = 2
        self.addGestureRecognizer(doubleTapRecognizer)
        
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressRecognized))
        self.addGestureRecognizer(longPressRecognizer)
        
        let pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchRecognized))
        self.addGestureRecognizer(pinchRecognizer)
    }
    
    @objc func doubleTapRecognized(recognizer: UITapGestureRecognizer) {
        if dragging { return }
        let location = recognizer.location(in: self)
        if let _ = markerForViewLocation(location) {
            // Don't allow markers to be created too close together
            return
        }
        let samplePositionForMarker = sampleForXPosition(location.x)!
        markers.append(samplePositionForMarker);
        markers.sort()
        self.setNeedsDisplay()
    }
    
    @objc func longPressRecognized(recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        let pressedSample = sampleForXPosition(location.x)!
        
        if recognizer.state == .began {
            var startSample = 0
            var endSample = totalSamples
            for marker in markers {
                // We can take advantage of markers being in sorted order here
                if marker < pressedSample {
                    startSample = marker
                }
                else {
                    endSample = marker
                    break
                }
            }
            print("start: \(startSample)  end: \(endSample)")
        }
        else if recognizer.state == .changed {
            print("long press changed")
        }
        else {
            print("long press ended")
        }
    }
    
    var firstPinchDistance : CGFloat! = nil
    var pinchBeginWindowSize : Int! = nil
    var centerPinchSample : Int! = nil
    
    @objc func pinchRecognized(recognizer: UIPinchGestureRecognizer) {
        if recognizer.numberOfTouches < 2 { return }
        let location1 = recognizer.location(ofTouch: 0, in: self)
        let location2 = recognizer.location(ofTouch: 1, in: self)
        if recognizer.state == .began {
            // We only care about horizontal scaling, so we compute the horizontal distance and scaling ourselves
            firstPinchDistance = abs(location1.x - location2.x)
            if firstPinchDistance == 0.0 {
                firstPinchDistance = 0.1
            }
            pinchBeginWindowSize = sampleWindowEnd - sampleWindowStart
            let midpoint = (location1.x + location2.x) / 2.0
            centerPinchSample = sampleForXPosition(midpoint)
        }
        else if (recognizer.state == .changed) {
            var distance = abs(location1.x - location2.x)
            if distance == 0.0 {
                distance = 0.1
            }
            let scale = distance / firstPinchDistance
            
            let totalSamplesInWindow = Int(CGFloat(pinchBeginWindowSize) / scale)
            let midpoint = (location1.x + location2.x) / 2.0
            let sampleOffsetForMidpoint = Int(midpoint * CGFloat(samplesPerPixel))
            
            var firstSample = centerPinchSample - sampleOffsetForMidpoint
            if firstSample < 0 {
                firstSample = 0
            }
            var lastSample = firstSample + totalSamplesInWindow
            if lastSample > totalSamples {
                lastSample = totalSamples
            }
            sampleWindowStart = firstSample
            sampleWindowEnd = lastSample
            setNeedsDisplay()
        }
        else {
            firstPinchDistance = nil
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self)
        if let (markerIdx, _) = markerForViewLocation(location) {
            for recognizer in gestureRecognizers! {
                recognizer.isEnabled = false
            }
            dragging = true
            draggingIdx = markerIdx
        }
        else {
            panStartSample = sampleForXPosition(location.x)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self)
        if dragging {
            let samples = sampleForXPosition(location.x)!
            markers[draggingIdx] = samples // @TODO: Should we prevent dragging markers over each other?
            self.setNeedsDisplay()
        }
        else if panning {
            let totalSamplesInWindow = sampleWindowEnd - sampleWindowStart
            let sampleOffsetForTouch = Int(location.x * CGFloat(samplesPerPixel))
            var startSample = max(panStartSample - sampleOffsetForTouch, 0)
            var endSample = startSample + totalSamplesInWindow
            if endSample > totalSamples {
                endSample = totalSamples
                startSample = endSample - totalSamplesInWindow
            }
            sampleWindowStart = startSample
            sampleWindowEnd = endSample
            setNeedsDisplay()
        }
        else if longPressRecognizer.state == .possible {
            // Only pan if we haven't started a long press yet
            panning = true
            for recognizer in gestureRecognizers! {
                recognizer.isEnabled = false
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = false
        panning = false
        markers.sort()
        for recognizer in gestureRecognizers! {
            recognizer.isEnabled = true
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = false
        panning = false
        markers.sort()
        for recognizer in gestureRecognizers! {
            recognizer.isEnabled = true
        }
    }
    
    func markerForViewLocation(_ location: CGPoint) -> (Int, Int)? {
        let x = location.x
        let markerDistanceThreshold = CGFloat(10.0) // in pixels
        
        for (idx, marker) in markers.enumerated() {
            if let markerX = xPositionForSample(marker) {
                if abs(markerX - x) < markerDistanceThreshold {
                    return (idx, marker)
                }
            }
        }
        
        return nil
    }
    
    override func draw(_ rect: CGRect) {
        
        // Draw the waveform
        let data = buffer.floatChannelData![0]
        
        let context = UIGraphicsGetCurrentContext()!
        var currentX = CGFloat(0.0)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(1.0)
        
        // For each pixel in the horizontal direction, draw a vertical line
        // between the maximum and minimum amplitude of that part of the waveform
        var currentSampleIdx = sampleWindowStart
        for _ in 0..<Int(rect.size.width) {
            var min = 0.0
            var max = 0.0
            for sampleIdx in currentSampleIdx..<currentSampleIdx + samplesPerPixel {
                let sample = Double(data[sampleIdx]);
                if sample < min {
                    min = sample
                }
                else if sample > max {
                    max = sample
                }
            }
            context.beginPath()
            let minY = (rect.size.height / 2.0) - (CGFloat(min) * rect.size.height / 2.0) // Flip y
            let maxY = (rect.size.height / 2.0) - (CGFloat(max) * rect.size.height / 2.0) // Flip y
                
            context.move(to: CGPoint(x: currentX, y: minY))
            context.addLine(to: CGPoint(x: currentX, y: maxY))
            context.strokePath()
            currentSampleIdx += samplesPerPixel
            currentX += 1.0
        }
        
        // Draw the markers
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(2.0)
        context.setLineDash(phase: 0, lengths: [10.0, 3.0])
        for marker in markers {
            if let markerX = xPositionForSample(marker) {
                context.beginPath()
                context.move(to: CGPoint(x: CGFloat(markerX), y: 0.0))
                context.addLine(to: CGPoint(x: CGFloat(markerX), y: rect.size.height))
                context.strokePath()
            }
        }
    }
    
}

class AudioCaptureViewController: UIViewController {

    @IBOutlet weak var audioView: AudioView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
