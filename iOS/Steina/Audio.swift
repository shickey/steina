//
//  Audio.swift
//  Steina
//
//  Created by Sean Hickey on 9/5/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import AudioUnit

var audioUnit : AudioComponentInstance! = nil
var audioRenderInfo : AudioRenderInfo! = nil

class AudioRenderInfo {
    let buffer : Data
    var playhead : Int
    var renderPhase : Double
    
    init(buffer newBuffer: Data, playhead newPlayhead: Int) {
        buffer = newBuffer
        playhead = newPlayhead
        renderPhase = 0
    }
}

func renderAudio(_ inRefCon: UnsafeMutableRawPointer,
                 _ audioUnitRenderActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                 _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                 _ inBusNumber: UInt32,
                 _ inNumberFrames: UInt32,
                 _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    let renderInfo = inRefCon.bindMemory(to: AudioRenderInfo.self, capacity: 1).pointee
    
    let outputBuffers = UnsafeMutableAudioBufferListPointer(ioData)!
    let outputL = outputBuffers[0].mData!.bindMemory(to: Int16.self, capacity: Int(inNumberFrames))
    let outputR = outputBuffers[1].mData!.bindMemory(to: Int16.self, capacity: Int(inNumberFrames))
    
    renderInfo.buffer.withUnsafeBytes { (ptr: UnsafePointer<Int16>) in
        for i in 0..<Int(inNumberFrames) {
            outputL[i] = ptr[renderInfo.playhead + i]
            outputR[i] = ptr[renderInfo.playhead + i]
        }
    }
    
    renderInfo.playhead += Int(inNumberFrames)
    
    return noErr
}

func initAudioSystem() {
    // NOTE: kAudioUnitSubType_RemoteIO refers to the iOS system audio for some reason?
    var componentDescription = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                         componentSubType: kAudioUnitSubType_RemoteIO,
                                                         componentManufacturer: kAudioUnitManufacturer_Apple,
                                                         componentFlags: 0,
                                                         componentFlagsMask: 0)
    let component = AudioComponentFindNext(nil, &componentDescription)!
    
    var audioUnitOptional : AudioComponentInstance? = nil
    AudioComponentInstanceNew(component, &audioUnitOptional)
    audioUnit = audioUnitOptional!
    AudioUnitInitialize(audioUnit)
    
    var streamDescription = AudioStreamBasicDescription(mSampleRate: 44100, 
                                                        mFormatID: kAudioFormatLinearPCM, 
                                                        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved, 
                                                        mBytesPerPacket: 2, 
                                                        mFramesPerPacket: 1, 
                                                        mBytesPerFrame: 2, 
                                                        mChannelsPerFrame: 2, 
                                                        mBitsPerChannel: 16,
                                                        mReserved: 0)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    
    var callbackStruct = AURenderCallbackStruct(inputProc: renderAudio, inputProcRefCon: &audioRenderInfo)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    
    AudioOutputUnitStart(audioUnit)
}
