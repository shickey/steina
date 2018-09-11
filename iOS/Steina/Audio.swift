//
//  Audio.swift
//  Steina
//
//  Created by Sean Hickey on 9/5/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import AudioUnit
import AVFoundation
import QuartzCore

typealias PlayingSoundId = UUID

var audioUnit : AudioComponentInstance! = nil
var audioRenderContext = AudioRenderContext()
var playingSounds : [PlayingSoundId : PlayingSound] = [:]

var soundsToStart : [PlayingSound] = []
var soundsToStop : [PlayingSoundId] = []

class Sound {
    let samples : Data
    let bytesPerSample : Int
    
    init(samples newSamples: Data, bytesPerSample newBytesPerSample: Int) {
        samples = newSamples
        bytesPerSample = newBytesPerSample
    }
    
    var length : Int {
        return samples.count / bytesPerSample
    }
}

struct SampleRange {
    var start : Int
    var end : Int
    
    var size : Int {
        return end - start
    }
    
    init(_ newStart: Int, _ newEnd: Int) {
        start = newStart
        end = newEnd
    }
}

class PlayingSound {
    let id : PlayingSoundId
    let sound : Sound
    let range : SampleRange
    let shouldLoop : Bool
    var playhead : Int
    
    init(sound newSound: Sound, range newRange: SampleRange, shouldLoop newShouldLoop: Bool) {
        id = UUID()
        sound = newSound
        range = newRange
        shouldLoop = newShouldLoop
        playhead = newRange.start
    }
}

class AudioRenderContext {
    var callback : (([PlayingSoundId : Int]) -> ())? = nil
}

func inputAudio(_ inRefCon: UnsafeMutableRawPointer,
                 _ audioUnitRenderActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                 _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                 _ inBusNumber: UInt32,
                 _ inNumberFrames: UInt32,
                 _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    return noErr
}

func outputAudio(_ inRefCon: UnsafeMutableRawPointer,
                 _ audioUnitRenderActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                 _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                 _ inBusNumber: UInt32,
                 _ inNumberFrames: UInt32,
                 _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    // @TODO: These addition and removal loops probably aren't threadsafe
    for idToStop in soundsToStop {
        playingSounds.removeValue(forKey: idToStop)
    }
    soundsToStop.removeAll()
    
    for soundToStart in soundsToStart {
        playingSounds[soundToStart.id] = soundToStart
    }
    soundsToStart.removeAll()
    
    let numSamplesToRender = Int(inNumberFrames)
    let renderContext = inRefCon.bindMemory(to: AudioRenderContext.self, capacity: 1).pointee
    
    // Allocate a temporary buffer for mixing
    // We use a 32-bit buffer here to allow overflow above 32k (and below -32k)
    // before mixing back down into 16-bit depth
    let mixingBuffer = Ptr<Int32>.allocate(capacity: numSamplesToRender)
    mixingBuffer.initialize(repeating: 0, count: numSamplesToRender)
    
    // Mix playing sounds
    for (playingSoundId, playingSound) in playingSounds {
        let numSamplesToCopy = min(numSamplesToRender, playingSound.range.end - playingSound.playhead)
        let samples = playingSound.sound.samples.bytes.bindMemory(to: Int16.self, capacity: playingSound.sound.length)
        for i in 0..<numSamplesToCopy {
            mixingBuffer[i] += Int32(samples[playingSound.playhead + i]) 
        }
        playingSound.playhead += numSamplesToCopy
        if playingSound.playhead >= playingSound.range.end {
            if playingSound.shouldLoop {
                playingSound.playhead = playingSound.range.start
            }
            else {
                // Remove this sound from the playing queue on the next audio render loop
                soundsToStop.append(playingSoundId) 
            }
        }
    }


    // Copy mixed samples to the output hardware
    let outputBuffers = UnsafeMutableAudioBufferListPointer(ioData)!
    let outputL = outputBuffers[0].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    let outputR = outputBuffers[1].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    
    for i in 0..<numSamplesToRender {
        // Downsample to 16-bit
        let sample = Int16(truncatingIfNeeded: mixingBuffer[i])
        outputL[i] = sample
        outputR[i] = sample
    }
    
    if let callback = renderContext.callback {
        var updatedPlayheads : [PlayingSoundId : Int] = [:]
        for (soundId, sound) in playingSounds {
            updatedPlayheads[soundId] = sound.playhead
        }
        DispatchQueue.main.async {
            callback(updatedPlayheads)
        }
    }
    
    return noErr
}

func playSound(_ sound: Sound, _ range: SampleRange, looped: Bool) -> PlayingSoundId {
    // The sounds to start playing get added to the playing sound array at the beginning
    // of the next audio render loop
    let playingSound = PlayingSound(sound: sound, range: range, shouldLoop: true)
    soundsToStart.append(playingSound)
    return playingSound.id
}

func stopSound(_ playingSoundId : PlayingSoundId) {
    // The sounds to stop get removed at the beginning
    // of the next audio render loop
    soundsToStop.append(playingSoundId)
}

func initAudioSystem() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
        try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
        try audioSession.setPreferredSampleRate(48000)
        try audioSession.setActive(true)
    }
    catch {
        print("ERROR: Couldn't start audio session")
    }
    
    // @TODO: Make permission checking (for both audio and video)
    //        part of app startup rather than waiting until the point
    //        of recording
    audioSession.requestRecordPermission { (accessGranted) in
        print("\(accessGranted)")
    }
    
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
    
    var inputStreamDescription = AudioStreamBasicDescription(mSampleRate: 48000, 
                                                             mFormatID: kAudioFormatLinearPCM, 
                                                             mFormatFlags: kAudioFormatFlagsNativeFloatPacked, 
                                                             mBytesPerPacket: 8, 
                                                             mFramesPerPacket: 1, 
                                                             mBytesPerFrame: 8, 
                                                             mChannelsPerFrame: 2, 
                                                             mBitsPerChannel: 32,
                                                             mReserved: 0)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inputStreamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    
    var outputStreamDescription = AudioStreamBasicDescription(mSampleRate: 48000, 
                                                              mFormatID: kAudioFormatLinearPCM, 
                                                              mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved, 
                                                              mBytesPerPacket: 2, 
                                                              mFramesPerPacket: 1, 
                                                              mBytesPerFrame: 2, 
                                                              mChannelsPerFrame: 2, 
                                                              mBitsPerChannel: 16,
                                                              mReserved: 0)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outputStreamDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
    
    var renderCallbackStruct = AURenderCallbackStruct(inputProc: outputAudio, inputProcRefCon: &audioRenderContext)
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    
    var inputCallbackStruct = AURenderCallbackStruct(inputProc: inputAudio, inputProcRefCon: &audioRenderContext)
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Input, 0, &inputCallbackStruct, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    
    var enable : UInt32 = 1
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, 1, &enable, UInt32(MemoryLayout<UInt32>.size))
}

func stopAudio() {
    AudioOutputUnitStop(audioUnit)
    AudioUnitUninitialize(audioUnit)
}

func startAudio() {
    AudioUnitInitialize(audioUnit)
    AudioOutputUnitStart(audioUnit)
}

func restartAudio(outputEnabled: Bool, inputEnabled: Bool) {
    stopAudio()
    
    var output : UInt32 = outputEnabled ? 1 : 0
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &output, UInt32(MemoryLayout<UInt32>.size))
    
    var input : UInt32 = inputEnabled ? 1 : 0
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &input, UInt32(MemoryLayout<UInt32>.size))
    
    startAudio()
}
