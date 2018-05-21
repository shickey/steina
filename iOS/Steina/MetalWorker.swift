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
    0.0,  0.5, 1.0, 1.0, 1.0, 0.0, 0.0, 1.0,
   -0.5, -0.5, 1.0, 1.0, 0.0, 1.0, 0.0, 1.0,
    0.5, -0.5, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0
]

var vertBuffer : MTLBuffer! = nil

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
    renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    
    renderEncoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
}
