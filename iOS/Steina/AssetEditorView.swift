//
//  AssetEditorView.swift
//  Steina
//
//  Created by Sean Hickey on 1/30/19.
//  Copyright © 2019 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit

typealias Marker = Int
typealias EditorRange = Region



protocol AssetEditorViewDataSource {
    func totalRange(for: AssetEditorView) -> EditorRange
    func assetEditorTappedPlayButton(for: AssetEditorView, range: EditorRange)
    func assetEditorReleasedPlayButton(for: AssetEditorView, range: EditorRange)
    func assetEditorMovedToRange(editor: AssetEditorView, range: EditorRange)
}

class AssetEditorView : UIView {
    
    var dataSource : AssetEditorViewDataSource! = nil {
        didSet {
            if let ds = dataSource {
                totalRange = ds.totalRange(for: self)
                trimmedRange = totalRange
                visibleRange = totalRange
                setNeedsDisplay()
            }
        }
    }
    var markers : [Marker] = []
    
    let gutterHeight : CGFloat = 40.0
    let markerHeight : CGFloat = 40.0
    let markerWidth : CGFloat = 40.0 / 2.0
    
    var totalRange : EditorRange = EditorRange(0, 0)
    var trimmedRange : EditorRange = EditorRange(0, 0)
    var visibleRange : EditorRange = EditorRange(0, 0)
    var playhead : Int = 0 {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var showMarkers = true {
        didSet {
            setNeedsDisplay()
        }
    }
    var showPlayhead = true {
        didSet {
            setNeedsDisplay()
        }
    }
    
    enum TouchState {
        case none
        case draggingPlayhead
        case draggingMarker
        case draggingStartTrimmer
        case draggingEndTrimmer
        case panning
        case zooming
        case possiblyAddingMarker
        case touchingPlayButton
    }
    
    var touchState : TouchState = .none
    var activeTouches = Set<UITouch>()
    
    var draggingMarkerIdx : Int! = nil
    var panStartUnit : Int! = nil
    var firstPinchDistance : CGFloat! = nil
    var pinchBeginVisibleRange : Int! = nil
    var centerPinchUnit : Int! = nil
    var activePlayButtonRegion : EditorRange! = nil
    
    var unitsPerPixel : CGFloat {
        return CGFloat(visibleRange.size) / bounds.size.width
    }
    
    var pixelsPerUnit : CGFloat {
        return CGFloat(bounds.size.width) / CGFloat(visibleRange.size)
    }
    
    @inline(__always)
    func xPositionForUnit(_ unit: Int) -> CGFloat? {
        if unit < visibleRange.start || unit > visibleRange.end { return nil } 
        return (CGFloat(unit - visibleRange.start) / CGFloat(visibleRange.size)) * bounds.size.width
    }
    
    @inline(__always)
    func unitForXPosition(_ xPosition: CGFloat) -> Int? {
        if xPosition < 0 || xPosition > bounds.size.width { return nil }
        return Int((CGFloat(visibleRange.size) / bounds.size.width) * xPosition) + visibleRange.start
    }
    
    func markerForViewLocation(_ location: CGPoint) -> (Int, Int)? {
        let x = location.x
        let markerDistanceThreshold = markerWidth / 2.0 // in pixels
        
        for (idx, marker) in markers.enumerated() {
            if let markerX = xPositionForUnit(marker) {
                if abs(markerX - x) < markerDistanceThreshold {
                    return (idx, marker)
                }
            }
        }
        
        return nil
    }
    
    func rangesForVisibleRegions() -> [EditorRange] {
        var ranges : [EditorRange] = []
        var lastRangeStart = visibleRange.start
        for (idx, marker) in markers.enumerated() {
            if marker < visibleRange.start { continue }
            if let _ = xPositionForUnit(marker) {
                ranges.append(EditorRange(lastRangeStart, marker))
                lastRangeStart = marker
                if idx == markers.count - 1 {
                    // Add a final range
                    ranges.append(EditorRange(lastRangeStart, visibleRange.end))
                }
            }
            else {
                ranges.append(EditorRange(lastRangeStart, visibleRange.end))
                break
            }
        }
        return ranges
    }
    
    func fullRangesForVisibleRegions() -> [EditorRange] {
        var ranges : [EditorRange] = []
        for (idx, marker) in markers.enumerated() {
            if marker < visibleRange.start { continue }
            if let _ = xPositionForUnit(marker) {
                if idx == 0 {
                    ranges.append(EditorRange(0, marker))
                }
                else {
                    ranges.append(EditorRange(markers[idx - 1], marker))
                }
                if idx == markers.count - 1 {
                    // Add a final range
                    ranges.append(EditorRange(marker, totalRange.end))
                }
            }
            else {
                if idx == 0 {
                    ranges.append(EditorRange(0, marker))
                }
                else {
                    ranges.append(EditorRange(markers[idx - 1], marker))
                }
            }
        }
        return ranges
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .draggingPlayhead || touchState == .draggingMarker || touchState == .zooming || activeTouches.count >= 2 {
            return
        }
        
        if touchState == .none {
            if touches.count == 1 {
                let touch = touches[touches.startIndex]
                let location = touch.location(in: self)
                if location.y <= gutterHeight || location.y >= bounds.size.height - gutterHeight {
                    // In the gutter
                    
                    let trimmerDistanceThreshold = markerWidth // in pixels, a little bigger than standard markers
                    let startTrimmerX = xPositionForUnit(trimmedRange.start)
                    let endTrimmerX = xPositionForUnit(trimmedRange.end)
                    
                    if startTrimmerX != nil && abs(startTrimmerX! - location.x) < trimmerDistanceThreshold {
                        touchState = .draggingStartTrimmer
                        activeTouches.insert(touch)
                    }
                    else if endTrimmerX != nil && abs(endTrimmerX! - location.x) < trimmerDistanceThreshold {
                        touchState = .draggingEndTrimmer
                        activeTouches.insert(touch)
                    }
                    else if let (idx, _) = markerForViewLocation(location) {
                        touchState = .draggingMarker
                        draggingMarkerIdx = idx
                        activeTouches.insert(touch)
                    } 
                    else {
                        let x = location.x
                        let y = location.y

                        // Check for touching play buttons
                        let playButtonDistanceThreshold : CGFloat = gutterHeight * (2.0 / 5.0) // in pixels
                        let ranges = rangesForVisibleRegions()
                        let playRegions = fullRangesForVisibleRegions()
                        let midpoints = ranges.map { (range) -> CGFloat in
                            let midUnit = Int(CGFloat(range.start + range.end) / 2.0)
                            return xPositionForUnit(midUnit)!
                        }
                        for (idx, midpoint) in midpoints.enumerated() {
                            if abs(midpoint - x) < playButtonDistanceThreshold  && abs((bounds.height - (gutterHeight / 2.0)) - y) < playButtonDistanceThreshold {
                                touchState = .touchingPlayButton
                                activeTouches.insert(touch)
                                activePlayButtonRegion = playRegions[idx]
                                if let ds = dataSource {
                                    ds.assetEditorTappedPlayButton(for: self, range: activePlayButtonRegion)
                                }
                                break
                            } 
                        }
                    }
                }
                else {
                    // In the display area, first check for the playhead
                    let x = location.x
                    let playheadDistanceThreshold : CGFloat = 30.0 // in pixels
                    
                    let playheadX = xPositionForUnit(playhead)
                    if  playheadX != nil && abs(playheadX! - x) < playheadDistanceThreshold {
                        touchState = .draggingPlayhead
                        activeTouches.insert(touch)
                    }
                    else {
                        // Otherwise, start panning
                        touchState = .panning
                        panStartUnit = unitForXPosition(location.x)
                        activeTouches.insert(touch)
                    }
                }
            }
            else {
                // Zooming
                let touch1 = touches[touches.startIndex]
                let touch2 = touches[touches.index(after: touches.startIndex)]
                let location1 = touch1.location(in: self)
                let location2 = touch2.location(in: self)
                firstPinchDistance = abs(location1.x - location2.x)
                if firstPinchDistance == 0.0 {
                    firstPinchDistance = 0.1
                }
                pinchBeginVisibleRange = visibleRange.size
                let midpoint = (location1.x + location2.x) / 2.0
                centerPinchUnit = unitForXPosition(midpoint)
                touchState = .zooming
                activeTouches.insert(touch1)
                activeTouches.insert(touch2)
            }
        }
        else {
            // Already in .panning state
            let touch = touches[touches.startIndex]
            let location = touch.location(in: self)
            // If the new touch is in the gutter, ignore it
            if location.y <= gutterHeight || location.y >= bounds.size.height - gutterHeight { return }
            
            // Transition to zooming
            let touch1 = activeTouches[activeTouches.startIndex]
            let touch2 = touch
            let location1 = touch1.location(in: self)
            let location2 = location
            firstPinchDistance = abs(location1.x - location2.x)
            if firstPinchDistance == 0.0 {
                firstPinchDistance = 0.1
            }
            pinchBeginVisibleRange = visibleRange.size
            let midpoint = (location1.x + location2.x) / 2.0
            centerPinchUnit = unitForXPosition(midpoint)
            touchState = .zooming
            activeTouches.insert(touch1)
            activeTouches.insert(touch2)
            panStartUnit = nil
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .none || touchState == .possiblyAddingMarker || touchState == .touchingPlayButton || activeTouches.intersection(touches).isEmpty { return }
        
        if touchState == .draggingPlayhead {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            if location.x < 0 {
                let unit = unitForXPosition(0)!
                playhead = unit
            }
            else if location.x > bounds.size.width {
                let unit = unitForXPosition(bounds.size.width)!
                playhead = unit
            }
            else {
                let unit = unitForXPosition(location.x)!
                playhead = unit
            }
            
            if playhead < trimmedRange.start {
               playhead = trimmedRange.start 
            }
            else if playhead > trimmedRange.end {
                playhead = trimmedRange.end
            }
            
            self.setNeedsDisplay()
        }
        else if touchState == .draggingStartTrimmer {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            
            if location.x < 0 {
                let unit = unitForXPosition(0)!
                trimmedRange.start = unit
            }
            else if location.x > bounds.size.width {
                let unit = unitForXPosition(bounds.size.width)!
                trimmedRange.start = unit
            }
            else {
                let unit = unitForXPosition(location.x)!
                trimmedRange.start = unit
            }
            
            // Don't drag past end trimmer
            if trimmedRange.start > trimmedRange.end {
                trimmedRange.start = trimmedRange.end
            }
            
            // Update playhead
            if playhead < trimmedRange.start {
                playhead = trimmedRange.start
            }
            self.setNeedsDisplay()
        }
        else if touchState == .draggingEndTrimmer {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            
            if location.x < 0 {
                let unit = unitForXPosition(0)!
                trimmedRange.end = unit
            }
            else if location.x > bounds.size.width {
                let unit = unitForXPosition(bounds.size.width)!
                trimmedRange.end = unit
            }
            else {
                let unit = unitForXPosition(location.x)!
                trimmedRange.end = unit
            }
            
            // Don't drag past start trimmer
            if trimmedRange.end < trimmedRange.start {
                trimmedRange.end = trimmedRange.start
            }
            
            // Update playhead
            if playhead > trimmedRange.end {
                playhead = trimmedRange.end
            }
            
            self.setNeedsDisplay()
        }
        else if touchState == .draggingMarker {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
             // @TODO: Should we prevent dragging markers over each other?
            if location.x < 0 {
                let unit = unitForXPosition(0)!
                markers[draggingMarkerIdx] = unit
            }
            else if location.x > bounds.size.width {
                let unit = unitForXPosition(bounds.size.width)!
                markers[draggingMarkerIdx] = unit
            }
            else {
                let unit = unitForXPosition(location.x)!
                markers[draggingMarkerIdx] = unit
            }
            self.setNeedsDisplay()
        }
        else if touchState == .panning {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            let totalUnitsInWindow = visibleRange.size
            let unitOffsetForTouch = Int(location.x * unitsPerPixel)
            var startUnit = max(panStartUnit - unitOffsetForTouch, 0)
            var endUnit = startUnit + totalUnitsInWindow
            if endUnit > totalRange.size {
                endUnit = totalRange.size
                startUnit = endUnit - totalUnitsInWindow
            }
            visibleRange = EditorRange(startUnit, endUnit)
            if let ds = dataSource {
                ds.assetEditorMovedToRange(editor: self, range: visibleRange)
            }
            setNeedsDisplay()
        }
        else if touchState == .zooming {
            let touch1 = activeTouches[activeTouches.startIndex]
            let touch2 = activeTouches[activeTouches.index(after: activeTouches.startIndex)]
            let location1 = touch1.location(in: self)
            let location2 = touch2.location(in: self)
            var distance = abs(location1.x - location2.x)
            if distance == 0.0 {
                distance = 0.1
            }
            let scale = distance / firstPinchDistance
            
            let totalUnitsInWindow = Int(CGFloat(pinchBeginVisibleRange) / scale)
            let midpoint = (location1.x + location2.x) / 2.0
            let unitOffsetForMidpoint = Int(midpoint * CGFloat(unitsPerPixel))
            
            var firstUnit = centerPinchUnit - unitOffsetForMidpoint
            if firstUnit < 0 {
                firstUnit = 0
            }
            var lastUnit = firstUnit + totalUnitsInWindow
            if lastUnit > totalRange.size {
                lastUnit = totalRange.size
            }
            visibleRange = EditorRange(firstUnit, lastUnit)
            if let ds = dataSource {
                ds.assetEditorMovedToRange(editor: self, range: visibleRange)
            }
            setNeedsDisplay()
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .possiblyAddingMarker && activeTouches.intersection(touches).count == 1 {
            if touchState == .possiblyAddingMarker {
                // Check for touch up inside
                let touch = activeTouches.intersection(touches).first!
                let x = touch.location(in: self).x
                let playheadDistanceThreshold : CGFloat = 30.0 // in pixels
                
                let playheadX = xPositionForUnit(playhead)
                if  playheadX != nil && abs(playheadX! - x) < playheadDistanceThreshold {
                    if !markers.contains(playhead) { // @TODO: Perhaps only add markers if they're far enough away from other markers rather than just directly on top
                        markers.append(playhead)
                    }
                }
            }
        }
        else if touchState == .touchingPlayButton && activeTouches.intersection(touches).count == 1 {
            if touchState == .touchingPlayButton {
                // We don't check for touch up inside, since we want to start/cancel playback no matter what
                if let ds = dataSource {
                    ds.assetEditorReleasedPlayButton(for: self, range: activePlayButtonRegion)
                }
                
            }
        }
        activeTouches.subtract(touches)
        if activeTouches.count == 0 {
            touchState = .none
            draggingMarkerIdx = nil
            panStartUnit = nil
            firstPinchDistance = nil
            pinchBeginVisibleRange = nil
            centerPinchUnit = nil
            activePlayButtonRegion = nil
            markers.sort() // In the case that we moved one marker past another, resort them
        }
        else if touchState == .zooming && activeTouches.count == 1 {
            // Transition back to panning
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            touchState = .panning
            panStartUnit = unitForXPosition(location.x)
            firstPinchDistance = nil
            pinchBeginVisibleRange = nil
            centerPinchUnit = nil
        }
        if let ds = dataSource {
            ds.assetEditorMovedToRange(editor: self, range: visibleRange)
        }
        setNeedsDisplay()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.removeAll()
        touchState = .none
        draggingMarkerIdx = nil
        panStartUnit = nil
        firstPinchDistance = nil
        pinchBeginVisibleRange = nil
        centerPinchUnit = nil
    }
    
    override func draw(_ rect: CGRect) {
          
        let context = UIGraphicsGetCurrentContext()!
        
        // Draw the trimmers and markers
        context.setLineWidth(2.0)
        if showMarkers {
            
            // Grey out the trimmed out regions, if necessary
            if trimmedRange.start >= visibleRange.start && trimmedRange.start <= visibleRange.end {
                let trimmerPosition = xPositionForUnit(trimmedRange.start)!
                let rect = CGRect(x: 0, y: gutterHeight, width: trimmerPosition, height: bounds.height - (2.0 * gutterHeight))
                context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
                context.fill(rect)
            }
            if trimmedRange.end >= visibleRange.start && trimmedRange.end <= visibleRange.end {
                let trimmerPosition = xPositionForUnit(trimmedRange.end)!
                let rect = CGRect(x: trimmerPosition, y: gutterHeight, width: bounds.width - trimmerPosition, height: bounds.height - (2.0 * gutterHeight))
                context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
                context.fill(rect)
            }
            
            context.setStrokeColor(UIColor.red.cgColor)
            context.setFillColor(UIColor.red.cgColor)
            
            // Start Trimmer
            let startTrimX = xPositionForUnit(trimmedRange.start)!
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(startTrimX), y: gutterHeight))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX), y: rect.size.height - gutterHeight))
            context.strokePath()
            
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(startTrimX), y: markerHeight))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX) + (markerWidth / 2.0), y: markerHeight - (markerWidth / 2.0)))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX) + (markerWidth / 2.0), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX), y: 0))
            context.closePath()
            context.fillPath()
            
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(startTrimX), y: rect.size.height - markerHeight))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX), y: rect.size.height))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX) + (markerWidth / 2.0), y: rect.size.height))
            context.addLine(to: CGPoint(x: CGFloat(startTrimX) + (markerWidth / 2.0), y: rect.size.height - (markerHeight - (markerWidth / 2.0))))
            context.closePath()
            context.fillPath()
            
            // End Trimmer
            let endTrimX = xPositionForUnit(trimmedRange.end)!
            
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(endTrimX), y: gutterHeight))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX), y: rect.size.height - gutterHeight))
            context.strokePath()
            
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(endTrimX), y: markerHeight))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX) - (markerWidth / 2.0), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX) - (markerWidth / 2.0), y: markerHeight - (markerWidth / 2.0)))
            context.closePath()
            context.fillPath()
            
            context.beginPath()
            context.move(to: CGPoint(x: CGFloat(endTrimX), y: rect.size.height - markerHeight))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX) - (markerWidth / 2.0), y: rect.size.height - (markerHeight - (markerWidth / 2.0))))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX) - (markerWidth / 2.0), y: rect.size.height))
            context.addLine(to: CGPoint(x: CGFloat(endTrimX), y: rect.size.height))
            context.closePath()
            context.fillPath()
            
            for (idx, marker) in markers.enumerated() {
                if let markerX = xPositionForUnit(marker) {
                    context.setLineDash(phase: 0, lengths: [10.0, 3.0])
                    context.setStrokeColor(UIColor.red.cgColor)
                    context.setFillColor(UIColor.red.cgColor)
                    
                    context.beginPath()
                    context.move(to: CGPoint(x: CGFloat(markerX), y: gutterHeight))
                    context.addLine(to: CGPoint(x: CGFloat(markerX), y: rect.size.height - gutterHeight))
                    context.strokePath()
                    
                    // Draw handles
                    context.setLineDash(phase: 0, lengths: [])
                    
                    context.beginPath()
                    context.move(to: CGPoint(x: CGFloat(markerX), y: markerHeight))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) + (markerWidth / 2.0), y: markerHeight - (markerWidth / 2.0)))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) + (markerWidth / 2.0), y: 0))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) - (markerWidth / 2.0), y: 0))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) - (markerWidth / 2.0), y: markerHeight - (markerWidth / 2.0)))
                    context.closePath()
                    context.fillPath()
                    
                    context.beginPath()
                    context.move(to: CGPoint(x: CGFloat(markerX), y: rect.size.height - markerHeight))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) - (markerWidth / 2.0), y: rect.size.height - (markerHeight - (markerWidth / 2.0))))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) - (markerWidth / 2.0), y: rect.size.height))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) + (markerWidth / 2.0), y: rect.size.height))
                    context.addLine(to: CGPoint(x: CGFloat(markerX) + (markerWidth / 2.0), y: rect.size.height - (markerHeight - (markerWidth / 2.0))))
                    context.closePath()
                    context.fillPath()
                    
                    // Draw labels
                    let label = "\(idx + 1)" // Scratch uses 1-based indexing
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.alignment = .center
                    let attrs : [NSAttributedString.Key : Any] = [.font : UIFont.systemFont(ofSize: gutterHeight * (1.0 / 2.0)), .paragraphStyle : paragraphStyle, .foregroundColor : UIColor.white]
                    label.draw(with: CGRect(x: CGFloat(markerX) - (markerWidth / 2.0), y: (markerHeight * 0.1), width: markerWidth, height: (markerHeight * 0.9)), options:.usesLineFragmentOrigin, attributes: attrs, context: nil)
                    label.draw(with: CGRect(x: CGFloat(markerX) - (markerWidth / 2.0), y: bounds.size.height - (markerHeight * 0.75), width: markerWidth, height: markerHeight), options:.usesLineFragmentOrigin, attributes: attrs, context: nil)
                }
            }
        }
        
        // Draw play symbols
        context.setFillColor(UIColor.green.cgColor)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(2.0)
        let ranges = rangesForVisibleRegions()
        for range in ranges {
            let midUnit = Int(CGFloat(range.start + range.end) / 2.0)
            if let midpoint = xPositionForUnit(midUnit) {
                let playButtonCenter = CGPoint(x: midpoint, y: bounds.height - (gutterHeight / 2.0))
                var playButtonRect = CGRect(origin: playButtonCenter, size: .zero)
                let inset = gutterHeight * (2.0 / 5.0)
                playButtonRect = playButtonRect.insetBy(dx: -inset, dy: -inset)
                context.addEllipse(in: playButtonRect)
                context.strokePath()
                // Play Symbol
                context.beginPath()
                context.move(to: CGPoint(x: playButtonCenter.x + inset / 3.0, y: playButtonCenter.y))
                context.addLine(to: CGPoint(x: playButtonCenter.x - inset / 4.0, y: playButtonCenter.y + inset / 3.0))
                context.addLine(to: CGPoint(x: playButtonCenter.x - inset / 4.0, y: playButtonCenter.y - inset / 3.0))
                context.closePath()
                context.fillPath()
            }
        }
        
        
        // Draw the playhead if playing
        if showPlayhead {
            if let playheadX = xPositionForUnit(playhead) {
                context.setStrokeColor(UIColor.yellow.cgColor)
                context.setLineWidth(2.0)
                context.setLineDash(phase: 0, lengths: [])
                context.beginPath()
                context.move(to: CGPoint(x: CGFloat(playheadX), y: gutterHeight))
                context.addLine(to: CGPoint(x: CGFloat(playheadX), y: rect.size.height - gutterHeight))
                context.strokePath()
                
                // Crossbars
                context.setLineWidth(4.0)
                context.beginPath()
                context.move(to: CGPoint(x: CGFloat(playheadX) - 10.0, y: gutterHeight + 2.0))
                context.addLine(to: CGPoint(x: CGFloat(playheadX) + 10.0, y: gutterHeight + 2.0))
                context.strokePath()
                context.beginPath()
                context.move(to: CGPoint(x: CGFloat(playheadX) - 10.0, y: rect.size.height - gutterHeight - 2.0))
                context.addLine(to: CGPoint(x: CGFloat(playheadX) + 10.0, y: rect.size.height - gutterHeight - 2.0))
                context.strokePath()
            }
        }
    }
}

