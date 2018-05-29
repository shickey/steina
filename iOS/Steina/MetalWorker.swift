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

class MetalView : UIView {
    override class var layerClass : AnyClass {
        return CAMetalLayer.self
    }
}

var metalLayer : CAMetalLayer! = nil
let device : MTLDevice! = MTLCreateSystemDefaultDevice()
let commandQueue : MTLCommandQueue! = device.makeCommandQueue()
var pipeline : MTLRenderPipelineState! = nil

func genVerts(_ offset: Int) -> [Float] {
    return [
        // X     Y    Z    W       U    V       0          EntityIdx
        -1.0,  1.0, 1.0, 1.0,    1.0, 1.0,    0.0, Float(offset.u32),
        -1.0, -1.0, 1.0, 1.0,    1.0, 0.0,    0.0, Float(offset.u32),
         1.0, -1.0, 1.0, 1.0,    0.0, 0.0,    0.0, Float(offset.u32),
        -1.0,  1.0, 1.0, 1.0,    1.0, 1.0,    0.0, Float(offset.u32),
         1.0, -1.0, 1.0, 1.0,    0.0, 0.0,    0.0, Float(offset.u32),
         1.0,  1.0, 1.0, 1.0,    0.0, 1.0,    0.0, Float(offset.u32)
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

var tex : MTLTexture! = nil

var vertBuffer : MTLBuffer! = nil
var matBuffer : MTLBuffer! = nil

var decoder : tjhandle! = nil
var rawPixels : UnsafeMutableRawPointer! = nil
var pixels : U8Ptr! = nil

func initMetal(_ hostView: MetalView) {
    
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
    
    
    // Create rendering pipeline
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexDescriptor = vertexDescriptor
    pipelineDescriptor.vertexFunction = vertexShader
    pipelineDescriptor.fragmentFunction = fragmentShader
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    
    pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    
    // Set up buffers
    vertBuffer = device.makeBuffer(length: (genVerts(0).count * MemoryLayout<Float>.size) * MAX_RENDERED_ENTITIES, options: [])
    matBuffer = device.makeBuffer(length: MemoryLayout<float4x4>.size * MAX_RENDERED_ENTITIES, options: [])
    
    // Set up jpeg decompression
    decoder = tjInitDecompress()
    let width = 640
    let height = 480
    let bytesPerPixel = 4
    let pitch = bytesPerPixel * width
    
    rawPixels = malloc(pitch * height)!
    pixels = rawPixels.bindMemory(to: U8.self, capacity: pitch * height)
    
    let texDescriptor = MTLTextureDescriptor()
    texDescriptor.textureType = .type2DArray
    texDescriptor.pixelFormat = .bgra8Unorm
    texDescriptor.width = 640
    texDescriptor.height = 480
    texDescriptor.arrayLength = MAX_RENDERED_ENTITIES
    
    tex = device.makeTexture(descriptor: texDescriptor)!
}

var entitiesToRender = 0;

func clearRenderList() {
    entitiesToRender = 0;
}

func pushRenderFrame(_ clip: VideoClip, _ frameNumber: Int, _ transform: float4x4) {
    let verts = genVerts(entitiesToRender)
    let vertDest = vertBuffer.contents() + (verts.count * MemoryLayout<Float>.size * entitiesToRender)
    memcpy(vertDest, verts, verts.count * MemoryLayout<Float>.size)
    
    let transformDest = matBuffer.contents() + (MemoryLayout<float4x4>.size * entitiesToRender)
    var mutableTransform = transform
    memcpy(transformDest, &mutableTransform, MemoryLayout<float4x4>.size)
    
    // Decode and set up texture
    clip.data.withUnsafeBytes { (ptr : UnsafePointer<U8>) in
        let (offset, length) = clip.offsets[frameNumber]
        let jpegBase = ptr + Int(offset)
        tjDecompress2(decoder, jpegBase, UInt(length), pixels, 640, 640 * 4, 480, S32(TJPF_BGRA.rawValue), 0)
    }
    
    tex.replace(region: MTLRegionMake2D(0, 0, 640, 480), mipmapLevel: 0, slice: entitiesToRender, withBytes: rawPixels, bytesPerRow: 640 * 4, bytesPerImage: 640 * 480 * 4)
    
    entitiesToRender += 1
}

func render() {
    assert(metalLayer != nil)
    
    let drawable = metalLayer.nextDrawable()!
    
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = drawable.texture
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
    
    renderEncoder.setRenderPipelineState(pipeline)
    renderEncoder.setVertexBuffer(vertBuffer, offset: 0, index: 0)
    renderEncoder.setVertexBuffer(matBuffer, offset: 0, index: 1)
    
    renderEncoder.setFragmentTexture(tex, index: 0)
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6 * entitiesToRender)
    
    renderEncoder.endEncoding()
    commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 30.0)
    commandBuffer.commit()
    
    clearRenderList()
}
