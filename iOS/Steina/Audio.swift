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
var audioRenderBuffer = AudioRenderBuffer()

class AudioRenderBuffer {
    var data : Data = Data(count: 48000 * MemoryLayout<Int16>.size) // init(count:) zeroes the bytes
    var playCursor = 0
    var writeCursor = 0
    var length : Int {
        return data.count / 2 // @NOTE: Assumes Int16 samples
    }
}

var firstTime = true

func renderAudio(_ inRefCon: UnsafeMutableRawPointer,
                 _ audioUnitRenderActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                 _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                 _ inBusNumber: UInt32,
                 _ inNumberFrames: UInt32,
                 _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    let numSamplesToRender = Int(inNumberFrames)
    
    let renderBuffer = inRefCon.bindMemory(to: AudioRenderBuffer.self, capacity: 1).pointee
    
    let renderSamples = renderBuffer.data.bytes.bindMemory(to: Int16.self, capacity: 48000)
    
    let outputBuffers = UnsafeMutableAudioBufferListPointer(ioData)!
    let outputL = outputBuffers[0].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    let outputR = outputBuffers[1].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    
    // Render playing sounds into the write area of the buffer
    for sound in playingSounds {
        let soundSamples = sound.samples.bytes.bindMemory(to: Int16.self, capacity: sound.length)
        if sound.playhead < sound.length - numSamplesToRender {
            for i in 0..<numSamplesToRender {
                renderSamples[(renderBuffer.writeCursor + i) % renderBuffer.length] = soundSamples[sound.playhead + i]
            }
        }
        sound.playhead += numSamplesToRender
    }
    renderBuffer.writeCursor = (renderBuffer.writeCursor + numSamplesToRender) % renderBuffer.length 
    
    // If it's the first time, do it again to give us some wiggle room
    if firstTime {
        for sound in playingSounds {
            let soundSamples = sound.samples.bytes.bindMemory(to: Int16.self, capacity: sound.length)
            if sound.playhead < sound.length - numSamplesToRender {
                for i in 0..<numSamplesToRender {
                    renderSamples[(renderBuffer.writeCursor + i) % renderBuffer.length] = soundSamples[sound.playhead + i]
                }
            }
        }
        renderBuffer.writeCursor = (renderBuffer.writeCursor + numSamplesToRender) % renderBuffer.length
        firstTime = false
    }
    
    // Copy samples to the output hardware    
    for i in 0..<numSamplesToRender {
        let sample = renderSamples[(renderBuffer.playCursor + i) % renderBuffer.length]
        outputL[i] = sample
        outputR[i] = sample
    }
    renderBuffer.playCursor = (renderBuffer.playCursor + numSamplesToRender) % renderBuffer.length
    
    return noErr
}

func copySamples(_ buffer: Data, _ range: SampleRange) {
    
    audioRenderBuffer.data.withUnsafeMutableBytes { (ptr: UnsafeMutablePointer<Int16>) in
        let nsBuffer = (buffer as NSData).bytes.bindMemory(to: Int16.self, capacity: range.size)
        for i in 0..<range.size {
            ptr[i] = nsBuffer[range.start + i]
        }
    }
}

class PlayingSound {
    let samples : Data
    var length : Int {
        return samples.count / 2 // @NOTE: Assumes Int16 samples
    }
    var playhead : Int = 0
    
    init(samples newSamples: Data) {
        samples = newSamples
    }
}

var playingSounds : [PlayingSound] = []

func playSound(_ sound: Data) {
    let playingSound = PlayingSound(samples: sound)
    playingSounds.append(playingSound)
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
    
    var streamDescription = AudioStreamBasicDescription(mSampleRate: 48000, 
                                                        mFormatID: kAudioFormatLinearPCM, 
                                                        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved, 
                                                        mBytesPerPacket: 2, 
                                                        mFramesPerPacket: 1, 
                                                        mBytesPerFrame: 2, 
                                                        mChannelsPerFrame: 2, 
                                                        mBitsPerChannel: 16,
                                                        mReserved: 0)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &streamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    
    var callbackStruct = AURenderCallbackStruct(inputProc: renderAudio, inputProcRefCon: &audioRenderBuffer)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    
    AudioOutputUnitStart(audioUnit)
}
