//
//  Audio.swift
//  Steina
//
//  Created by Sean Hickey on 9/5/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import AudioUnit
import QuartzCore

typealias PlayingSoundId = UUID

var audioUnit : AudioComponentInstance! = nil
var audioRenderBuffer = AudioRenderBuffer()
var playingSounds : [PlayingSoundId : PlayingSound] = [:]
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
    let sound : Sound
    let range : SampleRange
    let shouldLoop : Bool
    var playhead : Int
    
    init(sound newSound: Sound, range newRange: SampleRange, shouldLoop newShouldLoop: Bool) {
        sound = newSound
        range = newRange
        shouldLoop = newShouldLoop
        playhead = newRange.start
    }
}

class AudioRenderBuffer {
    var data : Data = Data(count: 48000 * MemoryLayout<Int16>.size) // init(count:) zeroes the bytes
    var playCursor = 0
    var writeCursor = 0
    var length : Int {
        return data.count / 2 // @NOTE: Assumes Int16 samples
    }
    var callback : (([PlayingSoundId : Int]) -> ())? = nil
}

var firstTime = true

func renderAudio(_ inRefCon: UnsafeMutableRawPointer,
                 _ audioUnitRenderActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                 _ inTimeStamp: UnsafePointer<AudioTimeStamp>,
                 _ inBusNumber: UInt32,
                 _ inNumberFrames: UInt32,
                 _ ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    for idToStop in soundsToStop {
        playingSounds.removeValue(forKey: idToStop)
    }
    soundsToStop.removeAll()
    
    let numSamplesToRender = Int(inNumberFrames)
    
    let renderBuffer = inRefCon.bindMemory(to: AudioRenderBuffer.self, capacity: 1).pointee
    
    let renderSamples = renderBuffer.data.bytes.bindMemory(to: Int16.self, capacity: 48000)
    
    let outputBuffers = UnsafeMutableAudioBufferListPointer(ioData)!
    let outputL = outputBuffers[0].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    let outputR = outputBuffers[1].mData!.bindMemory(to: Int16.self, capacity: numSamplesToRender)
    
    // If there are no sounds, render silence
    if playingSounds.count == 0 {
        for i in 0..<numSamplesToRender {
            renderSamples[(renderBuffer.writeCursor + i) % renderBuffer.length] = 0
        }
        renderBuffer.writeCursor = (renderBuffer.writeCursor + numSamplesToRender) % renderBuffer.length
    }
    else {
        // Render playing sounds into the write area of the buffer
        for (_, playingSound) in playingSounds {
            let sound = playingSound.sound
            let soundSamples = sound.samples.bytes.bindMemory(to: Int16.self, capacity: sound.length)
            if playingSound.playhead < playingSound.range.end - numSamplesToRender {
                for i in 0..<numSamplesToRender {
                    renderSamples[(renderBuffer.writeCursor + i) % renderBuffer.length] = soundSamples[playingSound.playhead + i]
                }
                playingSound.playhead += numSamplesToRender
            }
            else if playingSound.shouldLoop {
                playingSound.playhead = playingSound.range.start
            }
            else {
                // @TODO: Remove from playing sounds
            }
        }
        renderBuffer.writeCursor = (renderBuffer.writeCursor + numSamplesToRender) % renderBuffer.length 
        
        // If it's the first time, do it again to give us some wiggle room
        if firstTime {
            for (_, playingSound) in playingSounds {
                let sound = playingSound.sound
                let soundSamples = sound.samples.bytes.bindMemory(to: Int16.self, capacity: sound.length)
                if playingSound.playhead < playingSound.range.end - numSamplesToRender {
                    for i in 0..<numSamplesToRender {
                        renderSamples[(renderBuffer.writeCursor + i) % renderBuffer.length] = soundSamples[playingSound.playhead + i]
                    }
                    playingSound.playhead += numSamplesToRender
                }
                else if playingSound.shouldLoop {
                    playingSound.playhead = playingSound.range.start
                }
                else {
                    // @TODO: Remove from playing sounds
                }
            }
            renderBuffer.writeCursor = (renderBuffer.writeCursor + numSamplesToRender) % renderBuffer.length
            firstTime = false
        }
    }
    
    // Copy samples to the output hardware    
    for i in 0..<numSamplesToRender {
        let sample = renderSamples[(renderBuffer.playCursor + i) % renderBuffer.length]
        outputL[i] = sample
        outputR[i] = sample
    }
    renderBuffer.playCursor = (renderBuffer.playCursor + numSamplesToRender) % renderBuffer.length
    
    if let callback = renderBuffer.callback {
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
    let playingSound = PlayingSound(sound: sound, range: range, shouldLoop: true)
    let soundId = UUID()
    playingSounds[soundId] = playingSound
    return soundId
}

func stopSound(_ playingSoundId : PlayingSoundId) {
    // The sounds to stop get removed at the beginning
    // of the next audio render loop
    soundsToStop.append(playingSoundId)
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
