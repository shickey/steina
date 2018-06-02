//
//  VideoClip.swift
//  Steina
//
//  Created by Sean Hickey on 5/23/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//


import Foundation
import QuartzCore

let VIDEO_FILE_MAGIC_NUMBER : U32 = 0x000F1DE0

typealias FrameOffset = U32
typealias FrameLength = U32

struct FrameInfo {
    let offset : FrameOffset
    let length : FrameLength
}

class VideoClip {
    // Total frames in the clip
    var frames : U32 = 0
    
    // Array of tuples containing each frame offset and length.
    //   Offsets are calculated from the base of the data bytes pointer
    var offsets : [FrameInfo] = []
    
    // JPEG compositing mask data
    var mask : Data = Data()
    
    // JPEG frame data bytes
    var data : Data = Data(capacity: 10.megabytes)
    
    // Thumbnail
    var thumbnail : CGImage! = nil
}


func appendFrame(_ clip: VideoClip, jpegData: U8Ptr, length: Int) {
    let offset = clip.data.count
    clip.data.append(jpegData, count: length)
    clip.offsets.append(FrameInfo(offset: offset.u32, length: length.u32))
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
    
    // U32 -> Mask data offset from top of file (24 bytes for the header + length of frame offset data)
    var maskOffset : U32 = U32(6 * MemoryLayout<U32>.size + (Int(frames) * MemoryLayout<U32>.size))
    withUnsafeBytes(of: &maskOffset) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Mask length in bytes
    var maskLength = clip.mask.count.u32
    withUnsafeBytes(of: &maskLength) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Data offset from top of file
    var dataOffset : U32 = maskOffset + maskLength
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
    let offsets = clip.offsets.map { $0.offset } // Grab just the offsets, disregard lengths
    for offset in offsets {
        var mutableOffset = offset
        withUnsafeBytes(of: &mutableOffset) { (ptr) in
            let bytes = ptr.bindMemory(to: U8.self)
            out.append(bytes)
        }
    }
    
    out.reserveCapacity(clip.mask.count + clip.data.count)
    out.append(clip.mask)
    out.append(clip.data)
    
    return out
}


func deserializeClip(_ data: Data) -> VideoClip {
    let clip = VideoClip()
    
    var frames : U32 = 0
    var maskOffset : U32 = 0
    var maskLength : U32 = 0
    var dataOffset : U32 = 0
    var dataLength : U32 = 0
    
    data.withUnsafeBytes { (bytes : UnsafePointer<U8>) in
        
        // Parse the first 4 fields of the header
        bytes.withMemoryRebound(to: U32.self, capacity: 6, { (ptr) in
            assert(ptr[0] == VIDEO_FILE_MAGIC_NUMBER)
            frames = ptr[1]
            maskOffset = ptr[2]
            maskLength = ptr[3]
            dataOffset = ptr[4]
            dataLength = ptr[5]
        })
        
        
        // Calculate frame offset tuples
        let headerLength = Int(maskOffset)
        bytes.withMemoryRebound(to: U32.self, capacity: headerLength, { (ptr) in
            
            for i in 0..<(frames - 1) { // Handle the last frame differently since we need to use the data length
                                        // to calculate the frame length
                let thisOffset = ptr[Int(6 + i)]
                let nextOffset = ptr[Int(6 + i + 1)]
                let thisLength = nextOffset - thisOffset
                clip.offsets.append(FrameInfo(offset: thisOffset, length: thisLength))
            }
            
            // Last frame
            let lastOffset = ptr[Int(6 + (frames - 1))]
            let lastLength = dataLength - lastOffset
            clip.offsets.append(FrameInfo(offset: lastOffset, length: lastLength))
        })
        
    }
    
    clip.frames = frames
    
    let maskDataStart = data.startIndex.advanced(by: Int(maskOffset))
    clip.mask = data.subdata(in: maskDataStart..<(maskDataStart + Int(maskLength))) 
    
    let jpegDataStart = data.startIndex.advanced(by: Int(dataOffset))
    clip.data = data.subdata(in: jpegDataStart..<data.endIndex)
    
    // Decode the first frame as a thumbnail image
    let thumbInfo = clip.offsets[0]
    let thumbRangeStart = clip.data.startIndex
    let thumbRangeEnd = thumbRangeStart.advanced(by: Int(thumbInfo.length))
    let thumbData = clip.data.subdata(in: thumbRangeStart..<thumbRangeEnd)
    
    let thumbDataProvider = CGDataProvider(data: thumbData as CFData)!
    let maskDataProvider = CGDataProvider(data: clip.mask as CFData)!
    
    let thumbCGImage = CGImage(jpegDataProviderSource: thumbDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let maskCGImage = CGImage(jpegDataProviderSource: maskDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    
    let thumbUpsideDown = thumbCGImage.masking(maskCGImage)!
    
    let context = CGContext.init(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    
    // @TODO: This rotation matches what's currently rendered by the GPU, but something is still fishy
    //        in terms of coordinate systems and flipping. Looking into whether the mask is flipping
    //        when it gets rendered into a jpeg for the video file
    context.translateBy(x: 640, y: 480)
    context.rotate(by: .pi)
    context.draw(thumbUpsideDown, in: CGRect(origin: CGPoint.zero, size: CGSize(width: 640, height: 480)))
    context.rotate(by: .pi)
    
    clip.thumbnail = context.makeImage()!
    
    return clip
}
