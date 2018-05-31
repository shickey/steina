//
//  MathUtils.swift
//  Steina
//
//  Created by Sean Hickey on 5/31/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import QuartzCore

/**********************************************
 *
 * Math!
 *
 **********************************************/

@inline(__always)
func distance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
    let yDiffSquared = ((point2.y - point1.y) * (point2.y - point1.y))
    let xDiffSquared = ((point2.x - point1.x) * (point2.x - point1.x))
    return sqrt(yDiffSquared + xDiffSquared)
}

@inline(__always)
func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
    let numerator = ((lineEnd.y - lineStart.y) * point.x) - ((lineEnd.x - lineStart.x) * point.y) + (lineEnd.x * lineStart.y) - (lineEnd.y * lineStart.x)
    return abs(numerator) / distance(lineStart, lineEnd)
}

func ramerDouglasPeucker(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
    if points.count < 3 { return points }
    
    // Find the point farthest from the line between the starting and ending points
    var maxDistance : CGFloat = 0.0
    var maxDistIdx = 1 // Start from the second point in the array
    let firstPoint = points.first!
    let lastPoint = points.last!
    for i in 1..<(points.count - 1) {
        let point = points[i]
        let distance = perpendicularDistance(point, lineStart: firstPoint, lineEnd: lastPoint)
        if distance > maxDistance {
            maxDistance = distance
            maxDistIdx = i
        }
    }
    
    if maxDistance < tolerance {
        return [firstPoint, lastPoint]
    }
    
    let leftRecurse = ramerDouglasPeucker(Array(points[0...maxDistIdx]), tolerance: tolerance)
    let rightRecurse = ramerDouglasPeucker(Array(points[maxDistIdx..<points.count]), tolerance: tolerance)
    
    return leftRecurse + rightRecurse[1..<rightRecurse.count]
}
