//
//  VideoClip.swift
//  Steina
//
//  Created by Sean Hickey on 5/23/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//


import Foundation

let VIDEO_FILE_MAGIC_NUMBER : U32 = 0x000F1DE0

typealias FrameOffset = U32
typealias FrameLength = U32

class VideoClip {
    // Total frames in the clip
    var frames : U32 = 0
    
    // Array of tuples containing each frame offset and length.
    //   Offsets are calculated from the base of the data bytes pointer
    var offsets : [(FrameOffset, FrameLength)] = []
    
    // JPEG frame data bytes
    var data : Data = Data(capacity: 10.megabytes)
}


func appendFrame(_ clip: VideoClip, jpegData: U8Ptr, length: Int) {
    let offset = clip.data.count
    clip.data.append(jpegData, count: length)
    clip.offsets.append((offset.u32, length.u32))
    clip.frames += 1
}

func serializeClip(_ clip: VideoClip) -> Data {
    var out = Data()
    
    // U32 -> Magic Number
    var magic : U32 = VIDEO_FILE_MAGIC_NUMBER
    withUnsafeBytes(of: &magic) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Total frames in clip
    var frames = clip.frames
    withUnsafeBytes(of: &frames) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Data offset from top of file (4 U32s for the first 4 values in this header + (frame count * size of U32))
    var dataOffset : U32 = U32(4 * MemoryLayout<U32>.size + (Int(frames) * MemoryLayout<U32>.size))
    withUnsafeBytes(of: &dataOffset) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Data length in bytes starting from data pointer
    var dataLength = clip.data.count.u32
    withUnsafeBytes(of: &dataLength) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Frame offsets from top of data pointer
    let offsets = clip.offsets.map { $0.0 } // Grab just the offsets, disregard lengths
    for offset in offsets {
        var mutableOffset = offset
        withUnsafeBytes(of: &mutableOffset) { (ptr) in
            let bytes = ptr.bindMemory(to: U8.self)
            out.append(bytes)
        }
    }
    
    out.reserveCapacity(clip.data.count)
    out.append(clip.data)
    
    return out
}


func deserializeClip(_ data: Data) -> VideoClip {
    let clip = VideoClip()
    
    var frames : U32 = 0
    var dataOffset : U32 = 0
    var dataLength : U32 = 0
    
    data.withUnsafeBytes { (bytes : UnsafePointer<U8>) in
        
        // Parse the first 4 fields of the header
        bytes.withMemoryRebound(to: U32.self, capacity: 2, { (ptr) in
            assert(ptr[0] == VIDEO_FILE_MAGIC_NUMBER)
            frames = ptr[1]
            dataOffset = ptr[2]
            dataLength = ptr[3]
        })
        
        
        // Calculate frame offset tuples
        let headerLength = Int(dataOffset)
        bytes.withMemoryRebound(to: U32.self, capacity: headerLength, { (ptr) in
            
            for i in 0..<(frames - 1) { // Handle the last frame differently since we need to use the data length
                                             // to calculate the frame length
                let thisOffset = ptr[Int(4 + i)]
                let nextOffset = ptr[Int(4 + i + 1)]
                let thisLength = nextOffset - thisOffset
                clip.offsets.append((thisOffset, thisLength))
            }
            
            // Last frame
            let lastOffset = ptr[Int(4 + (frames - 1))]
            let lastLength = dataLength - lastOffset
            clip.offsets.append((lastOffset, lastLength))
        })
        
    }
    
    clip.frames = frames
    
    let headerLength = U32(4 * MemoryLayout<U32>.size + (Int(clip.frames) * MemoryLayout<U32>.size))
    let dataOffsetInBytes = Int(headerLength) * MemoryLayout<U32>.size
    let jpegDataStart = data.startIndex.advanced(by: dataOffsetInBytes)
    clip.data = data.subdata(in: jpegDataStart..<data.endIndex)
    
    return clip
}
