//
//  DataTypes.swift
//  Steina
//
//  Created by Sean Hickey on 8/30/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import UIKit
import QuartzCore


typealias FrameOffset = U32
typealias FrameLength = U32
typealias AssetId = String
typealias ClipId = AssetId
typealias SoundId = AssetId


let VIDEO_FILE_MAGIC_NUMBER : U32 = 0x000F1DE0
let DATA_DIRECTORY_URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
let PROJECT_MANIFEST_URL = DATA_DIRECTORY_URL.appendingPathComponent("steina.manifest")

struct Region<T:Numeric> {
    var start : T
    var end : T
    
    var size : T {
        return end - start
    }
    
    init(_ newStart: T, _ newEnd: T) {
        start = newStart
        end = newEnd
    }
}

typealias SampleRange = Region<Int>

/*******************************************************************
 *
 * Clip
 *
 *******************************************************************/


struct FrameInfo {
    let offset : FrameOffset
    let length : FrameLength
}

class Clip {
    let id : UUID
    
    let project : Project
    
    var assetUrl : URL {
        return DATA_DIRECTORY_URL
            .appendingPathComponent(project.id.uuidString)
            .appendingPathComponent("video")
            .appendingPathComponent("\(id.uuidString).svc")
    }
    
    // Total frames in the clip
    var frames : U32 = 0
    
    // Width of each image
    var width : U32 = 0
    
    // Height of each image
    var height : U32 = 0
    
    // Array of tuples containing each frame offset and length.
    //   Offsets are calculated from the base of the data bytes pointer
    var offsets : [FrameInfo] = []
    
    // JPEG compositing mask data
    var mask : Data = Data()
    
    // JPEG frame data bytes
    var data : Data = Data(capacity: 10.megabytes)
    
    // Thumbnail
    var thumbnail : UIImage! = nil
    
    // Markers and Trimming
    var markers : [Int] = []
    var trimmedRegion : Region = Region(0, 0)
    
    init(id clipId: UUID, project clipProject: Project) {
        id = clipId
        project = clipProject
    } 
}


func appendFrame(_ clip: Clip, jpegData: U8Ptr, length: Int) {
    let offset = clip.data.count
    clip.data.append(jpegData, count: length)
    clip.offsets.append(FrameInfo(offset: offset.u32, length: length.u32))
    clip.frames += 1
}

func serializeClip(_ clip: Clip) -> Data {
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
    
    // U32 -> Width of each image
    var width = clip.width
    withUnsafeBytes(of: &width) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Height of each image
    var height = clip.height
    withUnsafeBytes(of: &height) { (ptr) in
        let bytes = ptr.bindMemory(to: U8.self)
        out.append(bytes)
    }
    
    // U32 -> Mask data offset from top of file (32 bytes for the header + length of frame offset data)
    var maskOffset : U32 = U32(8 * MemoryLayout<U32>.size + (Int(frames) * MemoryLayout<U32>.size))
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


func deserializeClip(_ clip: Clip, _ data: Data) {
    var frames : U32 = 0
    var width : U32 = 0
    var height : U32 = 0
    var maskOffset : U32 = 0
    var maskLength : U32 = 0
    var dataOffset : U32 = 0
    var dataLength : U32 = 0
    
    data.withUnsafeBytes { (bytes : UnsafePointer<U8>) in
        
        // Parse the first 8 fields of the header
        bytes.withMemoryRebound(to: U32.self, capacity: 8, { (ptr) in
            assert(ptr[0] == VIDEO_FILE_MAGIC_NUMBER)
            frames = ptr[1]
            width = ptr[2]
            height = ptr[3]
            maskOffset = ptr[4]
            maskLength = ptr[5]
            dataOffset = ptr[6]
            dataLength = ptr[7]
        })
        
        
        // Calculate frame offset tuples
        let headerLength = Int(maskOffset)
        bytes.withMemoryRebound(to: U32.self, capacity: headerLength, { (ptr) in
            
            for i in 0..<(frames - 1) { // Handle the last frame differently since we need to use the data length
                                        // to calculate the frame length
                let thisOffset = ptr[Int(8 + i)]
                let nextOffset = ptr[Int(8 + i + 1)]
                let thisLength = nextOffset - thisOffset
                clip.offsets.append(FrameInfo(offset: thisOffset, length: thisLength))
            }
            
            // Last frame
            let lastOffset = ptr[Int(8 + (frames - 1))]
            let lastLength = dataLength - lastOffset
            clip.offsets.append(FrameInfo(offset: lastOffset, length: lastLength))
        })
        
    }
    
    clip.frames = frames
    clip.width = width
    clip.height = height
    
    let maskDataStart = data.startIndex.advanced(by: Int(maskOffset))
    clip.mask = data.subdata(in: maskDataStart..<(maskDataStart + Int(maskLength))) 
    
    let jpegDataStart = data.startIndex.advanced(by: Int(dataOffset))
    clip.data = data.subdata(in: jpegDataStart..<data.endIndex)
    
    clip.thumbnail = generateThumbnailForClip(clip)
}

func generateThumbnailForClip(_ clip: Clip) -> UIImage {
    return createImageForClip(clip, frame: clip.trimmedRegion.start)
}

func createClipInProject(_ project: Project) -> Clip {
    let clipId = UUID()
    let clip = Clip(id: clipId, project: project)
    addClipToProject(clip, project)
    return clip
}

func addClipToProject(_ clip: Clip, _ project: Project) {
    project.clips[clip.id.uuidString] = clip
    project.clipIds.append(clip.id.uuidString)
}

func saveClip(_ clip: Clip) {
    let clipData = serializeClip(clip)
    // @TODO: Handle file writing error
    try! clipData.write(to: clip.assetUrl)
}

@discardableResult
func loadClip(_ id: String, _ project: Project) -> Clip {
    let uuid = UUID(uuidString: id)!
    let clip = Clip(id: uuid, project: project)
    let clipData = try! Data(contentsOf: clip.assetUrl)
    deserializeClip(clip, clipData)
    addClipToProject(clip, project)
    return clip
}

func createImageForClip(_ clip: Clip, frame: Int, inverted : Bool = false) -> UIImage {
    assert(frame >= 0 && frame < clip.frames)
    
    // Decode the frame pixels
    let frameInfo = clip.offsets[frame]
    let frameRangeStart = clip.data.startIndex.advanced(by: Int(frameInfo.offset))
    let frameRangeEnd = frameRangeStart.advanced(by: Int(frameInfo.length))
    let frameData = clip.data.subdata(in: frameRangeStart..<frameRangeEnd)
    
    let pixelDataProvider = CGDataProvider(data: frameData as CFData)!
    let maskDataProvider = CGDataProvider(data: clip.mask as CFData)!
    
    let pixelCGImage = CGImage(jpegDataProviderSource: pixelDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let maskCGImage = CGImage(jpegDataProviderSource: maskDataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    
    let upsideDown = pixelCGImage.masking(maskCGImage)!
    
    let context = CGContext(data: nil, width: Int(clip.width), height: Int(clip.height), bitsPerComponent: 8, bytesPerRow: Int(clip.width) * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    
    // @TODO: This rotation matches what's currently rendered by the GPU, but something is still fishy
    //        in terms of coordinate systems and flipping. Looking into whether the mask is flipping
    //        when it gets rendered into a jpeg for the video file
    if !inverted {
        context.translateBy(x: CGFloat(clip.width), y: CGFloat(clip.height))
        context.rotate(by: .pi)
    }
    else {
        context.scaleBy(x: -1.0, y: 1.0)
        context.translateBy(x: -CGFloat(clip.width), y: 0)
    }
    context.draw(upsideDown, in: CGRect(origin: CGPoint.zero, size: CGSize(width: Int(clip.width), height: Int(clip.height))))
    
    return UIImage(cgImage: context.makeImage()!)
}


/*******************************************************************
 *
 * Sound
 *
 *******************************************************************/

class Sound {
    
    let id : UUID
    
    var project : Project? = nil
    
    var samples : Data
    let bytesPerSample : Int
    var markers : [Int] = []
    var trimmedRegion : SampleRange
    
    var thumbnail : UIImage! = nil
    
    init(id newId: UUID, project newProject: Project, markers newMarkers: [Int], trimmedRegion newTrimmedRegion: SampleRange? = nil) {
        id = newId
        project = newProject
        samples = Data()
        bytesPerSample = 2 // @TODO: This is contrived. Do we even really need to keep this property?
        markers = newMarkers
        if let t = newTrimmedRegion {
            trimmedRegion = t 
        }
        else {
            trimmedRegion = Region(0, samples.count / bytesPerSample)
        }
    }
    
    init(bytesPerSample newBytesPerSample: Int) {
        id = UUID()
        bytesPerSample = newBytesPerSample
        samples = Data()
        trimmedRegion = Region(0, 0)
    }
    
    var length : Int {
        return samples.count / bytesPerSample
    }
    
    var assetUrl : URL {
        return DATA_DIRECTORY_URL
            .appendingPathComponent(project!.id.uuidString)
            .appendingPathComponent("audio")
            .appendingPathComponent("\(id.uuidString).sac")
    }
}

func addSoundToProject(_ sound: Sound, _ project: Project) {
    sound.project = project
    project.sounds[sound.id.uuidString] = sound
    project.soundIds.append(sound.id.uuidString)
}

func saveSound(_ sound: Sound) {
    try! sound.samples.write(to: sound.assetUrl)
}

func loadSound(_ id: String, _ project: Project, _ markers: [Int], _ trimmedRegion: SampleRange? = nil) {
    let uuid = UUID(uuidString: id)!
    
    let sound = Sound(id: uuid, project: project, markers: markers, trimmedRegion: trimmedRegion)
    let soundData = try! Data(contentsOf: sound.assetUrl)
    sound.samples = soundData
    
    if trimmedRegion == nil {
        sound.trimmedRegion = Region(0, sound.length)
    }
    
    sound.thumbnail = generateThumbnailForSound(sound)
    
    addSoundToProject(sound, project)
}

func generateThumbnailForSound(_ sound: Sound) -> UIImage {
    // Draw the waveform
    let nsData = sound.samples as NSData
    let data = nsData.bytes.bindMemory(to: Int16.self, capacity: sound.length)
     
    UIGraphicsBeginImageContext(CGSize(width: 400, height: 150)) // Support 2x rendering
    let context = UIGraphicsGetCurrentContext()!
    var currentX = CGFloat(0.0)
    context.setStrokeColor(UIColor.green.cgColor)
    context.setLineWidth(1.0)
    
    // For each pixel in the horizontal direction, draw a vertical line
    // between the maximum and minimum amplitude of that part of the waveform
    let rect = CGRect(x: 0, y: 0, width: 400, height: 150)
    let samplesPerPixel = sound.length / Int(rect.width)
    var currentSampleIdx = 0
    for _ in 0..<Int(rect.size.width) {
        var min : Int16 = 0
        var max : Int16 = 0
        for sampleIdx in currentSampleIdx..<currentSampleIdx + samplesPerPixel {
            let sample = data[sampleIdx];
            if sample < min {
                min = sample
            }
            else if sample > max {
                max = sample
            }
        }
        context.beginPath()
        let minY = (rect.size.height / 2.0) - (CGFloat(min) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
        let maxY = (rect.size.height / 2.0) - (CGFloat(max) / CGFloat(Int16.max) * rect.size.height / 2.0) // Flip y
        
        context.move(to: CGPoint(x: currentX, y: minY))
        context.addLine(to: CGPoint(x: currentX, y: maxY))
        context.strokePath()
        currentSampleIdx += samplesPerPixel
        currentX += 1.0
    }
    
    // Draw simple markers
    context.setStrokeColor(UIColor.red.cgColor)
    context.setFillColor(UIColor.red.cgColor)
    for marker in sound.markers {
        let markerX = CGFloat(marker) * CGFloat(rect.size.width) / CGFloat(sound.length)
        context.beginPath()
        context.move(to: CGPoint(x: CGFloat(markerX), y: 0))
        context.addLine(to: CGPoint(x: CGFloat(markerX), y: rect.size.height))
        context.strokePath()
    }
    
    // Draw simple greyed out trimmed regions
    if sound.trimmedRegion.start > 0 {
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
        let trimmerPosition = CGFloat(sound.trimmedRegion.start) * CGFloat(rect.size.width) / CGFloat(sound.length)
        let rect = CGRect(x: 0, y: 0, width: trimmerPosition, height: rect.height)
        context.fill(rect)
    }
    if sound.trimmedRegion.end < sound.length {
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
        let trimmerPosition = CGFloat(sound.trimmedRegion.end) * CGFloat(rect.size.width) / CGFloat(sound.length)
        let rect = CGRect(x: trimmerPosition, y: 0, width: rect.width - trimmerPosition, height: rect.height)
        context.fill(rect)
    }
    
    let image = UIImage(cgImage: context.makeImage()!)
    UIGraphicsEndImageContext()
    
    return image
}


/*******************************************************************
 *
 * Project
 *
 *******************************************************************/

class Project {
    let id : UUID
    var clipIds : [ClipId] = []
    var clips : [ClipId : Clip] = [:]
    var soundIds : [SoundId] = []
    var sounds : [SoundId : Sound] = [:]
    var thumbnail : UIImage? = nil
    var assetsLoaded : Bool = false
    
    init(id projectId: UUID) {
        id = projectId
    }
    
    var projectFolderUrl : URL {
        return DATA_DIRECTORY_URL.appendingPathComponent(id.uuidString)
    }
    
    var jsonUrl : URL {
        return projectFolderUrl.appendingPathComponent("project.json")
    }
    
    var thumbnailUrl : URL {
        return projectFolderUrl.appendingPathComponent("thumb.png")
    }
}

func loadProjectThumbnail(_ project: Project) {
    if FileManager.default.fileExists(atPath: project.thumbnailUrl.path) {
        project.thumbnail = UIImage(contentsOfFile: project.thumbnailUrl.path)
    }
}

func loadProjectJson(_ project: Project) -> String {
    if FileManager.default.fileExists(atPath: project.jsonUrl.path) {
        return try! String(contentsOf: project.jsonUrl)
    }
    return ""
}

func saveProjectThumbnail(_ project: Project) {
    assert(project.thumbnail != nil)
    let data = UIImagePNGRepresentation(project.thumbnail!)!
    // @TODO: Handle write error
    try! data.write(to: project.thumbnailUrl)
}

func saveProjectJson(_ project: Project, _ json: String) {
    try! json.write(to: project.jsonUrl, atomically: true, encoding: .utf8)
}

func loadProjectAssets(_ project: Project) {
    if project.assetsLoaded { return }
    
    do {
        let projectJsonData = try Data(contentsOf: project.jsonUrl)
        let projectJson = try JSONSerialization.jsonObject(with: projectJsonData, options: [])
        let jsonDict = projectJson as! NSDictionary
        let videoTargets = jsonDict["videoTargets"] as! NSDictionary
        for (videoTargetId, videoTargetAny) in videoTargets {
            let videoTargetIdStr = videoTargetId as! String
            let videoTarget = videoTargetAny as! Dictionary<String, Any>
            let clip = loadClip(videoTargetIdStr, project)
            if let nsMarkers = videoTarget["markers"] as? [NSNumber] {
                let markers = nsMarkers.map({ $0.intValue })
                clip.markers = markers
            }
            if let nsTrimStart = videoTarget["trimStart"] as? NSNumber, let nsTrimEnd = videoTarget["trimEnd"] as? NSNumber {
                let region = Region(nsTrimStart.intValue, nsTrimEnd.intValue)
                clip.trimmedRegion = region
            }
            else {
                clip.trimmedRegion = Region<Int>(0, Int(clip.frames))
            }
        }
        let audioTargets = jsonDict["audioTargets"] as! NSDictionary
        for (audioTargetId, audioTargetAny) in audioTargets {
            let audioTargetIdStr = audioTargetId as! String
            let audioTarget = audioTargetAny as! Dictionary<String, Any>
            let nsMarkers = audioTarget["markers"] as! [NSNumber]
            let markers = nsMarkers.map({ $0.intValue })
            if let nsTrimStart = audioTarget["trimStart"] as? NSNumber, let nsTrimEnd = audioTarget["trimEnd"] as? NSNumber {
                let region = Region(nsTrimStart.intValue, nsTrimEnd.intValue)
                loadSound(audioTargetIdStr, project, markers, region)
            }
            else {
                loadSound(audioTargetIdStr, project, markers)
            }
             
        }
    }
    catch {}
    
    project.assetsLoaded = true
}

func deleteProjectAsset(_ project: Project, _ assetId: AssetId) {
    if let idx = project.clipIds.firstIndex(of: assetId) {
        project.clipIds.remove(at: idx)
        let clip = project.clips.removeValue(forKey: assetId)
        assert(clip != nil)
        try! FileManager.default.removeItem(at: clip!.assetUrl)
    }
    else if let idx = project.soundIds.firstIndex(of: assetId) {
        project.soundIds.remove(at: idx)
        let sound = project.sounds.removeValue(forKey: assetId)
        assert(sound != nil)
        try! FileManager.default.removeItem(at: sound!.assetUrl)
    }
}

func duplicateProjectAsset(_ project: Project, _ assetId: AssetId, _ newAssetId: AssetId) {
    // @TODO: We could get more clever about this and have multiple in-memory assets
    // point to the same on-disk asset, but then deletion gets complicated and maybe it
    // just isn't worth it
    if let _ = project.clipIds.firstIndex(of: assetId) {
        let clip = project.clips[assetId]
        assert(clip != nil)
        let oldUrl = clip!.assetUrl
        let newUrl = oldUrl.deletingLastPathComponent().appendingPathComponent("\(newAssetId).svc")
        try! FileManager.default.copyItem(at: oldUrl, to: newUrl)
        let newClip = loadClip(newAssetId, project)
        newClip.trimmedRegion = clip!.trimmedRegion
        newClip.markers = clip!.markers
        newClip.thumbnail = generateThumbnailForClip(newClip)
    }
    else if let _ = project.soundIds.firstIndex(of: assetId) {
        let sound = project.sounds[assetId]
        assert(sound != nil)
        let oldUrl = sound!.assetUrl
        let newUrl = oldUrl.deletingLastPathComponent().appendingPathComponent("\(newAssetId).sac")
        try! FileManager.default.copyItem(at: oldUrl, to: newUrl)
        loadSound(newAssetId, project, sound!.markers) // @TODO: This should do a proper array copy, but worth double checking once asset re-editing is implemented
    }
}


/*******************************************************************
 *
 * Storage
 *
 *******************************************************************/

class SteinaStore {
    
    // We use NSMutableArray here instead of swift's Array for the sake
    // of reference semantics
    static var projects : NSMutableArray = []
    
    static func insertProject() -> Project {
        let projectId = UUID()
        let project = Project(id: projectId)
        project.assetsLoaded = true
        projects.add(project)
        
        // Create directory structure
        let fileManager = FileManager.default
        let projectDirectoryUrl = DATA_DIRECTORY_URL.appendingPathComponent(projectId.uuidString)
        let videoDirectoryUrl = projectDirectoryUrl.appendingPathComponent("video")
        let audioDirectoryUrl = projectDirectoryUrl.appendingPathComponent("audio")
        
        // Create directories (project directory gets created automatically as intermediate)
        // @TODO: Error handling on write failure
        try! fileManager.createDirectory(at: videoDirectoryUrl, withIntermediateDirectories: true, attributes: nil)
        try! fileManager.createDirectory(at: audioDirectoryUrl, withIntermediateDirectories: true, attributes: nil)
        
        saveProjectsManifest()
        
        return project
    }
    
    static func loadProjectsManifest() {
        var manifest : String = ""
        do {
            try manifest = String(contentsOf: PROJECT_MANIFEST_URL) 
        }
        catch {
            // If we can't load the file, create an empty one
            try! "".write(to: PROJECT_MANIFEST_URL, atomically: true, encoding: .utf8)
        }
        
        projects = []
        let lines = manifest.split(separator: "\n");
        for projectIdString in lines {
            let projectId = UUID(uuidString: String(projectIdString))!
            let project = Project(id: projectId)
            
            projects.add(project)
        }
        
    }
    
    static func saveProjectsManifest() {
        var manifest = ""
        for untypedProject in projects {
            let project = untypedProject as! Project
            manifest += "\(project.id.uuidString)\n"
        }
        
        // @TODO: Error handling on write failure
        try! manifest.write(to: PROJECT_MANIFEST_URL, atomically: true, encoding: .utf8)
    }
    
}

