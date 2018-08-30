//
//  MetalWorker.swift
//  Steina
//
//  Created by Sean Hickey on 5/21/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import UIKit
import Metal
import simd

let MAX_RENDERED_ENTITIES = 100

protocol MetalViewDelegate {
    func metalViewBeganTouch(_ metalView: MetalView, location: CGPoint)
    func metalViewMovedTouch(_ metalView: MetalView, location: CGPoint)
    func metalViewEndedTouch(_ metalView: MetalView, location: CGPoint)
}

class MetalView : UIView {
    
    var delegate : MetalViewDelegate? = nil
    
    override class var layerClass : AnyClass {
        return CAMetalLayer.self
    }
    
    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewBeganTouch(self, location: location)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewMovedTouch(self, location: location)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewEndedTouch(self, location: location)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewEndedTouch(self, location: location)
        }
    }
}

var metalLayer : CAMetalLayer! = nil
let device : MTLDevice! = MTLCreateSystemDefaultDevice()
let commandQueue : MTLCommandQueue! = device.makeCommandQueue()
var pipeline : MTLRenderPipelineState! = nil
var depthState : MTLDepthStencilState! = nil


var lastRenderedTexture : MTLTexture! = nil
var lastRenderedPixels : RawPtr = malloc(4 * 640 * 480)
var lastRenderedHeight = 0
var lastRenderedWidth = 0

struct VideoEffects {
    var color : F32 = 0
    var whirl : F32 = 0
    var brightness : F32 = 0
    var ghost : F32 = 0
}

struct VideoUniforms {
    let entityIndex : U32
    let width : F32
    let height : F32
    let transform: float4x4
    let effects : VideoEffects
}

func genVerts(width: Float, height: Float, depth: Float, entityIndex: Int) -> [Float] {
    let x = width / 2.0
    let y = height / 2.0
    let z = depth
    return [
    //   X   Y   Z    W      U       V    0          EntityIdx
        -x,  y,  z, 1.0, width, height, 0.0, Float(entityIndex.u32),
        -x, -y,  z, 1.0, width,    0.0, 0.0, Float(entityIndex.u32),
         x, -y,  z, 1.0, 0.0,      0.0, 0.0, Float(entityIndex.u32),
        -x,  y,  z, 1.0, width, height, 0.0, Float(entityIndex.u32),
         x, -y,  z, 1.0, 0.0,      0.0, 0.0, Float(entityIndex.u32),
         x,  y,  z, 1.0, 0.0,   height, 0.0, Float(entityIndex.u32)
    ]
}

func entityTransform(scale: Float, rotate: Float, translateX: Float, translateY: Float) -> float4x4 {
    var translation = float4x4(1)
    translation[3][0] = translateX
    translation[3][1] = translateY
    
    var rotation = float4x4(1)
    rotation[0][0] =  cos(rotate)
    rotation[0][1] = -sin(rotate)
    rotation[1][0] =  sin(rotate)
    rotation[1][1] =  cos(rotate)
    
    var scaling = float4x4(1)
    scaling[0][0] = scale
    scaling[1][1] = scale
    
    return translation * rotation * scaling
}

func orthographicProjection(left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float) -> float4x4 {
    return float4x4(
        float4([ 2.0 / (right - left),                    0,                   0, -(right + left) / (right - left) ]),
        float4([                    0, 2.0 / (top - bottom),                   0, -(top + bottom) / (top - bottom) ]),
        float4([                    0,                    0, -2.0 / (far - near),     -(far + near) / (far - near) ]),
        float4([                    0,                    0,                   0,                              1.0 ])
    )
}

func orthographicUnprojection(left: Float, right: Float, top: Float, bottom: Float, near: Float, far: Float) -> float4x4 {
    return float4x4(
        float4([ (right - left) / 2.0,                    0,                   0, (right + left) / 2.0 ]),
        float4([                    0, (top - bottom) / 2.0,                   0, (top + bottom) / 2.0 ]),
        float4([                    0,                    0, (far - near) / -2.0,   (far + near) / 2.0 ]),
        float4([                    0,                    0,                   0,                  1.0 ])
    )
}

var pixelTex : MTLTexture! = nil
var maskTex : MTLTexture! = nil
var depthTex : MTLTexture! = nil

var vertBuffer : MTLBuffer! = nil
var matBuffer : MTLBuffer! = nil

var rawPixels : UnsafeMutableRawPointer! = malloc(640 * 480 * 4 * MAX_RENDERED_ENTITIES)!
var pixels : U8Ptr! = nil

var rawMask : UnsafeMutableRawPointer! = malloc(640 * 480 * MAX_RENDERED_ENTITIES)!
var mask : U8Ptr! = nil

var NUM_DECOMPRESSORS = 10
var decompressors : Set<tjhandle> = Set()
var decompressorSemaphore = DispatchSemaphore(value: NUM_DECOMPRESSORS)
let decompressorLockQueue = DispatchQueue(label: "edu.mit.media.llk.Steina.Decompressors")

var captureScope : MTLCaptureScope! = nil

func initMetal(_ hostView: MetalView) {
    
    captureScope = MTLCaptureManager.shared().makeCaptureScope(device: device)
    captureScope.label = "Steina Debug Scope"
    
    // Set up JPEG decompressors
    for _ in 0..<NUM_DECOMPRESSORS {
        decompressors.insert(tjInitDecompress())
    } 
    
    // Set up rendering view layer
    metalLayer = hostView.metalLayer
    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = false
    
    // Load shaders
    let shaderLibrary = device.makeDefaultLibrary()!
    let vertexShader = shaderLibrary.makeFunction(name: "passthrough_vertex")
    let fragmentShader = shaderLibrary.makeFunction(name: "passthrough_fragment")
    
    // Set up vertex descriptor
    let vertexDescriptor = MTLVertexDescriptor()
    
        // Position
    vertexDescriptor.attributes[0].format = .float4
    vertexDescriptor.attributes[0].bufferIndex = 0
    vertexDescriptor.attributes[0].offset = 0
    
        // UV tex data
    vertexDescriptor.attributes[1].format = .float2
    vertexDescriptor.attributes[1].bufferIndex = 0
    vertexDescriptor.attributes[1].offset = 4 * MemoryLayout<Float>.size
    
        // Entity Index
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].bufferIndex = 0
    vertexDescriptor.attributes[2].offset = 6 * MemoryLayout<Float>.size
    
        // Set stride of vertex buffer
    vertexDescriptor.layouts[0].stride = 8 * MemoryLayout<Float>.size
    vertexDescriptor.layouts[0].stepFunction = .perVertex
    
    // Set up depth buffer
    let depthTexDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 640, height: 480, mipmapped: false)
    depthTexDescriptor.usage = .renderTarget
    depthTex = device.makeTexture(descriptor: depthTexDescriptor)!
    
    // Create rendering pipeline
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexDescriptor = vertexDescriptor
    pipelineDescriptor.vertexFunction = vertexShader
    pipelineDescriptor.fragmentFunction = fragmentShader
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
    
    
    pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    
    // Set up buffers
    vertBuffer = device.makeBuffer(length: (genVerts(width: 0, height: 0, depth: 0, entityIndex: 0).count * MemoryLayout<Float>.size) * MAX_RENDERED_ENTITIES, options: [])
    matBuffer  = device.makeBuffer(length: MemoryLayout<VideoUniforms>.size * MAX_RENDERED_ENTITIES, options: [])
    
    // Set up jpeg decompression
    let width = 640
    let height = 640
    let bytesPerPixel = 4
    let pitch = bytesPerPixel * width
    
    pixels = rawPixels.bindMemory(to: U8.self, capacity: pitch * height * MAX_RENDERED_ENTITIES)
    
    let texDescriptor = MTLTextureDescriptor()
    texDescriptor.textureType = .type2DArray
    texDescriptor.pixelFormat = .bgra8Unorm
    texDescriptor.width = 640
    texDescriptor.height = 640
    texDescriptor.arrayLength = MAX_RENDERED_ENTITIES
    
    pixelTex = device.makeTexture(descriptor: texDescriptor)!
    
    // Set up mask decompression
    mask = rawMask.bindMemory(to: U8.self, capacity: width * height * MAX_RENDERED_ENTITIES)
    
    let maskTexDescriptor = MTLTextureDescriptor()
    maskTexDescriptor.textureType = .type2DArray
    maskTexDescriptor.pixelFormat = .a8Unorm
    maskTexDescriptor.width = 640
    maskTexDescriptor.height = 640
    maskTexDescriptor.arrayLength = MAX_RENDERED_ENTITIES
    
    maskTex = device.makeTexture(descriptor: maskTexDescriptor)!
    
    // Set up depth test
    let depthTestDescriptor = MTLDepthStencilDescriptor()
    depthTestDescriptor.depthCompareFunction = .less
    depthTestDescriptor.isDepthWriteEnabled = true
    depthState = device.makeDepthStencilState(descriptor: depthTestDescriptor)
    
    // Initialize the projection transform
    let uniformsDest = matBuffer.contents()
    let projectionTransform = orthographicProjection(left: -320.0, right: 320.0, top: 240.0, bottom: -240.0, near: 1.0, far: -1.0)
    var projectionUniforms = VideoUniforms(entityIndex: 0, width: 0, height: 0, transform: projectionTransform, effects: VideoEffects(color: 0, whirl: 0, brightness: 0, ghost: 0))
    memcpy(uniformsDest, &projectionUniforms, MemoryLayout<VideoUniforms>.size)
    
    // Set up the texture to blit to for saving project thumbnails
    let blitTexDescriptor = MTLTextureDescriptor()
    blitTexDescriptor.textureType = .type2D
    blitTexDescriptor.pixelFormat = .bgra8Unorm
    blitTexDescriptor.width = 640
    blitTexDescriptor.height = 480
    
    lastRenderedTexture = device.makeTexture(descriptor: blitTexDescriptor)
}

@inline(__always)
func zValueForIndex(_ index: Int) -> Float {
    return 1.0 - (Float(index + 1) / 100.0)
}

@inline(__always)
func indexForZValue(_ z: Float) -> Int {
    return Int(round((1.0 - z) * 100.0)) - 1
}

func getLastRenderedImage() -> UIImage {
    lastRenderedTexture.getBytes(lastRenderedPixels, bytesPerRow: lastRenderedWidth * 4, from: MTLRegionMake2D(0, 0, lastRenderedWidth, lastRenderedHeight), mipmapLevel: 0)
    let context = CGContext(data: lastRenderedPixels, width: lastRenderedWidth, height: lastRenderedHeight, bitsPerComponent: 8, bytesPerRow: lastRenderedWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    return UIImage(cgImage: context.makeImage()!)
}

struct RenderFrame {
    let clip : Clip
    let frameNumber: Int
    let transform : float4x4
    let effects : VideoEffects
}

func pushRenderFrame(_ renderFrame: RenderFrame, at renderingIndex: Int) {
    let clip = renderFrame.clip
    let frameNumber = renderFrame.frameNumber
    let transform = renderFrame.transform
    let effects = renderFrame.effects
    
    // Fill vertex buffer
    let verts = genVerts(width: Float(clip.width), height: Float(clip.height), depth: zValueForIndex(renderingIndex), entityIndex: renderingIndex)
    let vertDest = vertBuffer.contents() + (verts.count * MemoryLayout<Float>.size * renderingIndex)
    memcpy(vertDest, verts, verts.count * MemoryLayout<Float>.size)
    
    // Fill uniforms buffer
    var uniforms = VideoUniforms(entityIndex: U32(renderingIndex), width: Float(clip.width), height: Float(clip.height), transform: transform, effects: effects)
    let uniformsDest = matBuffer.contents() + (MemoryLayout<VideoUniforms>.size * (renderingIndex + 1)) // We reserve the first uniforms for the projection matrix
    memcpy(uniformsDest, &uniforms, MemoryLayout<VideoUniforms>.size)
    
    // Acquire a decompressor
    var decompressor : tjhandle! = nil
    decompressorLockQueue.sync {
        decompressorSemaphore.wait()
        decompressor = decompressors.removeFirst()
    }
    
    // Decode and set up texture
    clip.data.withUnsafeBytes { (ptr : UnsafePointer<U8>) in
        let frameInfo = clip.offsets[frameNumber]
        let jpegBase = ptr + Int(frameInfo.offset)
        let pixelsOffset = pixels + (640 * 640 * 4 * renderingIndex)
        tjDecompress2(decompressor, jpegBase, UInt(frameInfo.length), pixelsOffset, S32(clip.width), S32(clip.width) * 4, S32(clip.height), S32(TJPF_BGRA.rawValue), TJFLAG_FASTDCT | TJFLAG_FASTUPSAMPLE)
    }
    
    let rawPixelsOffset = rawPixels + (640 * 640 * 4 * renderingIndex)
    pixelTex.replace(region: MTLRegionMake2D(0, 0, Int(clip.width), Int(clip.height)), mipmapLevel: 0, slice: renderingIndex, withBytes: rawPixelsOffset, bytesPerRow: Int(clip.width) * 4, bytesPerImage: Int(clip.width * clip.height) * 4)
    
    // Decode and set up mask
    clip.mask.withUnsafeBytes { (ptr : UnsafePointer<U8>) in
        let maskBase = ptr
        let maskOffset = mask + (640 * 640 * renderingIndex)
        tjDecompress2(decompressor, maskBase, UInt(clip.mask.count), maskOffset, S32(clip.width), S32(clip.width), S32(clip.height), S32(TJPF_GRAY.rawValue), TJFLAG_FASTDCT | TJFLAG_FASTUPSAMPLE)
    }
    
    let rawMaskPixelsOffset = rawMask + (640 * 640 * renderingIndex)
    maskTex.replace(region: MTLRegionMake2D(0, 0, Int(clip.width), Int(clip.height)), mipmapLevel: 0, slice: renderingIndex, withBytes: rawMaskPixelsOffset, bytesPerRow: Int(clip.width), bytesPerImage: Int(clip.width * clip.height))
    
    // Release the decompressor back to the queue
    let _ = decompressorLockQueue.sync {
        decompressors.insert(decompressor)
    }
    decompressorSemaphore.signal()
}

func render(_ numEntities: Int) {
    assert(metalLayer != nil)
    
    captureScope.begin()
    
    if let drawable = metalLayer.nextDrawable() {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depthTex
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.label = UUID().uuidString
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        
        renderEncoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(drawable.texture.width), height: Double(drawable.texture.height), znear: 0.0, zfar: 1.0))
        
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setVertexBuffer(vertBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(matBuffer, offset: 0, index: 1)
        
        renderEncoder.setFragmentTexture(pixelTex, index: 0)
        renderEncoder.setFragmentTexture(maskTex, index: 1)
        renderEncoder.setFragmentBuffer(matBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6 * numEntities)
        
        renderEncoder.endEncoding()
        
        let blitCommandEncoder = commandBuffer.makeBlitCommandEncoder()!
        blitCommandEncoder.copy(from: drawable.texture, 
                                sourceSlice: 0, 
                                sourceLevel: 0, 
                                sourceOrigin: MTLOriginMake(0, 0, 0), 
                                sourceSize: MTLSizeMake(drawable.texture.width, drawable.texture.height, drawable.texture.depth), 
                                to: lastRenderedTexture, 
                                destinationSlice: 0, 
                                destinationLevel: 0, 
                                destinationOrigin: MTLOriginMake(0, 0, 0))
        blitCommandEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { _ in
            lastRenderedWidth = Int(metalLayer.drawableSize.width)
            lastRenderedHeight = Int(metalLayer.drawableSize.height)
        }
        
        commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 30.0)
        commandBuffer.commit()
    }
    
    captureScope.end()
    
}
