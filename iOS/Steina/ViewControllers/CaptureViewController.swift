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

class VideoPreviewView: UIView {
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
}


class CaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var recordingQueue : DispatchQueue! = nil
    
    var session : AVCaptureSession! = nil
    var frameOutput : AVCaptureVideoDataOutput! = nil
    var recording = false // Should only be set through the dispatch queue
    var framesWritten = 0
    var compressor : tjhandle! = nil
    var jpegBuffer : U8Ptr! = nil
    var videoData : Data! = nil
    var clip : VideoClip! = nil
    var outputDirectoryPath : URL! = nil
    
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
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setupCaptureSession() {
        
        outputDirectoryPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
        
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
        session.startRunning()
        
    }
    
    func startRecording() {
        print("start")
        framesWritten = 0
        videoData = Data(capacity: 1.megabytes)
        
        clip = VideoClip()
        
        // Begin recording by setting up the delegate methods
        // on the background queue
        frameOutput.setSampleBufferDelegate(self, queue: recordingQueue)
    }
    
    func stopRecording() {
        frameOutput.setSampleBufferDelegate(nil, queue: nil)
        
        // Finish the recording process on the background queue,
        // making sure to wait for all frames to be processed
        recordingQueue.async {
            print("stop")
            print("\(self.framesWritten) frames written")
            
            let clipData = serializeClip(self.clip)
            try! clipData.write(to: self.outputDirectoryPath.appendingPathComponent("clip.out"))
            
        }
    }
    
    @IBAction func recordPressed(_ sender: Any) {
        startRecording()
    }
    
    @IBAction func recordReleased(_ sender: Any) {
        stopRecording()
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
