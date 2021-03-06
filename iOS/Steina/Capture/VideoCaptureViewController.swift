//
//  VideoCaptureViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/22/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import AVFoundation
import QuartzCore
import Accelerate

let FORMAT_420v_CODE : UInt32 = 0x34323076   // '420v' in ascii

let JPEG_QUALITY : S32 = 75 // Value from 1-100 (1 - worst, 100 - best)
let JPEG_FLAGS   : S32 = 0

let MIN_FRAMES = 10            // Minimum frames in a video clip
let MAX_FRAMES = 300           // 10 seconds of video @ 30 fps

enum ClipOrientation : S32 {
    case portrait = 0
    case portraitUpsideDown = 1
    case landscapeLeft = 2
    case landscapeRight = 3
}

enum CameraPosition {
    case back
    case front
}

class VideoPreviewView : UIView {
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
}

class CaptureInfoLabel : UILabel {
    
    var edgeInsets : UIEdgeInsets {
        return UIEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
    }
    
    override func drawText(in rect: CGRect) { 
        super.drawText(in: UIEdgeInsetsInsetRect(rect, self.edgeInsets))
    }
    
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width  += self.edgeInsets.left + self.edgeInsets.right;
        size.height += self.edgeInsets.top + self.edgeInsets.bottom;
        return size
    }
    
}

protocol VideoCaptureViewControllerDelegate {
    func videoCaptureViewControllerDidCreateClip(videoCaptureViewController: VideoCaptureViewController, clip: Clip)
}

class VideoCaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, DrawMaskViewDelegate, VideoEditorViewControllerDelegate {
    
    var delegate : VideoCaptureViewControllerDelegate? = nil
    
    var firstAppearance = true // Flag so that we can go right back to rerecording when dismissing the video editor
    
    var project : Project! = nil
    
    var frontCamera : AVCaptureDevice? = nil
    var backCamera : AVCaptureDevice? = nil
    
    var recordingQueue : DispatchQueue! = nil
    
    var session : AVCaptureSession! = nil
    var frameOutput : AVCaptureVideoDataOutput! = nil
    var cameraPosition : CameraPosition = .back
    var recordingOrientation : ClipOrientation = .portrait
    var framesWritten = 0
    var recording = false
    var compressor : tjhandle! = nil
    var jpegBuffer : U8Ptr! = nil
    var clip : Clip! = nil
    var maskBounds : CGRect! = nil
    var maskData : Data! = nil
    
    @IBOutlet weak var previewView: VideoPreviewView!
    @IBOutlet weak var drawMaskView: DrawMaskView!
    @IBOutlet weak var infoLabel: UILabel!
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var recordProgress: UIProgressView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var cameraReverseButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        drawMaskView.delegate = self
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            self.setupCaptureSession()
            
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupCaptureSession()
                    }
                }
            }
            
        case .denied: // The user has previously denied access.
            return
        case .restricted: // The user can't grant access due to restrictions.
            return
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        updateOrientation()
        if firstAppearance || maskData == nil {
            infoLabel.alpha = 1.0
            infoLabel.isHidden = false
            recordButton.isHidden = true
            recordProgress.isHidden = true
        }
        else {
            recordProgress.isHidden = true
            recordButton.isHidden = false
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if firstAppearance || maskData == nil {
            UIView.animate(withDuration: 5.0, delay: 1.0, options: [], animations: { 
                self.infoLabel.alpha = 0.0
            }) { (_) in
                self.infoLabel.isHidden = true
            }
        }
        firstAppearance = false
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override var shouldAutorotate: Bool {
        if recording { return false }
        return super.shouldAutorotate
    }
    
    func setupCaptureSession() {
        
        // Set up JPEG compression
        compressor = tjInitCompress()
        let size = tjBufSize(640, 480, Int32(TJSAMP_420.rawValue))
        jpegBuffer = tjAlloc(Int32(size))
        
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: nil, position: .unspecified)
        for device in discovery.devices {
            if device.position == .front {
                frontCamera = device
            }
            else if device.position == .back {
                backCamera = device
            }
        }
        
        if frontCamera == nil || backCamera == nil {
            cameraReverseButton.isHidden = true
        }
        
        session = AVCaptureSession()
        session.beginConfiguration()
        
        // @TODO: Test for ability to use this preset, fallback if otherwise
        session.sessionPreset = .vga640x480
        
        // @TODO: This assumes that we actually found a camera at all, which is probably bad
        let input = try! AVCaptureDeviceInput(device: backCamera!)
        session.addInput(input)
        
        cameraPosition = .back
        
        frameOutput = AVCaptureVideoDataOutput()
        frameOutput.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey) : kCVPixelFormatType_32BGRA
        ]
        session.addOutput(frameOutput)
        
        session.commitConfiguration()
        
        recordingQueue = DispatchQueue(label: "edu.mit.media.llk.Bricoleur")
        
        previewView.videoPreviewLayer.session = self.session
        
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange(_:)), name: .UIDeviceOrientationDidChange, object: nil)
        
        session.startRunning()
        
        updateOrientation()
        
    }
    
    func flipCamera() {
        session.beginConfiguration()
        
        let currentCamera = session.inputs[0] as! AVCaptureDeviceInput
        session.removeInput(currentCamera)
        
        if cameraPosition == .back, let front = frontCamera {
            let input = try! AVCaptureDeviceInput(device: front)
            session.addInput(input)
            cameraPosition = .front
        }
        else {
            let back = backCamera!
            let input = try! AVCaptureDeviceInput(device: back)
            session.addInput(input)
            cameraPosition = .back
        }
        
        session.commitConfiguration()
    }
    
    @objc func deviceOrientationDidChange(_ notification: NSNotification) {
        updateOrientation()
    }
    
    func updateOrientation() {
        if recording { return }
        let orientation = UIDevice.current.orientation
        
        if !orientation.isPortrait && !orientation.isLandscape { return }
        
        if let videoConnection = previewView.videoPreviewLayer.connection {
            videoConnection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue)!
        }
        
        if recording { return } // Don't update the orientation while recording so that we can store it
                                // alongside the rest of the clip info
        
        
        var newRecordingOrientation : ClipOrientation = .portrait
        switch orientation {
        case .portrait:
            newRecordingOrientation = .portrait
        case .portraitUpsideDown:
            newRecordingOrientation = .portraitUpsideDown
        case .landscapeLeft:
            newRecordingOrientation = .landscapeLeft
        case .landscapeRight:
            newRecordingOrientation = .landscapeRight
        default: break // Ignore orientations like faceUp/faceDown and just keep the previous orientation value
        }
        
        if newRecordingOrientation != recordingOrientation {
            recordingOrientation = newRecordingOrientation
            drawMaskView.clearMask()
        }
    }
    
    
    func startRecording() {
        closeButton.isHidden = true
        cameraReverseButton.isHidden = true
        recording = true
        framesWritten = 0
        
        let clipId = UUID()
        clip = Clip(id: clipId, project: project)
        clip.mask = maskData
        clip.width = U32(maskBounds.size.width)
        clip.height = U32(maskBounds.size.height)
        
        recordProgress.isHidden = false
        
        // Begin recording by setting up the delegate methods on the background queue
        frameOutput.setSampleBufferDelegate(self, queue: recordingQueue)
    }
    
    func stopRecording() {
        // It's possible that the delegate was already removed by the output delegate
        // method (i.e., in the case where we reached the maximum number of frames)
        // so we only remove it here if necessary
        if let _ = frameOutput.sampleBufferDelegate {
            frameOutput.setSampleBufferDelegate(nil, queue: nil)
        }
        
        // Finish the recording process on the background queue,
        // making sure to wait for all frames to be processed
        recordingQueue.async {
            
            // Write the data on the main queue since the MOC
            // belongs to the main thread
            DispatchQueue.main.async {
                
                self.clip.trimmedRegion = Region<Int>(0, Int(self.clip.frames) - 1)
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let videoEditorVC = storyboard.instantiateViewController(withIdentifier: "VideoEditor") as! VideoEditorViewController
                videoEditorVC.delegate = self
                videoEditorVC.clip = self.clip
                self.present(videoEditorVC, animated: true, completion: nil)
                
                self.recordProgress.isHidden = true
                self.closeButton.isHidden = false
                
                if self.backCamera != nil && self.frontCamera != nil {
                    self.cameraReverseButton.isHidden = true
                }
                
                self.recording = false
            }
        }
    }
    
    @IBAction func recordPressed(_ sender: Any) {
        if recording {
            stopRecording()
        }
        else {
            startRecording()
        }
    }
    
    @IBAction func closePressed(_ sender: Any) {
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func cameraReverseTapped(_ sender: Any) {
        if let _ = frontCamera, let _ = backCamera {
            flipCamera()
        }
    }
    
    // DrawMaskViewDelegate
    
    func drawMaskViewUpdatedMask(_ maskView: DrawMaskView, _ bounds: CGRect?) {
        maskBounds = bounds
        if maskBounds != nil {
            maskData = maskView.createGreyscaleMaskJpeg()
            recordButton.isHidden = false
        }
        else {
            maskData = nil
            recordButton.isHidden = true
        }
        
    }
    
    /*******************************************************************************
     *
     * Capture delegate methods
     *
     * These only get called on the background recordingQueue during
     * an active recording process. Don't call on main queue/thread.
     *
     *******************************************************************************/
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        if self.framesWritten >= MAX_FRAMES {
            // Prevent any more frames from getting processed
            frameOutput.setSampleBufferDelegate(nil, queue: nil)
            DispatchQueue.main.async {
                self.stopRecording()
            }
            return
        }
        
        // Grab pointer to pixels
        let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        CVPixelBufferLockBaseAddress(buffer, [])
        let baseRawPointer = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        // Original pixels
        var originalBuffer = vImage_Buffer()
        originalBuffer.width = UInt(width)
        originalBuffer.height = UInt(height)
        originalBuffer.rowBytes = bytesPerRow
        originalBuffer.data = baseRawPointer
        
        // Rotate the pixels if necessary
        var rotatedBuffer : vImage_Buffer = originalBuffer
        let rotatedBase = malloc(4 * width * height)
        if (recordingOrientation == .landscapeLeft && cameraPosition == .back) || (recordingOrientation == .landscapeRight && cameraPosition == .front) {
            rotatedBuffer = vImage_Buffer(data: rotatedBase, height: 480, width: 640, rowBytes: 640 * 4)
            var foo : U8 = 0
            vImageRotate90_ARGB8888(&originalBuffer, &rotatedBuffer, 2, &foo, 0)
        }
        else if recordingOrientation == .portrait {
            rotatedBuffer = vImage_Buffer(data: rotatedBase, height: 640, width: 480, rowBytes: 480 * 4)
            var foo : U8 = 0
            vImageRotate90_ARGB8888(&originalBuffer, &rotatedBuffer, 1, &foo, 0)
        }
        else if recordingOrientation == .portraitUpsideDown {
            rotatedBuffer = vImage_Buffer(data: rotatedBase, height: 640, width: 480, rowBytes: 480 * 4)
            var foo : U8 = 0
            vImageRotate90_ARGB8888(&originalBuffer, &rotatedBuffer, 3, &foo, 0)
        }
        
        // Flip the buffer vertically if using the front facing camera
        // @TODO: Probably a good idea to wrap this transform into the one above
        if cameraPosition == .front {
            let flippedBufferBase = malloc(4 * width * height)
            var flippedBuffer = vImage_Buffer(data: flippedBufferBase, height: rotatedBuffer.height, width: rotatedBuffer.width, rowBytes: rotatedBuffer.rowBytes)
            vImageHorizontalReflect_ARGB8888(&rotatedBuffer, &flippedBuffer, 0)
            memcpy(rotatedBuffer.data, flippedBuffer.data, flippedBuffer.rowBytes * Int(flippedBuffer.height))
            free(flippedBufferBase)
        }
        
        // Crop into new pixel buffer
        let crop = maskBounds!
        
        // Offset the rotated buffer to the first pixel in the cropped region
        var yOffset = Int(480 - (crop.origin.y + crop.size.height))
        var xOffset = Int(640 - (crop.origin.x + crop.size.width))
        var offset = (640 * yOffset * 4) + (xOffset * 4)
        if recordingOrientation == .portrait || recordingOrientation == .portraitUpsideDown {
            yOffset = Int(640 - (crop.origin.y + crop.size.height))
            xOffset = Int(480 - (crop.origin.x + crop.size.width))
            offset = (480 * yOffset * 4) + (xOffset * 4)
        }
        
        var inBuffer = vImage_Buffer()
        inBuffer.height = UInt(crop.size.height)
        inBuffer.width = UInt(crop.size.width)
        inBuffer.rowBytes = rotatedBuffer.rowBytes
        inBuffer.data = rotatedBuffer.data.advanced(by: offset)
        
        // Create buffer for final cropped output
        let outBase = malloc(4 * Int(crop.size.width * crop.size.height))
        var outBuffer = vImage_Buffer(data: outBase, height: UInt(crop.size.height), width: UInt(crop.size.width), rowBytes: Int(crop.size.width) * 4)
        
        vImageScale_ARGB8888(&inBuffer, &outBuffer, nil, 0)
        
        // Compress
        var jpegSize : UInt = 0
        let typedBase = outBuffer.data.bindMemory(to: U8.self, capacity: Int(crop.size.width * crop.size.height) * 4)
        var compressedBuffer = jpegBuffer // Ridiculous swift limitation won't allow us to pass the buffer directly
                                          // so we have to do it through an alias
        
        tjCompress2(compressor, typedBase, S32(crop.size.width), S32(crop.size.width) * 4, S32(crop.size.height), S32(TJPF_BGRA.rawValue), &compressedBuffer, &jpegSize, S32(TJSAMP_420.rawValue), JPEG_QUALITY, JPEG_FLAGS)
        
        // Copy compressed data to in-memory video file representation
        appendFrame(clip, jpegData: compressedBuffer!, length: Int(jpegSize))
        
        free(outBase)
        free(rotatedBase)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        DispatchQueue.main.async {
            self.recordProgress.progress = Float(self.framesWritten) / Float(MAX_FRAMES) 
        }
        
        self.framesWritten += 1
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("frame dropped")
    }
    
    /*******************************************************************************
     *
     * VideoEditorViewControllerDelegate 
     *
     *******************************************************************************/
    
    func videoEditorRequestedSave(editor: VideoEditorViewController, clip: Clip, markers: [Marker], trimmedRegion: EditorRange) {
        clip.markers = markers
        clip.trimmedRegion = trimmedRegion
        clip.thumbnail = generateThumbnailForClip(clip)
        addClipToProject(clip, project)
        saveClip(clip)

        if let del = delegate {
            del.videoCaptureViewControllerDidCreateClip(videoCaptureViewController: self, clip: clip)
        }
        
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    func videoEditorRequestedDiscard(editor: VideoEditorViewController) {
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    func videoEditorRequestedRerecord(editor: VideoEditorViewController) {
        self.dismiss(animated: true, completion: nil)
    }
    
}
