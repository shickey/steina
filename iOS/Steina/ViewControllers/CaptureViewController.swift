//
//  CaptureViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/22/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import AVFoundation

let FORMAT_420v_CODE : UInt32 = 0x34323076   // '420v' in ascii

let JPEG_QUALITY : S32 = 75 // Value from 1-100 (1 - worst, 100 - best)
let JPEG_FLAGS   : S32 = 0

enum ClipOrientation : S32 {
    case portrait = 0
    case portraitUpsideDown = 1
    case landscapeLeft = 2
    case landscapeRight = 3
}

class VideoPreviewView: UIView {
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
}


class CaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var project : Project! = nil
    
    var recordingQueue : DispatchQueue! = nil
    
    var session : AVCaptureSession! = nil
    var frameOutput : AVCaptureVideoDataOutput! = nil
    var recordingOrientation : ClipOrientation = .portrait
    var framesWritten = 0
    var recording = false
    var compressor : tjhandle! = nil
    var jpegBuffer : U8Ptr! = nil
    var clip : VideoClip! = nil
    
    @IBOutlet weak var previewView: VideoPreviewView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    func setupCaptureSession() {
        
        // Set up JPEG compression
        compressor = tjInitCompress()
        let size = tjBufSize(640, 480, Int32(TJSAMP_420.rawValue))
        jpegBuffer = tjAlloc(Int32(size))
        
        session = AVCaptureSession()
        session.beginConfiguration()
        
        // @TODO: Test for ability to use this preset, fallback if otherwise
        session.sessionPreset = .vga640x480
        
        let videoDevice = AVCaptureDevice.default(for: .video)! // @TODO: Handle case where no camera present
        let input = try! AVCaptureDeviceInput(device: videoDevice)
        session.addInput(input)
        
        frameOutput = AVCaptureVideoDataOutput()
        frameOutput.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey) : kCVPixelFormatType_32BGRA
        ]
        session.addOutput(frameOutput)
        
        session.commitConfiguration()
        
        recordingQueue = DispatchQueue(label: "edu.mit.media.llk.Steina")
        
        previewView.videoPreviewLayer.session = self.session
        
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationDidChange(_:)), name: .UIDeviceOrientationDidChange, object: nil)
        
        session.startRunning()
        
    }
    
    @objc func deviceOrientationDidChange(_ notification: NSNotification) {
        updateOrientation()
    }
    
    func updateOrientation() {
        let orientation = UIDevice.current.orientation
        
        if !orientation.isPortrait && !orientation.isLandscape { return }
        
        if let videoConnection = previewView.videoPreviewLayer.connection {
            videoConnection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue)!
        }
        
        if recording { return } // Don't update the orientation while recording so that we can store it
        // alongside the rest of the clip info
        
        switch orientation {
        case .portrait:
            recordingOrientation = .portrait
        case .portraitUpsideDown:
            recordingOrientation = .portraitUpsideDown
        case .landscapeLeft:
            recordingOrientation = .landscapeLeft
        case .landscapeRight:
            recordingOrientation = .landscapeRight
        default: break // Ignore orientations like faceUp/faceDown and just keep the previous orientation value
        }
    }
    
    
    func startRecording() {
        print("start")
        recording = true
        framesWritten = 0
        
        clip = VideoClip()
        
        // Begin recording by setting up the delegate methods on the background queue
        frameOutput.setSampleBufferDelegate(self, queue: recordingQueue)
    }
    
    func stopRecording() {
        frameOutput.setSampleBufferDelegate(nil, queue: nil)
        
        // Finish the recording process on the background queue,
        // making sure to wait for all frames to be processed
        recordingQueue.async {
            print("stop")
            print("\(self.framesWritten) frames written")
            
            // Write the data on the main queue since the MOC
            // belongs to the main thread
            DispatchQueue.main.async {
                
                // Create Clip entity
                let clip = self.project.createClip()
                
                let clipData = serializeClip(self.clip)
                try! clipData.write(to: clip.assetUrl)
                
                try! clip.managedObjectContext!.save()
                
                clip.orientation = self.recordingOrientation.rawValue 
                
                self.recording = false
            }
        }
    }
    
    @IBAction func recordPressed(_ sender: Any) {
        startRecording()
    }
    
    @IBAction func recordReleased(_ sender: Any) {
        stopRecording()
    }
    
    @IBAction func closePressed(_ sender: Any) {
        self.presentingViewController!.dismiss(animated: true, completion: nil)
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
        
        // Grab pointer to pixels
        let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        CVPixelBufferLockBaseAddress(buffer, [])
        let baseRawPointer = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        
        print("w: \(width)   h: \(height)")
        
        // Compress
        var jpegSize : UInt = 0
        let typedBase = baseRawPointer!.bindMemory(to: U8.self, capacity: width * height)
        var compressedBuffer = jpegBuffer // Ridiculous swift limitation won't allow us to pass the buffer directly
                                          // so we have to do it through an alias
        tjCompress2(compressor, typedBase, width.s32, bytesPerRow.s32, height.s32, S32(TJPF_BGRA.rawValue), &compressedBuffer, &jpegSize, S32(TJSAMP_420.rawValue), JPEG_QUALITY, JPEG_FLAGS)
        
        // Copy compressed data to in-memory video file representation
        appendFrame(clip, jpegData: compressedBuffer!, length: Int(jpegSize))
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        self.framesWritten += 1
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("frame dropped")
    }
    
}
