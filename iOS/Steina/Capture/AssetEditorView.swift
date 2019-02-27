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



protocol AssetEditorViewDelegate {
    func totalRange(for: AssetEditorView) -> EditorRange
    func assetEditorTappedPlayButton(for: AssetEditorView, range: EditorRange)
    func assetEditorReleasedPlayButton(for: AssetEditorView, range: EditorRange)
    func assetEditorMovedToRange(editor: AssetEditorView, range: EditorRange)
    func assetEditorDidSelect(editor: AssetEditorView, marker: Marker, at index: Int)
    func assetEditorDidDeselect(editor: AssetEditorView, marker: Marker, at index: Int)
}

class AssetEditorView : UIView {
    
    var delegate : AssetEditorViewDelegate! = nil {
        didSet {
            if let del = delegate {
                totalRange = del.totalRange(for: self)
                trimmedRange = totalRange
                visibleRange = totalRange
                setNeedsDisplay()
            }
        }
    }
    var markers : [Marker] = []
    
    var selectedMarker : Marker? = nil
    var selectedMarkerIdx : Int? = nil
    
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
        case zooming
        case touchingPlayButton
        case ignoring
    }
    
    var touchState : TouchState = .none
    var activeTouches = Set<UITouch>()
    
    var draggingMarkerIdx : Int! = nil
    var panStartUnit : Int! = nil
    var firstPinchDistance : CGFloat! = nil
    var pinchBeginVisibleRangeSize : Int! = nil
    var centerPinchUnit : Int! = nil
    var activePlayButtonRegion : EditorRange! = nil
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }
    
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
    
    func markerForXPosition(_ x: CGFloat, thresholdInPixels: CGFloat? = nil) -> (Int, Marker)? {
        var markerDistanceThreshold = markerWidth / 2.0 // in pixels
        if let thresholdOverride = thresholdInPixels {
            markerDistanceThreshold = thresholdOverride
        }
        var minDistance = markerDistanceThreshold
        var minIdx : Int? = nil
        for (idx, marker) in markers.enumerated() {
            if let markerX = xPositionForUnit(marker) {
                let dist = abs(markerX - x)
                if dist < markerDistanceThreshold {
                    if dist < minDistance {
                        minDistance = dist
                        minIdx = idx
                    }
                }
            }
        }
        
        if let idx = minIdx {
            return (idx, markers[idx])
        }
        
        return nil
    }
    
    func rangesForVisibleRegions() -> [EditorRange] {
        var ranges : [EditorRange] = []
        var lastRangeStart = visibleRange.start
        if trimmedRange.start > visibleRange.start {
            lastRangeStart = trimmedRange.start
        }
        for marker in markers {
            if marker < visibleRange.start { continue }
            if let _ = xPositionForUnit(marker) {
                ranges.append(EditorRange(lastRangeStart, marker))
                lastRangeStart = marker
            }
        }
        if trimmedRange.end < visibleRange.end {
            ranges.append(EditorRange(lastRangeStart, trimmedRange.end))
        }
        else {
            ranges.append(EditorRange(lastRangeStart, visibleRange.end))
        }
        return ranges
    }
    
    func fullRangesForVisibleRegions() -> [EditorRange] {
        var ranges : [EditorRange] = []
        if trimmedRange.start > visibleRange.end { return ranges } 
        var lastRangeStart = trimmedRange.start
        var didBreakEarly = false
        for marker in markers {
            if marker < visibleRange.start {
                lastRangeStart = marker
                continue
            }
            if marker > visibleRange.end {
                ranges.append(EditorRange(lastRangeStart, marker))
                didBreakEarly = true
                break
            }
            ranges.append(EditorRange(lastRangeStart, marker))
            lastRangeStart = marker
        }
        if !didBreakEarly && trimmedRange.end > visibleRange.start {
            ranges.append(EditorRange(lastRangeStart, trimmedRange.end))
        }
        return ranges
    }
    
    func createMarkerAtPlayhead() {
        if markers.contains(playhead) { return }
        markers.append(playhead)
        markers.sort()
        let idx = markers.firstIndex(of: playhead)!
        selectedMarkerIdx = idx
        selectedMarker = markers[idx]
        if let del = delegate {
            del.assetEditorDidSelect(editor: self, marker: selectedMarker!, at: selectedMarkerIdx!)
        }
        setNeedsDisplay()
    }
    
    func updatePlayhead(_ newPlayhead: Int) {
        if newPlayhead < trimmedRange.start {
            playhead = trimmedRange.start
        }
        else if newPlayhead > trimmedRange.end {
            playhead = trimmedRange.end
        }
        else {
            playhead = newPlayhead
        }
        updateSelectedMarker()
        setNeedsDisplay()
    }
    
    func updateSelectedMarker() {
        if let selected = selectedMarker {
            if playhead != selected {
                if let del = delegate {
                    del.assetEditorDidDeselect(editor: self, marker: selectedMarker!, at: selectedMarkerIdx!)
                }
                selectedMarker = nil
                selectedMarkerIdx = nil
            }
        }
        if let idx = markers.firstIndex(of: playhead) {
            if idx != selectedMarkerIdx {
                selectedMarkerIdx = idx
                selectedMarker = markers[idx]
                if let del = delegate {
                    del.assetEditorDidSelect(editor: self, marker: selectedMarker!, at: selectedMarkerIdx!)
                }
            }
        }
    }
    
    func deleteSelectedMarker() {
        if let idx = selectedMarkerIdx {
            markers.remove(at: idx)
            if let del = delegate {
                del.assetEditorDidDeselect(editor: self, marker: selectedMarker!, at: selectedMarkerIdx!)
            }
            selectedMarkerIdx = nil
            selectedMarker = nil
            setNeedsDisplay()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .draggingMarker || touchState == .zooming || activeTouches.count >= 2 {
            return
        }
        
        if touchState == .none {
            if touches.count == 1 {
                let touch = touches[touches.startIndex]
                let location = touch.location(in: self)
                if location.y <= gutterHeight || location.y >= bounds.size.height - gutterHeight {
                    // In the gutter
                    
                    let trimmerDistanceThreshold = markerWidth * 1.5 // in pixels, a little bigger than standard markers
                    let startTrimmerX = xPositionForUnit(trimmedRange.start)
                    let endTrimmerX = xPositionForUnit(trimmedRange.end)
                    
                    
                    if let (idx, _) = markerForXPosition(location.x) {
                        touchState = .draggingMarker
                        draggingMarkerIdx = idx
                        playhead = markers[draggingMarkerIdx]
                        activeTouches.insert(touch)
                        setNeedsDisplay()
                    }
                    else if startTrimmerX != nil && abs(startTrimmerX! - location.x) < trimmerDistanceThreshold {
                        touchState = .draggingStartTrimmer
                        playhead = trimmedRange.start
                        activeTouches.insert(touch)
                        setNeedsDisplay()
                    }
                    else if endTrimmerX != nil && abs(endTrimmerX! - location.x) < trimmerDistanceThreshold {
                        touchState = .draggingEndTrimmer
                        playhead = trimmedRange.end
                        activeTouches.insert(touch)
                        setNeedsDisplay()
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
                                if let del = delegate {
                                    del.assetEditorTappedPlayButton(for: self, range: activePlayButtonRegion)
                                }
                                break
                            } 
                        }
                    }
                }
                else {
                    // Move the playhead
                    touchState = .draggingPlayhead
                    activeTouches.insert(touch)
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
                    
                    // Don't go outside trimmer bounds
                    if playhead < trimmedRange.start {
                        playhead = trimmedRange.start 
                    }
                    else if playhead > trimmedRange.end {
                        playhead = trimmedRange.end
                    }
                    
                    // Snap to nearby marker
                    let snappingThresholdInPixels = CGFloat(16.0)
                    if let (_, markerToSnapTo) = markerForXPosition(xPositionForUnit(playhead)!, thresholdInPixels: snappingThresholdInPixels) {
                        playhead = markerToSnapTo
                    }
                    
                    self.setNeedsDisplay()
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
                pinchBeginVisibleRangeSize = visibleRange.size
                let midpoint = (location1.x + location2.x) / 2.0
                centerPinchUnit = unitForXPosition(midpoint)
                touchState = .zooming
                activeTouches.insert(touch1)
                activeTouches.insert(touch2)
            }
        }
        else {
            // Already in .ignoring state
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
            pinchBeginVisibleRangeSize = visibleRange.size
            let midpoint = (location1.x + location2.x) / 2.0
            centerPinchUnit = unitForXPosition(midpoint)
            touchState = .zooming
            activeTouches.insert(touch1)
            activeTouches.insert(touch2)
            panStartUnit = nil
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .none || touchState == .ignoring || touchState == .touchingPlayButton || activeTouches.intersection(touches).isEmpty { return }
        
        let minMarkerSeparationInPixels : CGFloat = markerWidth + 2.0
        let minMarkerSeparationInUnits = Int(minMarkerSeparationInPixels * unitsPerPixel)
        
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
            
            // Don't go outside trimmer bounds
            if playhead < trimmedRange.start {
               playhead = trimmedRange.start 
            }
            else if playhead > trimmedRange.end {
                playhead = trimmedRange.end
            }
            
            // Snap to nearby marker
            let snappingThresholdInPixels = CGFloat(16.0)
            if let (_, markerToSnapTo) = markerForXPosition(xPositionForUnit(playhead)!, thresholdInPixels: snappingThresholdInPixels) {
                playhead = markerToSnapTo
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
            
            // Don't drag past first marker (or end trimmer)
            let maxUnit = markers.count > 0 ? markers[0] - minMarkerSeparationInUnits : trimmedRange.end - minMarkerSeparationInUnits
            if trimmedRange.start > maxUnit {
                trimmedRange.start = maxUnit
            }
            
            if trimmedRange.start < 0 {
                trimmedRange.start = 0
            }
            
            // Update playhead
            playhead = trimmedRange.start
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
            
            // Don't drag past last marker (or start trimmer)
            let minUnit = markers.count > 0 ? markers[markers.count - 1] + minMarkerSeparationInUnits : trimmedRange.start + minMarkerSeparationInUnits
            if trimmedRange.end < minUnit {
                trimmedRange.end = minUnit
            }
            
            if trimmedRange.end > totalRange.end {
                trimmedRange.end = totalRange.end
            }
            
            // Update playhead
            playhead = trimmedRange.end
            self.setNeedsDisplay()
        }
        else if touchState == .draggingMarker {
            let touch = activeTouches.first!
            let location = touch.location(in: self)
            
            var draggableRange = EditorRange(trimmedRange.start + minMarkerSeparationInUnits, trimmedRange.end - minMarkerSeparationInUnits)
            if draggingMarkerIdx > 0 {
                if markers[draggingMarkerIdx - 1] > visibleRange.start {
                    draggableRange.start = markers[draggingMarkerIdx - 1] + minMarkerSeparationInUnits
                }
                else {
                    draggableRange.start = unitForXPosition(0)!
                }
            }
            if draggingMarkerIdx < markers.count - 1 {
                if markers[draggingMarkerIdx + 1] < visibleRange.end {
                    draggableRange.end = markers[draggingMarkerIdx + 1] - minMarkerSeparationInUnits
                }
                else {
                    draggableRange.end = unitForXPosition(bounds.size.width)!
                }
            }
            
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
            
            let newMarker = markers[draggingMarkerIdx]
            if newMarker < draggableRange.start {
                markers[draggingMarkerIdx] = draggableRange.start
            }
            else if newMarker > draggableRange.end {
                markers[draggingMarkerIdx] = draggableRange.end
            }
            
            // Update playhead
            playhead = markers[draggingMarkerIdx]
            self.setNeedsDisplay()
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
            
            let totalUnitsInWindow = Int(CGFloat(pinchBeginVisibleRangeSize) / scale)
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
            if let del = delegate {
                del.assetEditorMovedToRange(editor: self, range: visibleRange)
            }
            
            // Check for selection
            setNeedsDisplay()
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchState == .touchingPlayButton && activeTouches.intersection(touches).count == 1 {
            if touchState == .touchingPlayButton {
                // We don't check for touch up inside, since we want to start/cancel playback no matter what
                if let del = delegate {
                    del.assetEditorReleasedPlayButton(for: self, range: activePlayButtonRegion)
                }
                
            }
        }
        activeTouches.subtract(touches)
        if activeTouches.count == 0 {
            touchState = .none
            draggingMarkerIdx = nil
            panStartUnit = nil
            firstPinchDistance = nil
            pinchBeginVisibleRangeSize = nil
            centerPinchUnit = nil
            activePlayButtonRegion = nil
            markers.sort() // In the case that we moved one marker past another, resort them
        }
        else if touchState == .zooming && activeTouches.count == 1 {
            // Transition to ignoring touch input until a second touch returns 
            touchState = .ignoring
            firstPinchDistance = nil
            pinchBeginVisibleRangeSize = nil
            centerPinchUnit = nil
        }
        if let del = delegate {
            del.assetEditorMovedToRange(editor: self, range: visibleRange)
        }
        
        // Check for deselection
        updateSelectedMarker()
        
        setNeedsDisplay()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouches.removeAll()
        touchState = .none
        draggingMarkerIdx = nil
        panStartUnit = nil
        firstPinchDistance = nil
        pinchBeginVisibleRangeSize = nil
        centerPinchUnit = nil
    }
    
    override func draw(_ rect: CGRect) {
          
        let context = UIGraphicsGetCurrentContext()!
        
        // Draw the trimmers and markers
        context.setLineWidth(2.0)
        if showMarkers {
            
            // Grey out the trimmed out regions, if necessary
            if trimmedRange.start >= visibleRange.start {
                context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
                if let trimmerPosition = xPositionForUnit(trimmedRange.start) {
                    let rect = CGRect(x: 0, y: gutterHeight, width: trimmerPosition, height: bounds.height - (2.0 * gutterHeight))
                    context.fill(rect)
                }
                else {
                    // The trimmer is ahead of the current region, so grey the whole visible area
                    let rect = CGRect(x: 0, y: gutterHeight, width: bounds.width, height: bounds.height - (2.0 * gutterHeight))
                    context.fill(rect)
                }
            }
            if trimmedRange.end <= visibleRange.end {
                context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.7)
                if let trimmerPosition = xPositionForUnit(trimmedRange.end) {
                    let rect = CGRect(x: trimmerPosition, y: gutterHeight, width: bounds.width - trimmerPosition, height: bounds.height - (2.0 * gutterHeight))
                    context.fill(rect)
                }
                else {
                    // The trimmer is before the current region, so grey the whole visible area
                    let rect = CGRect(x: 0, y: gutterHeight, width: bounds.width, height: bounds.height - (2.0 * gutterHeight))
                    context.fill(rect)
                }
            }
            
            let markerColor = UIColor.red
            context.setStrokeColor(markerColor.cgColor)
            context.setFillColor(markerColor.cgColor)
            
            // Start Trimmer
            if let startTrimX = xPositionForUnit(trimmedRange.start) {
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
            }
            
            // End Trimmer
            if let endTrimX = xPositionForUnit(trimmedRange.end) {
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
            }
            
            var highlightedMarker : Marker? = nil
            var highlightedMarkerIdx : Int? = nil
            for (idx, marker) in markers.enumerated() {
                if let markerX = xPositionForUnit(marker) {
                    if marker == playhead {
                        // Draw the highlighted marker last
                        highlightedMarker = marker
                        highlightedMarkerIdx = idx
                        continue
                    }
                    else {
                        let label = "\(idx + 1)" // Scratch uses 1-based indexing
                        drawMarker(at: markerX, in: context, rect: rect, color: markerColor, textColor: UIColor.white, label: label)
                    }
                }
            }
            
            if let highlighted = highlightedMarker, let idx = highlightedMarkerIdx {
                let markerX = xPositionForUnit(highlighted)!
                let label = "\(idx + 1)" // Scratch uses 1-based indexing
                drawMarker(at: markerX, in: context, rect: rect, color: UIColor.yellow, textColor: UIColor.black, label: label)
            }
            
            // Draw play symbols
            context.setFillColor(UIColor.white.cgColor)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineDash(phase: 0, lengths: [])
            context.setLineWidth(2.0)
            let playButtonRadius = gutterHeight * (2.0 / 5.0)
            let ranges = rangesForVisibleRegions()
            for range in ranges {
                let rangeWidthInPixels = pixelsPerUnit * CGFloat(range.end - range.start)
                if rangeWidthInPixels < (2.0 * playButtonRadius) + markerWidth + 4.0 { continue } // Don't draw if not enough space
                let midUnit = Int(CGFloat(range.start + range.end) / 2.0)
                if let midpoint = xPositionForUnit(midUnit) {
                    let playButtonCenter = CGPoint(x: midpoint, y: bounds.height - (gutterHeight / 2.0))
                    var playButtonRect = CGRect(origin: playButtonCenter, size: .zero)
                    playButtonRect = playButtonRect.insetBy(dx: -playButtonRadius, dy: -playButtonRadius)
                    context.addEllipse(in: playButtonRect)
                    context.strokePath()
                    // Play Symbol
                    context.beginPath()
                    context.move(to: CGPoint(x: playButtonCenter.x + playButtonRadius / 3.0, y: playButtonCenter.y))
                    context.addLine(to: CGPoint(x: playButtonCenter.x - playButtonRadius / 4.0, y: playButtonCenter.y + playButtonRadius / 3.0))
                    context.addLine(to: CGPoint(x: playButtonCenter.x - playButtonRadius / 4.0, y: playButtonCenter.y - playButtonRadius / 3.0))
                    context.closePath()
                    context.fillPath()
                }
            }
        }
        
        // Draw the playhead
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
    
    func drawMarker(at markerX: CGFloat, in context: CGContext, rect: CGRect, color: UIColor, textColor: UIColor, label: String) {
        context.setLineDash(phase: 0, lengths: [10.0, 3.0])
        
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs : [NSAttributedString.Key : Any] = [.font : UIFont.systemFont(ofSize: gutterHeight * (1.0 / 2.0)), .paragraphStyle : paragraphStyle, .foregroundColor : textColor]
        label.draw(with: CGRect(x: CGFloat(markerX) - (markerWidth / 2.0), y: (markerHeight * 0.1), width: markerWidth, height: (markerHeight * 0.9)), options:.usesLineFragmentOrigin, attributes: attrs, context: nil)
        label.draw(with: CGRect(x: CGFloat(markerX) - (markerWidth / 2.0), y: bounds.size.height - (markerHeight * 0.75), width: markerWidth, height: markerHeight), options:.usesLineFragmentOrigin, attributes: attrs, context: nil)
    }
    
}

