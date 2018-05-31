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
    func drawMaskViewCreatedMaskImage(_ maskView: DrawMaskView, maskJpegData: Data)
}

class DrawMaskView : UIView {
    
    var delegate : DrawMaskViewDelegate? = nil
    
    let background = UIColor(white: 0.0, alpha: 0.65)
    
    var path : UIBezierPath! = nil
    var rdpPath : UIBezierPath! = nil
    var maskPath : UIBezierPath! = nil
    
    var points : [CGPoint]! = nil
    
    func createGreyscaleMask(_ maskPath: UIBezierPath) -> Data {
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 640, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        
        UIGraphicsPushContext(context)
        
        let scaleTransform = CGAffineTransform(scaleX: 640.0 / self.bounds.size.width, y: 480.0 / self.bounds.size.height)
        
        let scaledPath = UIBezierPath(cgPath: maskPath.cgPath)
        scaledPath.apply(scaleTransform)
        
        UIColor.black.setFill()
        context.fill(CGRect(origin: CGPoint.zero, size: CGSize(width: 640, height: 480)))
        
        UIColor.white.setFill()
        scaledPath.fill()
        
        let pixels = context.data!
        
        // Compress
        let width = 640
        let height = 480
        let bytesPerRow = width
        
        let compressor = tjInitCompress()
        let size = tjBufSize(640, 480, Int32(TJSAMP_GRAY.rawValue))
        let jpegBuffer = tjAlloc(Int32(size))
        
        var jpegSize : UInt = 0
        let typedBase = pixels.bindMemory(to: U8.self, capacity: width * height)
        var compressedBuffer = jpegBuffer // Ridiculous swift limitation won't allow us to pass the buffer directly
                                          // so we have to do it through an alias
        tjCompress2(compressor, typedBase, width.s32, bytesPerRow.s32, height.s32, S32(TJPF_GRAY.rawValue), &compressedBuffer, &jpegSize, S32(TJSAMP_GRAY.rawValue), 100, 0)
        
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
                let data = createGreyscaleMask(maskPath)
                d.drawMaskViewCreatedMaskImage(self, maskJpegData: data)
            }
        }
        else {
            self.alpha = 1.0
            background.setFill()
            UIBezierPath(rect: rect).fill()
            if path != nil {
                UIColor.white.setStroke()
                path.stroke()
            }
            if rdpPath != nil {
                UIColor.red.setStroke()
                rdpPath.stroke()
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let location = touches.first!.location(in: self)
        points = [location]
        path = UIBezierPath()
        path.lineWidth = 3.0
        rdpPath = nil
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
        print("Simplified \(points.count) points to \(simplifiedPoints.count) points")
        rdpPath = UIBezierPath()
        rdpPath.move(to: simplifiedPoints[0])
        for i in 1..<simplifiedPoints.count {
            rdpPath.addLine(to: simplifiedPoints[i])
        }
        
        maskPath = UIBezierPath()
        maskPath.move(to: simplifiedPoints[0])
        var idx = 3
        while idx < simplifiedPoints.count {
            maskPath.addCurve(to: simplifiedPoints[idx], controlPoint1: simplifiedPoints[idx - 2], controlPoint2: simplifiedPoints[idx - 1])
            idx += 3
        }
        setNeedsDisplay()
    }
    
}
