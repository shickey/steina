//
//  VideoClip.swift
//  Steina
//
//  Created by Sean Hickey on 5/23/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

/**
 * This file declares the data structures for our custom video file format.
 *
 * In general, a video file consists of a VideoClipHeader structure at the beginning
 * of the file following by zero or more video frames. Each video frame is aligned on
 * a four byte boundary and begins with a VideoClipFrameHeader followed by the JPEG
 * data for that frame. The VideoClipFrameHeader essentially embeds a linked list 
 * structure into the file itself for quick frame accesses.
 *
 */

import Foundation

let VIDEO_FILE_MAGIC_NUMBER : U32 = 0x000F1DE0

struct VideoClipFrameHeader {
    var nextFrameOffset : U32 = 0xFFFFFFFF     // Positive offset from the base address of this frame header to
                                               //   the next one (if it exists, otherwise 0xFFFFFFFF)
                                               // Note: we keep this value first so that it's easy to replace by 
                                               //    accessing it directly from the base address of the frame header
    
    var prevFrameOffset : U32 = 0xFFFFFFFF     // Negative offset from the base address of this frame header to
                                               //   the previous one (if it exists, otherwise 0xFFFFFFFF)
    var frameLength : U32 = 0xFFFFFFFF         // Length in bytes of the frame's JPEG data
}

class VideoClip {
    var frames : U32 = 0
    var data : Data = Data(capacity: 10.megabytes) // JPEG frame data stream
    
    var offsets : [U32] = [U32](repeating: 0xFFFFFFFF, count: 10) // Offset into frameData bytes to frame header for
                                                                  // 0 seconds, 1 second, 2 seconds, etc.
                                                                  // (0xFFFFFFFF indicates no frame)
    
    var lastFrameOffset : U32 = 0xFFFFFFFF // Offset into frameData bytes to final frame of the clip
}


func appendFrame(_ clip: VideoClip, jpegData: U8Ptr, length: Int) {
    // Align to 4 byte boundary
    let alignment = clip.data.count % 4
    if alignment != 0 {
        let bytesNeeded = 4 - alignment
        for _ in 0..<bytesNeeded {
            clip.data.append(0)
        }
    }
    
    let prevFrameOffset = clip.lastFrameOffset
    var newFrameOffset = clip.data.count.u32
    
    var newFrameHeader = VideoClipFrameHeader()
    newFrameHeader.prevFrameOffset = prevFrameOffset
    newFrameHeader.frameLength = length.u32
    
    // Append the new frame header
    withUnsafeBytes(of: &newFrameHeader) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        clip.data.append(bytes)
    }
    
    // Append the JPEG data
    clip.data.append(jpegData, count: length)
    
    
    if clip.frames != 0 {
        // Set the nextFrameOffset pointer on the second to last frame
        withUnsafeBytes(of: &newFrameOffset) { (ptr) in
            let bytes = ptr.bindMemory(to: U8.self)
            let start = clip.data.startIndex.advanced(by: Int(prevFrameOffset))
            let range = start..<start.advanced(by: MemoryLayout<U32>.size)
            clip.data.replaceSubrange(range, with: bytes)
        }
    }
    
    
    clip.lastFrameOffset = newFrameOffset
    
    // Update clip header pointers if necessary
    if (clip.frames % 30 == 0) {
        let offset = Int(clip.frames / 30)
        assert(offset <= 9)
        clip.offsets[offset] = newFrameOffset
    }
    
    clip.frames += 1
    
}

func serializeClip(_ clip: VideoClip) -> Data {
    var out = Data()
    
    var magic : U32 = VIDEO_FILE_MAGIC_NUMBER
    withUnsafeBytes(of: &magic) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    var frames = clip.frames
    withUnsafeBytes(of: &frames) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    for offset in clip.offsets {
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
    
    data.withUnsafeBytes { (bytes : UnsafePointer<U8>) in
        // @TODO: Fragile. This will break if the length of the file header changes
        bytes.withMemoryRebound(to: U32.self, capacity: 12, { (ptr) in
            assert(ptr[0] == VIDEO_FILE_MAGIC_NUMBER)
            clip.frames = ptr[1]
            for i in 0..<10 {
                clip.offsets[i] = ptr[i + 2]
            }
        })
    }
    
    // @TODO: Fragile. This will break if the length of the file header changes
    let jpegDataStart = data.startIndex.advanced(by: (12 * MemoryLayout<U32>.size))
    clip.data = data.subdata(in: jpegDataStart..<data.endIndex)
    
    // @TODO: Should the lastFrameOffset actually be a part of the VideoClip structure?
    //        It seems weird to deserialize it without a real use? Holding off for now.
    
    return clip
}
