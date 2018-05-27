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

class MetalView : UIView {
    override class var layerClass : AnyClass {
        return CAMetalLayer.self
    }
}

var metalLayer : CAMetalLayer! = nil
let device : MTLDevice! = MTLCreateSystemDefaultDevice()
let commandQueue : MTLCommandQueue! = device.makeCommandQueue()
var pipeline : MTLRenderPipelineState! = nil

let verts : [Float] = [
    -0.5,  0.5, 1.0, 1.0,   1.0, 0.0, 0.0, 1.0,   0.0, 0.0, 0.0, 0.0,
    -0.5, -0.5, 1.0, 1.0,   0.0, 1.0, 0.0, 1.0,   0.0, 1.0, 0.0, 0.0,
     0.5, -0.5, 1.0, 1.0,   0.0, 0.0, 1.0, 1.0,   1.0, 1.0, 0.0, 0.0,
    -0.5,  0.5, 1.0, 1.0,   1.0, 0.0, 0.0, 1.0,   0.0, 0.0, 0.0, 0.0,
     0.5, -0.5, 1.0, 1.0,   0.0, 0.0, 1.0, 1.0,   1.0, 1.0, 0.0, 0.0,
     0.5,  0.5, 1.0, 1.0,   0.0, 0.0, 1.0, 1.0,   1.0, 0.0, 0.0, 0.0, 
]

var tex : MTLTexture! = nil

var vertBuffer : MTLBuffer! = nil

// @TODO: Rename this
class DisplayLinkThunk {
    var displayLink : CADisplayLink! = nil
    
    func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(linkFired))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .current, forMode: .defaultRunLoopMode)
    }
    
    @objc func linkFired(_ sender: CADisplayLink) {
//        let t0 = CACurrentMediaTime()
        render()
//        let t1 = CACurrentMediaTime()
//        print(String(format: "Frame time: %.3f    Render time: %.3f", (sender.targetTimestamp - sender.timestamp) * 1000.0, (t1 - t0) * 1000.0))
    }
}

var decoder : tjhandle! = nil
var rawPixels : UnsafeMutableRawPointer! = nil
var pixels : U8Ptr! = nil
var clip : VideoClip! = nil

var thunk : DisplayLinkThunk! = nil

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
    
    // Create rendering pipeline
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexShader
    pipelineDescriptor.fragmentFunction = fragmentShader
    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    
    pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    
    // Set up vertex buffer
    vertBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [])
    
    // Set up jpeg decompression
    decoder = tjInitDecompress()
    let width = 640
    let height = 480
    let bytesPerPixel = 4
    let pitch = bytesPerPixel * width
    
    rawPixels = malloc(pitch * height)!
    pixels = rawPixels.bindMemory(to: U8.self, capacity: pitch * height)
    
    // Test clip
    // @TODO: Remove
    let clipUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!.appendingPathComponent("clip.out")
    let clipData = try! Data(contentsOf: clipUrl)
    clip = deserializeClip(clipData)
    
    let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    tex = device.makeTexture(descriptor: texDescriptor)!
    
    thunk = DisplayLinkThunk()
    thunk.startDisplayLink()
}

var frameNumber = 0

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
    
    // Decode and set up texture
    clip.data.withUnsafeBytes { (ptr : UnsafePointer<U8>) in
        let (offset, length) = clip.offsets[frameNumber]
        let jpegBase = ptr + Int(offset)
//        let t0 = CACurrentMediaTime()
        tjDecompress2(decoder, jpegBase, UInt(length), pixels, 640, 640 * 4, 480, S32(TJPF_BGRA.rawValue), 0)
//        let t1 = CACurrentMediaTime()
//        print(String(format: "Decode time: %.3fms", (t1 - t0) * 1000.0))
    }
    
    
    tex.replace(region: MTLRegionMake2D(0, 0, 640, 480), mipmapLevel: 0, withBytes: rawPixels, bytesPerRow: 640 * 4)
    
    renderEncoder.setFragmentTexture(tex, index: 0)
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    
    renderEncoder.endEncoding()
    commandBuffer.present(drawable, afterMinimumDuration: 1.0 / 30.0)
    commandBuffer.commit()
    
    frameNumber += 1
    if frameNumber >= clip.frames {
        frameNumber = 0
    }
}
