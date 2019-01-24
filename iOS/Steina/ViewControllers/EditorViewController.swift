//
//  EditorViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/10/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import WebKit
import Dispatch
import simd

class EditorViewController: UIViewController,
                            UIWebViewDelegate,
                            MetalViewDelegate,
                            ClipsCollectionViewControllerDelegate, 
                            CaptureViewControllerDelegate,
                            AudioCaptureViewControllerDelegate {
    
    var project : Project! = nil
    var selectedAssetId : AssetId? = nil
    
    var displayLink : CADisplayLink! = nil
    var ready = false
    var draggingVideoId : ClipId! = nil
    var dragStartTimestamp : CFTimeInterval! = nil
    var previousRenderedIds : [ClipId] = []
    var renderedIds : [ClipId] = []
    var renderingQueue : DispatchQueue = DispatchQueue(label: "edu.mit.media.llk.Steina.Render", qos: .default, attributes: .concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem, target: nil)
    let renderDispatchGroup = DispatchGroup()
    let unproject = orthographicUnprojection(left: -320.0, right: 320.0, top: 240.0, bottom: -240.0, near: 1.0, far: -1.0)
    
    @IBOutlet weak var metalView: MetalView!
    @IBOutlet weak var webViewContainer: UIView!
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet weak var greenFlagButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var micButton: UIButton!
    @IBOutlet weak var toolbarView: UIView!
    @IBOutlet weak var assetsView: UIView!
    @IBOutlet weak var projectsButton: UIButton!
    @IBOutlet weak var projectsButtonBackground: UIImageView!
    @IBOutlet weak var stopGreenFlagButtonBackground: UIImageView!
    @IBOutlet weak var rotateHelpIcon: UIView!
    @IBOutlet weak var helpArrowTop: UIImageView!
    @IBOutlet weak var helpArrowBottom: UIImageView!
    
    
    var webView: UIWebView! = nil
    var clipsCollectionVC : ClipsCollectionViewController? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Move the loading view to cover the whole screen.
        // We do this in code instead of the storyboard so that
        // we don't have to move the loading view in the storyboard
        // to make changes to other UI elements
        loadingView.frame = CGRect(origin: .zero, size: loadingView.frame.size)
        
        // Load clips and sounds into memory
        if !project.assetsLoaded {
            loadProjectAssets(project)
        }
        
        metalView.metalLayer.drawableSize = CGSize(width: 640, height: 480)
        metalView.delegate = self
        
        initMetal(metalView)
        
        // Init webview and load editor
        webView = UIWebView(frame: self.webViewContainer.bounds)
        webView.delegate = self
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Add subview
        self.webViewContainer!.addSubview(webView)

        // Load blocks editor
        let indexPage = Bundle.main.url(forResource: "web/index", withExtension: "html")!
        
        webView.loadRequest(URLRequest(url: indexPage))
    }
    
    func webViewDidFinishLoad(_ webView: UIWebView) {
        onScratchLoaded()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        arrangeViewsForSize(view.bounds.size)
        changeAudioOutputSource(.project)
        if ready {
            onReady()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        runJavascript("vm.stopAll()")
        stopDisplayLink()
        clearAudioBuffer()
        saveProject()
        super.viewWillDisappear(animated)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { (_) in
            self.arrangeViewsForSize(size)
        }, completion: { (_) in 
            self.updateHelpAnimations()
        })
    }
    
    func arrangeViewsForSize(_ size: CGSize) {
        if size.width < size.height {
            // Portrait
            self.toolbarView.backgroundColor = UIColor(red: 40.0 / 255.0, green: 56.0 / 255.0, blue: 86.0 / 255.0, alpha: 1.0)
            self.projectsButton.alpha = 1.0
            self.projectsButtonBackground.alpha = 1.0
            self.stopGreenFlagButtonBackground.alpha = 1.0
            self.webViewContainer.alpha = 1.0
            self.assetsView.alpha = 1.0
            self.rotateHelpIcon.alpha = 0.0
            let remainingHeight = size.height - self.toolbarView.frame.size.height - self.webViewContainer.frame.size.height
            let aspectWidth = ceil((4.0 / 3.0) * remainingHeight)
            let x = size.width - aspectWidth
            self.metalView.frame = CGRect(x: x, y: self.toolbarView.frame.size.height, width: aspectWidth, height: remainingHeight)
        }
        else {
            // Landscape
            self.toolbarView.backgroundColor = UIColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 24.0 / 255.0, alpha: 1.0)
            self.projectsButton.alpha = 0.0
            self.projectsButtonBackground.alpha = 0.0
            self.stopGreenFlagButtonBackground.alpha = 0.0
            self.webViewContainer.alpha = 0.0
            self.assetsView.alpha = 0.0
            let height = size.height  - self.toolbarView.bounds.size.height
            let aspectWidth = ceil((4.0 / 3.0) * height)
            let x = (size.width - aspectWidth) / 2.0
            self.metalView.frame = CGRect(x: x, y: self.toolbarView.bounds.size.height, width: aspectWidth, height: height)
        }
    }
    
    func onScratchLoaded() {
        let projectJson = loadProjectJson(project)
        let js = "Steina.loadProject('\(projectJson)')"
        runJavascript(js)
        self.ready = true
        self.onReady()
        UIView.animate(withDuration: 0.5, animations: { 
            self.loadingView.alpha = 0.0
        }, completion: { (_) in
            self.loadingView.isHidden = true
            self.updateHelpAnimations()
        })
    }
    
    func updateHelpAnimations() {
        if self.project.clips.count == 0 && self.project.sounds.count == 0 {
            if self.view.bounds.size.width < self.view.bounds.size.height {
                // Portrait
                self.helpArrowTop.isHidden = false
                self.helpArrowBottom.isHidden = false
                self.helpArrowTop.center.x = 102
                self.helpArrowBottom.center.x = 102
                UIView.animate(withDuration: 0.5, delay: 0, options: [.repeat, .autoreverse, .curveEaseInOut], animations: { 
                    self.helpArrowTop.center.x += 15
                    self.helpArrowBottom.center.x += 15
                }, completion: nil)
            }
            else {
                // Landscape
                self.rotateHelpIcon.alpha = 0.0
                self.rotateHelpIcon.isHidden = false
                UIView.animate(withDuration: 1.5, animations: { 
                    self.rotateHelpIcon.alpha = 1.0
                })
            }
        }
        else {
            self.rotateHelpIcon.alpha = 0.0
            self.rotateHelpIcon.isHidden = true
            self.helpArrowTop.isHidden = true
            self.helpArrowBottom.isHidden = true
        }
    }
    
    func saveProject() {
        project.thumbnail = getLastRenderedImage()
        saveProjectThumbnail(project)
        let projectJson = runJavascript("Steina.getProjectJson()")
        saveProjectJson(self.project, projectJson!) 
    }
    
    func onReady() {
        if let clipsVC = clipsCollectionVC {
            clipsVC.project = project
            clipsVC.collectionView?.reloadData()
        }
        startDisplayLink()
    }
    
    func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .current, forMode: .defaultRunLoopMode)
    }
    
    func stopDisplayLink() {
        displayLink.remove(from: .current, forMode: .defaultRunLoopMode)
    }
    
    @inline(__always) @discardableResult
    func runJavascript(_ js: String) -> String? {
        return webView!.stringByEvaluatingJavaScript(from: js)
    }
    
    @IBAction func backButtonTapped(_ sender: Any) {
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func greenFlagButtonTapped(_ sender: Any) {
        runJavascript("vm.greenFlag()")
    }
    
    @IBAction func stopButtonTapped(_ sender: Any) {
        runJavascript("vm.stopAll()")
        saveProject()
    }
    
    @IBAction func trashButtonTapped(_ sender: Any) {
        if let selected = selectedAssetId {
            let nextSelectedId = runJavascript("Steina.deleteTarget(\"\(selected)\")")
            deleteProjectAsset(project, selected)
            clipsCollectionVC!.collectionView!.reloadData()
            if let nextId = nextSelectedId {
                clipsCollectionVC!.selectAsset(nextId)
            }
            updateHelpAnimations() // If the last asset gets deleted, trigger the help animations again
            saveProject()
        }
    }
    
    @IBAction func duplicateButtonTapped(_ sender: Any) {
        if let selected = selectedAssetId {
            let newId = UUID().uuidString
            runJavascript("Steina.duplicateTarget(\"\(selected)\", \"\(newId)\")")
            duplicateProjectAsset(project, selected, newId)
            clipsCollectionVC!.collectionView!.reloadData()
            clipsCollectionVC!.selectAsset(newId)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let clipsVC = segue.destination as? ClipsCollectionViewController {
            clipsVC.delegate = self
            clipsVC.project = project
            self.clipsCollectionVC = clipsVC
        }
        else if let captureVC = segue.destination as? CaptureViewController {
            captureVC.delegate = self
            captureVC.project = project
        }
        else if let audioCaptureVC = segue.destination as? AudioCaptureViewController {
            audioCaptureVC.delegate = self
        }
    }
    
    var nextRenderTimestamp = 0.0
    var lastTargetTimestamp = 0.0
    
    // Create audio mixing buffer
    let mixingBuffer = Data(count: MemoryLayout<Float>.size * 4800) // We allocate enough for 3 frames of audio and hard cap it there
    
    @objc func tick(_ sender: CADisplayLink) {
        
        DEBUGBeginTimedBlock("Frame")
        
        let dt = sender.targetTimestamp - lastTargetTimestamp
        
        // @TODO This probably isn't the best way to deal with dropped video frames in the audio stream
        //       but it's an (arguably) reasonable first approximation
        if dt > 0.1 {
            print("frame too long. dt: \(dt * 1000.0)")
            nextRenderTimestamp = sender.targetTimestamp
        }
        lastTargetTimestamp = sender.targetTimestamp
        previousRenderedIds = renderedIds
        renderedIds = []
        
        self.renderDispatchGroup.wait()
        DEBUGBeginTimedBlock("JS")
        let renderingStateJson = runJavascript("Steina.tick(\(dt * 1000.0)); Steina.getRenderingState()")!
        DEBUGEndTimedBlock("JS")
        
        if renderingStateJson != "" {
            
            let renderingState = try! JSONSerialization.jsonObject(with: renderingStateJson.data(using: .utf8)!, options: [])
            
            if let json = renderingState as? Dictionary<String, Any> {
                let videoTargets = json["videoTargets"] as! Array<Dictionary<String, Any>>
                let audioTargets = json["audioTargets"] as! Dictionary<String, Dictionary<String, Any>>
                let playingSounds = json["playingSounds"] as! Dictionary<String, Dictionary<String, Any>>
                
                /*****************
                 * Render Audio
                 *****************/
                
                DEBUGBeginTimedBlock("Audio Render")
                
                memset(mixingBuffer.bytes, 0, MemoryLayout<Float>.size * 4800)
                let rawMixingBuffer = mixingBuffer.bytes.bindMemory(to: Float.self, capacity: 4800)
                
                
                for (_, sound) in playingSounds {
                    // Get properties
                    let soundAssetId   = (sound["audioTargetId"] as! String)
                    let start          = Int(floor((sound["prevPlayhead"] as! NSNumber).floatValue))
                    let end            = Int(ceil((sound["playhead"] as! NSNumber).floatValue))
                    
                    // Get samples
                    let totalSamples = min(end - start, 4800);
                    let asset = self.project.sounds[soundAssetId]!
                    let samples = fetchSamples(asset, start, end)
                    
                    let target = audioTargets[soundAssetId]!
                    let volume = (target["volume"] as! NSNumber).floatValue / Float(100.0)
                    
                    // Mix into buffer
                    let rawSamples = samples.bytes.bindMemory(to: Int16.self, capacity: totalSamples)
                    for i in 0..<totalSamples {
                        rawMixingBuffer[i] += Float(rawSamples[i]) * volume
                    }
                }
                
                DEBUGBeginTimedBlock("Audio Write")
                // Copy samples to audio output buffer
                writeFloatSamples(mixingBuffer, forHostTime: hostTimeForTimestamp(self.nextRenderTimestamp))
                DEBUGEndTimedBlock("Audio Write")
                
                self.nextRenderTimestamp += dt
                
                DEBUGEndTimedBlock("Audio Render")
                
                /*****************
                 * Render Video
                 *****************/
                DEBUGBeginTimedBlock("Video Render")
                
                var numEntitiesToRender = 0
                var draggingRenderFrame : RenderFrame? = nil
                for target in videoTargets {
                    // Check for visibility, bail early if nothing to render
                    let visible = target["visible"] as! Bool
                    if !visible { continue; } // Don't render anything if the video isn't visible
                    
                    // Get target properties
                    let clipId    = (target["id"] as! String)
                    let frame     = (target["currentFrame"] as! NSNumber).floatValue
                    let x         = (target["x"] as! NSNumber).floatValue
                    let y         = (target["y"] as! NSNumber).floatValue
                    let size      = (target["size"] as! NSNumber).floatValue
                    let direction = (target["direction"] as! NSNumber).floatValue
                    let effects   = (target["effects"] as! Dictionary<String, NSNumber>) // We implicitly cast effects values to floats here
                    
                    // Get video clip
                    let videoClip = self.project.clips[clipId]!
                    
                    // Figure out which frame to render
                    var frameNumber = Int(round(frame))
                    if frameNumber >= videoClip.frames {
                        frameNumber = Int(videoClip.frames) - 1;
                    }
                    
                    // Compute the proper model transform
                    let scale = (size / 100.0)
                    let theta = (direction - 90.0) * (.pi / 180.0)
                    let transform = entityTransform(scale: scale, rotate: theta, translateX: x, translateY: y)
                    
                    // Create the effects structure
                    let colorEffect      = effects["color"]!.floatValue / 360.0
                    let whirlEffect      = effects["whirl"]!.floatValue / 360.0
                    let brightnessEffect = effects["brightness"]!.floatValue / 100.0
                    let ghostEffect      = 1.0 - (effects["ghost"]!.floatValue / 100.0)
                    let renderingEffects = VideoEffects(color: colorEffect, whirl: whirlEffect, brightness: brightnessEffect, ghost: ghostEffect)
                    
                    // Create the render frame structure
                    let renderFrame = RenderFrame(clip: videoClip, frameNumber: frameNumber, transform: transform, effects: renderingEffects)
                    
                    // If a target is being dragged, we defer drawing it until the end so that it draws on top of everything else
                    if self.draggingVideoId == clipId {
                        draggingRenderFrame = renderFrame
                        continue
                    }
                    
                    // Push the render frame into the rendering queue
                    self.renderedIds.append(clipId)
                    self.renderDispatchGroup.enter()
                    let entityIndex = numEntitiesToRender
                    self.renderingQueue.async {                        
                        pushRenderFrame(renderFrame, at: entityIndex)
                        self.renderDispatchGroup.leave()
                    }
                    numEntitiesToRender += 1
                }
                
                // Push the dragging target into the rendering queue, if it exists
                if let draggingFrame = draggingRenderFrame {
                    self.renderedIds.append(draggingFrame.clip.id.uuidString)
                    self.renderDispatchGroup.enter()
                    let entityIndex = numEntitiesToRender
                    self.renderingQueue.async {                        
                        pushRenderFrame(draggingFrame, at: entityIndex)
                        self.renderDispatchGroup.leave()
                    }
                    numEntitiesToRender += 1
                }
                
                self.renderDispatchGroup.wait()
                DEBUGEndTimedBlock("Video Render")
                
                DEBUGBeginTimedBlock("GPU Kickoff")
                render(numEntitiesToRender)
                DEBUGEndTimedBlock("GPU Kickoff")
            }
            
        }
        
        DEBUGEndTimedBlock("Frame")
    }
    
    /**********************************************************************
     *
     * MetalViewDelegate
     *
     **********************************************************************/
    
    func metalViewBeganTouch(_ metalView: MetalView, location: CGPoint) {
        
        let drawableSize = metalView.metalLayer.drawableSize
        let x = (location.x / metalView.bounds.size.width) * (drawableSize.width)
        let y = (location.y / metalView.bounds.size.height) * (drawableSize.height)
        
        if let draggingId = videoTargetAtLocation(CGPoint(x: x, y: y)) {
            
            let projectedX = (2.0 * (location.x / metalView.bounds.size.width)) - 1.0
            let projectedY = ((2.0 * (location.y / metalView.bounds.size.height)) - 1.0) * -1.0 // Invert y
            let unprojected = unproject * float4(Float(projectedX), Float(projectedY), 1.0, 1.0)
            
            dragStartTimestamp = CACurrentMediaTime()
            draggingVideoId = draggingId        
            runJavascript("Steina.beginDraggingVideo('\(draggingVideoId!)', \(unprojected.x), \(unprojected.y))")
        }
    }
    
    func metalViewMovedTouch(_ metalView: MetalView, location: CGPoint) {
        guard draggingVideoId != nil else { return }
        
        let x = (2.0 * (location.x / metalView.bounds.size.width)) - 1.0
        let y = ((2.0 * (location.y / metalView.bounds.size.height)) - 1.0) * -1.0 // Invert y
        let unprojected = unproject * float4(Float(x), Float(y), 1.0, 1.0)
        runJavascript("Steina.updateDraggingVideo('\(draggingVideoId!)', \(unprojected.x), \(unprojected.y))")
    }
    
    func metalViewEndedTouch(_ metalView: MetalView, location: CGPoint) {
        guard draggingVideoId != nil else { return }
        
        var shouldUpdateDragTarget = true
        if CACurrentMediaTime() - dragStartTimestamp < 0.25 {
            runJavascript("Steina.tapVideo('\(draggingVideoId!)')")
            shouldUpdateDragTarget = false;
        }
        
        runJavascript("Steina.endDraggingVideo('\(draggingVideoId!)', \(shouldUpdateDragTarget ? "true" : "false"))")
        if shouldUpdateDragTarget {
            if let clipsVC = self.clipsCollectionVC, let idx = self.project.clipIds.index(of: draggingVideoId) {
                clipsVC.collectionView!.selectItem(at: IndexPath(item: idx, section: 0), animated: true, scrollPosition: .centeredHorizontally)
            }
        }
        
        dragStartTimestamp = nil
        draggingVideoId = nil
    }
    
    func videoTargetAtLocation(_ location: CGPoint) -> ClipId? {
        let pixels : RawPtr = RawPtr.allocate(byteCount: 1, alignment: MemoryLayout<Float>.alignment)
        depthTex.getBytes(pixels, bytesPerRow: 1024, from: MTLRegionMake2D(Int(location.x), Int(location.y), 1, 1), mipmapLevel: 0)
        let val = pixels.bindMemory(to: Float.self, capacity: 1)[0]
        if (val == 1.0) {
            return nil
        }
        let idx = indexForZValue(val)
        if idx >= previousRenderedIds.count {
            return nil
        }
        let id = previousRenderedIds[idx]
        return id
    }
    
    
    /**********************************************************************
     *
     * ClipsCollectionViewControllerDelegate
     *
     **********************************************************************/
    
    // @TODO: Should we implement deselection as well?
    func clipsControllerDidSelect(clipsController: ClipsCollectionViewController, assetId: AssetId) {
        runJavascript("vm.setEditingTarget(\"\(assetId)\")")
        selectedAssetId = assetId
    }
    
    
    /**********************************************************************
     *
     * CaptureViewControllerDelegate
     *
     **********************************************************************/
    
    func captureViewControllerDidCreateClip(captureViewController: CaptureViewController, clip: Clip) {
        runJavascript("Steina.createVideoTarget(\"\(clip.id.uuidString)\", 30, \(clip.frames));")
        updateHelpAnimations()
    }
    
    /**********************************************************************
     *
     * AudioCaptureViewControllerDelegate
     *
     **********************************************************************/
    
    func audioCaptureViewControllerDidCreateSound(_ sound: Sound) {
        if sound.length == 0 { return }
        
        if sound.project == nil {
            addSoundToProject(sound, project)
        }
        saveSound(sound)
        
        let markersString = "[\(sound.markers.map({ String($0) }).joined(separator: ","))]"
        runJavascript("Steina.createAudioTarget(\"\(sound.id.uuidString)\", {totalSamples: \(sound.length), markers: \(markersString) })")
        updateHelpAnimations()
    }
    
}
