//
//  DrawMaskView.swift
//  Steina
//
//  Created by Sean Hickey on 5/31/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import QuartzCore

protocol DrawMaskViewDelegate {
    func drawMaskViewUpdatedMask(_ maskView: DrawMaskView)
}

class DrawMaskView : UIView {
    
    let BACKGROUND_COLOR = UIColor(white: 0.0, alpha: 0.65)
    let PATH_COLOR = UIColor.white
    
    var delegate : DrawMaskViewDelegate? = nil
    var points : [CGPoint]! = nil
    var path : UIBezierPath! = nil
    var maskPath : UIBezierPath! = nil
    
    var compressor : tjhandle! = nil
    var jpegBuffer : U8Ptr! = nil
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupCompressor()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCompressor()
    }
    
    func setupCompressor() {
        compressor = tjInitCompress()
        let size = tjBufSize(640, 480, Int32(TJSAMP_GRAY.rawValue))
        jpegBuffer = tjAlloc(Int32(size))
    }
    
    func createGreyscaleMaskJpeg() -> Data? {
        guard let maskPath = maskPath else {
            return nil
        }
        
        // Create context
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        UIGraphicsPushContext(context)
        
        // Set up proper transformation taking into account device orientation
        let scaleTransform = CGAffineTransform(scaleX: 640.0 / self.bounds.size.width, y: 480.0 / self.bounds.size.height)
        let scaledPath = UIBezierPath(cgPath: maskPath.cgPath)
        scaledPath.apply(scaleTransform)
        
        // Draw
        UIColor.black.setFill()
        context.fill(CGRect(origin: CGPoint.zero, size: CGSize(width: 640, height: 480)))
        UIColor.white.setFill()
        scaledPath.fill()
        
        // Compress
        let pixels = context.data!
        let width = 640
        let height = 480
        let bytesPerRow = width
        var jpegSize : UInt = 0
        let typedBase = pixels.bindMemory(to: U8.self, capacity: width * height)
        var compressedBuffer = jpegBuffer // Ridiculous swift limitation won't allow us to pass the buffer directly
                                          // so we have to do it through an alias
        tjCompress2(compressor, typedBase, width.s32, bytesPerRow.s32, height.s32, S32(TJPF_GRAY.rawValue), &compressedBuffer, &jpegSize, S32(TJSAMP_GRAY.rawValue), 100, 0)
        
        // Return JPEG data
        let data = Data(bytes: compressedBuffer!, count: Int(jpegSize))
        UIGraphicsPopContext()
        return data
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()!
        context.setBlendMode(.normal)
        if maskPath != nil {
            self.alpha = 0.9
            UIColor.black.setFill()
            UIBezierPath(rect: rect).fill()
            context.setBlendMode(.clear)
            UIColor.white.setFill()
            maskPath.fill()
            
            if let d = delegate {
                d.drawMaskViewUpdatedMask(self)
            }
        }
        else {
            self.alpha = 1.0
            BACKGROUND_COLOR.setFill()
            UIBezierPath(rect: rect).fill()
            if path != nil {
                PATH_COLOR.setStroke()
                path.stroke()
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self)
        points = [location]
        path = UIBezierPath()
        path.lineWidth = 3.0
        maskPath = nil
        path.move(to: location)
        setNeedsDisplay()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self)
        path.addLine(to: location)
        points.append(location)
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let simplifiedPoints = ramerDouglasPeucker(points, tolerance: 2)
        maskPath = UIBezierPath()
        maskPath.move(to: simplifiedPoints[0])
        
        // @TODO: Rethink how best to complete the drawn mask.
        //        E.g., if start point and end point are close, should we close the path here?
        var idx = 3
        while idx < simplifiedPoints.count {
            maskPath.addCurve(to: simplifiedPoints[idx], controlPoint1: simplifiedPoints[idx - 2], controlPoint2: simplifiedPoints[idx - 1])
            idx += 3
        }
        setNeedsDisplay()
    }
    
}
