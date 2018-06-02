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
    func metalViewDelegateBeganTouch(_ metalView: MetalView, location: CGPoint)
    func metalViewDelegateMovedTouch(_ metalView: MetalView, location: CGPoint)
    func metalViewDelegateEndedTouch(_ metalView: MetalView, location: CGPoint)
}

class MetalView : UIView {
    
    var delegate : MetalViewDelegate? = nil
    
    override class var layerClass : AnyClass {
        return CAMetalLayer.self
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewDelegateBeganTouch(self, location: location)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewDelegateMovedTouch(self, location: location)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewDelegateEndedTouch(self, location: location)
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self);
        if let d = delegate {
            d.metalViewDelegateEndedTouch(self, location: location)
        }
    }
}

var metalLayer : CAMetalLayer! = nil
let device : MTLDevice! = MTLCreateSystemDefaultDevice()
let commandQueue : MTLCommandQueue! = device.makeCommandQueue()
var pipeline : MTLRenderPipelineState! = nil
var depthState : MTLDepthStencilState! = nil

func genVerts(_ entityIndex: Int, z: Float) -> [Float] {
    return [
        // X     Y    Z    W       U    V       0          EntityIdx
        -1.0,  1.0,   z, 1.0,    1.0, 1.0,    0.0, Float(entityIndex.u32),
        -1.0, -1.0,   z, 1.0,    1.0, 0.0,    0.0, Float(entityIndex.u32),
         1.0, -1.0,   z, 1.0,    0.0, 0.0,    0.0, Float(entityIndex.u32),
        -1.0,  1.0,   z, 1.0,    1.0, 1.0,    0.0, Float(entityIndex.u32),
         1.0, -1.0,   z, 1.0,    0.0, 0.0,    0.0, Float(entityIndex.u32),
         1.0,  1.0,   z, 1.0,    0.0, 1.0,    0.0, Float(entityIndex.u32)
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

var pixelTex : MTLTexture! = nil
var maskTex : MTLTexture! = nil
var depthTex : MTLTexture! = nil

var vertBuffer : MTLBuffer! = nil
var matBuffer : MTLBuffer! = nil

var rawPixels : UnsafeMutableRawPointer! = nil
var pixels : U8Ptr! = nil

var rawMask : UnsafeMutableRawPointer! = nil
var mask : U8Ptr! = nil

var NUM_DECOMPRESSORS = 10
var decompressors : Set<tjhandle> = Set()
var decompressorSemaphore = DispatchSemaphore(value: NUM_DECOMPRESSORS)
let decompressorLockQueue = DispatchQueue(label: "edu.mit.media.llk.Steina.Decompressors")

func initMetal(_ hostView: MetalView) {
    
    // Set up JPEG decompressors
    for _ in 0..<NUM_DECOMPRESSORS {
        decompressors.insert(tjInitDecompress())
    } 
    
    // Set up rendering view layer
    metalLayer = hostView.layer as! CAMetalLayer
    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm
    metalLayer.framebufferOnly = true // @TODO: If we ever want to sample from frame attachments, we'll need to set this to false
    
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
    vertBuffer = device.makeBuffer(length: (genVerts(0, z: 0).count * MemoryLayout<Float>.size) * MAX_RENDERED_ENTITIES, options: [])
    matBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.size * MAX_RENDERED_ENTITIES, options: [])
    
    // Set up jpeg decompression
    let width = 640
    let height = 480
    let bytesPerPixel = 4
    let pitch = bytesPerPixel * width
    
    rawPixels = malloc(pitch * height * MAX_RENDERED_ENTITIES)!
    pixels = rawPixels.bindMemory(to: U8.self, capacity: pitch * height * MAX_RENDERED_ENTITIES)
    
    let texDescriptor = MTLTextureDescriptor()
    texDescriptor.textureType = .type2DArray
    texDescriptor.pixelFormat = .bgra8Unorm
    texDescriptor.width = 640
    texDescriptor.height = 480
    texDescriptor.arrayLength = MAX_RENDERED_ENTITIES
    
    pixelTex = device.makeTexture(descriptor: texDescriptor)!
    
    // Set up mask decompression
    rawMask = malloc(width * height * MAX_RENDERED_ENTITIES)!
    mask = rawMask.bindMemory(to: U8.self, capacity: width * height * MAX_RENDERED_ENTITIES)
    
    let maskTexDescriptor = MTLTextureDescriptor()
    maskTexDescriptor.textureType = .type2DArray
    maskTexDescriptor.pixelFormat = .a8Unorm
    maskTexDescriptor.width = 640
    maskTexDescriptor.height = 480
    maskTexDescriptor.arrayLength = MAX_RENDERED_ENTITIES
    
    maskTex = device.makeTexture(descriptor: maskTexDescriptor)!
    
    // Set up depth test
    let depthTestDescriptor = MTLDepthStencilDescriptor()
    depthTestDescriptor.depthCompareFunction = .less
    depthTestDescriptor.isDepthWriteEnabled = true
    depthState = device.makeDepthStencilState(descriptor: depthTestDescriptor)
}

@inline(__always)
func zValueForIndex(_ index: Int) -> Float {
    return 1.0 - (Float(index + 1) / 100.0)
}

@inline(__always)
func indexForZValue(_ z: Float) -> Int {
    return Int(round((1.0 - z) * 100.0)) - 1
}

func pushRenderFrame(_ clip: VideoClip, _ renderingIndex: Int, _ frameNumber: Int, _ transform: float4x4) {
    let verts = genVerts(renderingIndex, z: zValueForIndex(renderingIndex))
    let vertDest = vertBuffer.contents() + (verts.count * MemoryLayout<Float>.size * renderingIndex)
    memcpy(vertDest, verts, verts.count * MemoryLayout<Float>.size)
    
    let transformDest = matBuffer.contents() + (MemoryLayout<float4x4>.size * renderingIndex)
    var mutableTransform = transform
    memcpy(transformDest, &mutableTransform, MemoryLayout<float4x4>.size)
    
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
        let pixelsOffset = pixels + (640 * 480 * 4 * renderingIndex)
        tjDecompress2(decompressor, jpegBase, UInt(frameInfo.length), pixelsOffset, 640, 640 * 4, 480, S32(TJPF_BGRA.rawValue), TJFLAG_FASTDCT | TJFLAG_FASTUPSAMPLE)
    }
    
    let rawPixelsOffset = rawPixels + (640 * 480 * 4 * renderingIndex)
    pixelTex.replace(region: MTLRegionMake2D(0, 0, 640, 480), mipmapLevel: 0, slice: renderingIndex, withBytes: rawPixelsOffset, bytesPerRow: 640 * 4, bytesPerImage: 640 * 480 * 4)
    
    // Decode and set up mask
    clip.mask.withUnsafeBytes { (ptr : UnsafePointer<U8>) in
        let maskBase = ptr
        let maskOffset = mask + (640 * 480 * renderingIndex)
        tjDecompress2(decompressor, maskBase, UInt(640 * 480), maskOffset, 640, 640, 480, S32(TJPF_GRAY.rawValue), TJFLAG_FASTDCT | TJFLAG_FASTUPSAMPLE)
    }
    
    let rawMaskPixelsOffset = rawMask + (640 * 480 * renderingIndex)
    maskTex.replace(region: MTLRegionMake2D(0, 0, 640, 480), mipmapLevel: 0, slice: renderingIndex, withBytes: rawMaskPixelsOffset, bytesPerRow: 640, bytesPerImage: 640 * 480)
    
    // Release the decompressor back to the queue
    let _ = decompressorLockQueue.sync {
        decompressors.insert(decompressor)
    }
    decompressorSemaphore.signal()
}

func render(_ numEntities: Int) {
    assert(metalLayer != nil)
    
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
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
        
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setVertexBuffer(vertBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(matBuffer, offset: 0, index: 1)
        
        renderEncoder.setFragmentTexture(pixelTex, index: 0)
        renderEncoder.setFragmentTexture(maskTex, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6 * numEntities)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 30.0)
        commandBuffer.commit()
    }
    
}
