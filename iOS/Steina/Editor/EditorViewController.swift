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

struct MetalViewTouchState {
    enum VideoTargetState {
        case none
        case dragging
        case transforming
    }
    var activeTouches : [UITouch] = []
    var videoTargetState = VideoTargetState.none
    var videoTargetId : ClipId! = nil
    
    // Single finger dragging
    var initialDragOffset : CGPoint! = nil
    var dragStartTimestamp : CFTimeInterval? = nil
    
    // Two finger transform
    var initialPosition : CGPoint! = nil
    var initialRotation : CGFloat! = nil
    var initialScale : CGFloat! = nil
    
    var initialTouchDistance : CGFloat! = nil
    var initialTouchAngle : CGFloat! = nil
    var initialTouchMidpoint : CGPoint! = nil
}

class EditorViewController: UIViewController,
                            UIWebViewDelegate,
                            MetalViewDelegate,
                            ClipsCollectionViewControllerDelegate, 
                            VideoCaptureViewControllerDelegate,
                            AudioCaptureViewControllerDelegate,
                            VideoEditorViewControllerDelegate {  // Only used for editing clips, not when creating them in the first place
    
    var project : Project! = nil
    var selectedAssetId : AssetId? = nil
    
    var displayLink : CADisplayLink! = nil
    var ready = false
    
    var touchState = MetalViewTouchState()
    var previousRenderedIds : [ClipId] = []
    var renderedIds : [ClipId] = []
    var renderingQueue : DispatchQueue = DispatchQueue(label: "edu.mit.media.llk.Bricoleur.Render", qos: .default, attributes: .concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem, target: nil)
    let renderDispatchGroup = DispatchGroup()
    let unprojection = orthographicUnprojection(left: -320.0, right: 320.0, top: 240.0, bottom: -240.0, near: 1.0, far: -1.0)
    
    var webView: UIWebView! = nil
    var clipsCollectionVC : ClipsCollectionViewController? = nil
    
    // Audio
    var nextRenderTimestamp = 0.0
    var lastTargetTimestamp = 0.0
    let mixingBuffer = Data(count: MemoryLayout<Float>.size * 4800) // We allocate enough for 3 frames of audio and hard cap it there
    
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
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var shareButtonBackground: UIImageView!
    @IBOutlet weak var stopGreenFlagButtonBackground: UIImageView!
    @IBOutlet weak var rotateHelpIcon: UIView!
    @IBOutlet weak var helpArrowTop: UIImageView!
    @IBOutlet weak var helpArrowBottom: UIImageView!
    
    
    /**********************************************************************
     *
     * Lifecycle
     *
     **********************************************************************/
    
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let clipsVC = segue.destination as? ClipsCollectionViewController {
            clipsVC.delegate = self
            clipsVC.project = project
            self.clipsCollectionVC = clipsVC
        }
        else if let captureVC = segue.destination as? VideoCaptureViewController {
            captureVC.delegate = self
            captureVC.project = project
        }
        else if let audioCaptureVC = segue.destination as? AudioCaptureViewController {
            audioCaptureVC.delegate = self
        }
    }
    
    func arrangeViewsForSize(_ size: CGSize) {
        if size.width < size.height {
            // Portrait
            self.toolbarView.backgroundColor = UIColor(red: 40.0 / 255.0, green: 56.0 / 255.0, blue: 86.0 / 255.0, alpha: 1.0)
            self.projectsButton.alpha = 1.0
            self.projectsButtonBackground.alpha = 1.0
            self.shareButton.alpha = 1.0
            self.shareButtonBackground.alpha = 1.0
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
            self.shareButton.alpha = 0.0
            self.shareButtonBackground.alpha = 0.0
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
    
    func onReady() {
        if let clipsVC = clipsCollectionVC {
            clipsVC.project = project
            clipsVC.collectionView?.reloadData()
        }
        startDisplayLink()
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
    
    func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .current, forMode: .defaultRunLoopMode)
    }
    
    func stopDisplayLink() {
        displayLink.remove(from: .current, forMode: .defaultRunLoopMode)
    }
    
    
    /**********************************************************************
     *
     * IBActions
     *
     **********************************************************************/
    
    @IBAction func backButtonTapped(_ sender: Any) {
        self.presentingViewController!.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func shareButtonTapped(_ sender: Any) {
        stopAndSave()
        let projectProvider = ProjectItemProvider(project: project)
        let sharingVC = UIActivityViewController(activityItems: [projectProvider], applicationActivities: nil)
        sharingVC.modalPresentationStyle = .popover
        sharingVC.popoverPresentationController?.sourceView = view
        sharingVC.popoverPresentationController?.sourceRect = shareButton.frame
        self.present(sharingVC, animated: true, completion: nil)
    }
    
    @IBAction func greenFlagButtonTapped(_ sender: Any) {
        runJavascript("vm.greenFlag()")
    }
    
    @IBAction func stopButtonTapped(_ sender: Any) {
        stopAndSave()
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
    
    @IBAction func editButtonTapped(_ sender: Any) {
        if let assetId = selectedAssetId {
            if project.clipIds.contains(assetId) {
                let videoClip = project.clips[assetId]
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                let videoEditorVC = storyboard.instantiateViewController(withIdentifier: "VideoEditor") as! VideoEditorViewController
                videoEditorVC.delegate = self
                videoEditorVC.clip = videoClip
                videoEditorVC.canRerecord = false
                self.present(videoEditorVC, animated: true, completion: nil)
            }
        }
    }
    
    /**********************************************************************
     *
     * The Goods
     *
     **********************************************************************/
    
    @inline(__always) @discardableResult
    func runJavascript(_ js: String) -> String? {
        return webView!.stringByEvaluatingJavaScript(from: js)
    }
    
    func saveProject() {
        project.thumbnail = getLastRenderedImage()
        saveProjectThumbnail(project)
        let projectJson = runJavascript("Steina.getProjectJson()")
        saveProjectJson(self.project, projectJson!) 
    }
    
    func stopAndSave() {
        runJavascript("vm.stopAll()")
        saveProject()
    }
    
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
                    if self.touchState.videoTargetId == clipId {
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
     * UIWebViewDelegate
     *
     **********************************************************************/
    
    func webViewDidFinishLoad(_ webView: UIWebView) {
        onScratchLoaded()
    }
    
    
    /**********************************************************************
     *
     * MetalViewDelegate
     *
     **********************************************************************/
    
    func metalViewBeganTouches(_ metalView: MetalView, _ touches: Set<UITouch>) {
        DEBUGBeginTimedBlock("Touch Began")
        
        let drawableSize = metalView.metalLayer.drawableSize
        
        // Trigger "when touched" hats
        for touch in touches {
            let location = touch.location(in: metalView)
            let x = (location.x / metalView.bounds.size.width) * (drawableSize.width)
            let y = (location.y / metalView.bounds.size.height) * (drawableSize.height)
            if let touchedTarget = videoTargetAtLocation(CGPoint(x: x, y: y)) {
                runJavascript("Steina.tapVideo('\(touchedTarget)')")
            }
        }
        
        if touchState.videoTargetState == .transforming { return }
        
        if touchState.videoTargetState == .none {
            if touches.count == 1 {
                let touch = touches.first!
                let location = touch.location(in: metalView)
                let x = (location.x / metalView.bounds.size.width) * (drawableSize.width)
                let y = (location.y / metalView.bounds.size.height) * (drawableSize.height)
                if let touchedTarget = videoTargetAtLocation(CGPoint(x: x, y: y)) {
                    // Begin dragging
                    touchState.activeTouches.append(touch)
                    touchState.videoTargetId = touchedTarget
                    touchState.videoTargetState = .dragging
                    
                    let transformJson = runJavascript("Steina.getDraggingVideoTransform('\(touchState.videoTargetId!)')")!
                    let transformObj = try! JSONSerialization.jsonObject(with: transformJson.data(using: .utf8)!, options: [])
                    
                    let transform = transformObj as! Dictionary<String, NSNumber>
                    let initialX = CGFloat(transform["x"]!.floatValue)
                    let initialY = CGFloat(transform["y"]!.floatValue)
                    
                    let unprojected = unproject(location: location, in: metalView)
                    touchState.initialDragOffset = CGPoint(x: CGFloat(unprojected.x) - initialX, y: CGFloat(unprojected.y) - initialY)
                    touchState.dragStartTimestamp = CACurrentMediaTime()
                    runJavascript("Steina.beginDraggingVideo('\(touchedTarget)')")
                }
            }
            else {
                // For now, just check the first two touches.
                // @TODO: I guess we could do some sort of thing where we check if any pair
                //        of touches is touching the same target? Seems like overkill for the moment, though
                let touch1 = touches[touches.startIndex]
                let touch2 = touches[touches.index(after: touches.startIndex)]
                let location1 = touch1.location(in: metalView)
                let location2 = touch2.location(in: metalView)
                let x1 = (location1.x / metalView.bounds.size.width) * (drawableSize.width)
                let y1 = (location1.y / metalView.bounds.size.height) * (drawableSize.height)
                let x2 = (location2.x / metalView.bounds.size.width) * (drawableSize.width)
                let y2 = (location2.y / metalView.bounds.size.height) * (drawableSize.height)
                let touchedTarget1 = videoTargetAtLocation(CGPoint(x: x1, y: y1))
                let touchedTarget2 = videoTargetAtLocation(CGPoint(x: x2, y: y2))
                
                if touchedTarget1 == nil && touchedTarget2 == nil { return }
                if touchedTarget1 == touchedTarget2 {
                    // Two-finger video touch: begin transforming
                    
                    touchState.videoTargetId = touchedTarget1
                    
                    let unprojected1 = unproject(location: location1, in: metalView)
                    let unprojected2 = unproject(location: location2, in: metalView)
                    
                    let transformJson = runJavascript("Steina.getDraggingVideoTransform('\(touchState.videoTargetId!)')")!
                    let transformObj = try! JSONSerialization.jsonObject(with: transformJson.data(using: .utf8)!, options: [])
                    
                    let transform = transformObj as! Dictionary<String, NSNumber>
                    let initialX = CGFloat(transform["x"]!.floatValue)
                    let initialY = CGFloat(transform["y"]!.floatValue)
                    let initialR = CGFloat(transform["rot"]!.floatValue)
                    let initialS = CGFloat(transform["scale"]!.floatValue)
                    
                    touchState.initialPosition = CGPoint(x: initialX, y: initialY)
                    touchState.initialRotation = initialR
                    touchState.initialScale = initialS
                    
                    touchState.initialTouchDistance = CGFloat(distance(unprojected1, unprojected2))
                    touchState.initialTouchAngle = radiansToDegrees(CGFloat(atan2(-(unprojected2.y - unprojected1.y), unprojected2.x - unprojected1.x)))
                    touchState.initialTouchMidpoint = CGPoint(x: CGFloat(unprojected1.x + unprojected2.x) / CGFloat(2.0), y: CGFloat(unprojected1.y + unprojected2.y) / CGFloat(2.0))
                    
                    touchState.activeTouches.append(touch1)
                    touchState.activeTouches.append(touch2)
                    touchState.videoTargetState = .transforming
                    
                    runJavascript("Steina.beginDraggingVideo('\(touchedTarget1!)')")
                }
                else {
                    // At least one of these is guaranteed to be not nil at this point
                    let touchedTarget = touchedTarget1 != nil ? touchedTarget1! : touchedTarget2!
                    let activeTouch   = touchedTarget1 != nil ? touch1 : touch2
                    let location      = touchedTarget1 != nil ? location1 : location2
                    
                    // Begin dragging
                    touchState.activeTouches.append(activeTouch)
                    touchState.videoTargetId = touchedTarget
                    touchState.videoTargetState = .dragging
                    
                    let transformJson = runJavascript("Steina.getDraggingVideoTransform('\(touchState.videoTargetId!)')")!
                    let transformObj = try! JSONSerialization.jsonObject(with: transformJson.data(using: .utf8)!, options: [])
                    
                    let transform = transformObj as! Dictionary<String, NSNumber>
                    let initialX = CGFloat(transform["x"]!.floatValue)
                    let initialY = CGFloat(transform["y"]!.floatValue)
                    
                    let unprojected = unproject(location: location, in: metalView)
                    touchState.initialDragOffset = CGPoint(x: CGFloat(unprojected.x) - initialX, y: CGFloat(unprojected.y) - initialY)
                    touchState.dragStartTimestamp = CACurrentMediaTime()
                    runJavascript("Steina.beginDraggingVideo('\(touchedTarget)')")
                }
            }
        }
        else {
            // Touch state is already dragging
            assert(touchState.videoTargetState == .dragging)
            
            let drawableSize = metalView.metalLayer.drawableSize
            
            let touch = touches.first!
            let location = touch.location(in: metalView)
            let x = (location.x / metalView.bounds.size.width) * (drawableSize.width)
            let y = (location.y / metalView.bounds.size.height) * (drawableSize.height)
            if let touchedTarget = videoTargetAtLocation(CGPoint(x: x, y: y)) {
                // If the new touch is touching the same target as the previous, begin transforming
                if touchedTarget == touchState.videoTargetId {
                    
                    let touch1 = touchState.activeTouches.first!
                    let touch2 = touch
                    let location1 = touch1.location(in: metalView)
                    let location2 = touch2.location(in: metalView)
                    let unprojected1 = unproject(location: location1, in: metalView)
                    let unprojected2 = unproject(location: location2, in: metalView)
                    
                    let transformJson = runJavascript("Steina.getDraggingVideoTransform('\(touchState.videoTargetId!)')")!
                    let transformObj = try! JSONSerialization.jsonObject(with: transformJson.data(using: .utf8)!, options: [])
                    
                    let transform = transformObj as! Dictionary<String, NSNumber>
                    let initialX = CGFloat(transform["x"]!.floatValue)
                    let initialY = CGFloat(transform["y"]!.floatValue)
                    let initialR = CGFloat(transform["rot"]!.floatValue)
                    let initialS = CGFloat(transform["scale"]!.floatValue)
                    
                    touchState.initialDragOffset = nil
                    touchState.dragStartTimestamp = nil
                    
                    touchState.initialPosition = CGPoint(x: initialX, y: initialY)
                    touchState.initialRotation = initialR
                    touchState.initialScale = initialS
                    
                    touchState.initialTouchDistance = CGFloat(distance(unprojected1, unprojected2))
                    touchState.initialTouchAngle = radiansToDegrees(CGFloat(atan2(-(unprojected2.y - unprojected1.y), unprojected2.x - unprojected1.x)))
                    touchState.initialTouchMidpoint = CGPoint(x: CGFloat(unprojected1.x + unprojected2.x) / CGFloat(2.0), y: CGFloat(unprojected1.y + unprojected2.y) / CGFloat(2.0))
                    
                    touchState.activeTouches.append(touch)
                    touchState.videoTargetState = .transforming
                }
            }
        }
        DEBUGEndTimedBlock("Touch Began")
    }
    
    func metalViewMovedTouches(_ metalView: MetalView, _ touches: Set<UITouch>) {
        DEBUGBeginTimedBlock("Touch Moved")
        if touchState.videoTargetState == .none || touchState.activeTouches.filter({ touches.contains($0) }).count == 0 { return }
        
        if touchState.videoTargetState == .dragging {
            let touch = touchState.activeTouches.first!
            let location = touch.location(in: metalView)
            let unprojected = unproject(location: location, in: metalView)
            
            let offset = touchState.initialDragOffset!
            let translation = CGPoint(x: CGFloat(unprojected.x) - offset.x, y: CGFloat(unprojected.y) - offset.y)
            
            runJavascript("Steina.updateDraggingVideo('\(touchState.videoTargetId!)', \(translation.x), \(translation.y))")
        }
        else if touchState.videoTargetState == .transforming {
            let touch1 = touchState.activeTouches[touchState.activeTouches.startIndex]
            let touch2 = touchState.activeTouches[touchState.activeTouches.index(after: touchState.activeTouches.startIndex)]
            let location1 = touch1.location(in: metalView)
            let location2 = touch2.location(in: metalView)
            let unprojected1 = unproject(location: location1, in: metalView)
            let unprojected2 = unproject(location: location2, in: metalView)
            
            let scaleFactor = CGFloat(distance(unprojected1, unprojected2)) / touchState.initialTouchDistance
            let scale = touchState.initialScale * scaleFactor
            
            let touchAngle = radiansToDegrees(CGFloat(atan2(-(unprojected2.y - unprojected1.y), unprojected2.x - unprojected1.x)))
            let rotation = touchState.initialRotation - (touchState.initialTouchAngle - CGFloat(touchAngle))
            
            let midpoint = CGPoint(x: CGFloat(unprojected1.x + unprojected2.x) / CGFloat(2.0), y: CGFloat(unprojected1.y + unprojected2.y) / CGFloat(2.0))
            
            let translation = CGPoint(x: touchState.initialPosition.x - (touchState.initialTouchMidpoint.x - midpoint.x), y: touchState.initialPosition.y - (touchState.initialTouchMidpoint.y - midpoint.y))
            
            runJavascript("Steina.updateDraggingVideo('\(touchState.videoTargetId!)', \(translation.x), \(translation.y), \(rotation), \(scale))")
        }
        DEBUGEndTimedBlock("Touch Moved")
    }
    
    func metalViewEndedTouches(_ metalView: MetalView, _ touches: Set<UITouch>) {
        DEBUGBeginTimedBlock("Touch Ended")
        if touchState.videoTargetState == .none { return }
        
        touchState.activeTouches.removeAll { touches.contains($0) }
        if touchState.activeTouches.count == 0 {
            touchState.videoTargetState = .none
            DEBUGBeginTimedBlock("End Dragging Video")
            var updateEditingTarget = false
            if let startTimestamp = touchState.dragStartTimestamp {
                if CACurrentMediaTime() - startTimestamp > 0.2 {
                    updateEditingTarget = true
                }
            }
            runJavascript("Steina.endDraggingVideo('\(touchState.videoTargetId!)', \(updateEditingTarget ? "true" : "false"))")
            DEBUGEndTimedBlock("End Dragging Video")
            touchState.videoTargetId = nil
            touchState.initialDragOffset = nil
            touchState.initialPosition = nil
            touchState.initialRotation = nil
            touchState.initialScale = nil
            touchState.initialTouchDistance = nil
            touchState.initialTouchAngle = nil
            touchState.initialTouchMidpoint = nil
        }
        else if touchState.videoTargetState == .transforming && touchState.activeTouches.count == 1 {
            // Transition back to dragging
            let touch = touchState.activeTouches.first!
            let location = touch.location(in: metalView)
            
            touchState.initialPosition = nil
            touchState.initialRotation = nil
            touchState.initialScale = nil
            touchState.initialTouchDistance = nil
            touchState.initialTouchAngle = nil
            touchState.initialTouchMidpoint = nil
            
            let transformJson = runJavascript("Steina.getDraggingVideoTransform('\(touchState.videoTargetId!)')")!
            let transformObj = try! JSONSerialization.jsonObject(with: transformJson.data(using: .utf8)!, options: [])
            
            let transform = transformObj as! Dictionary<String, NSNumber>
            let initialX = CGFloat(transform["x"]!.floatValue)
            let initialY = CGFloat(transform["y"]!.floatValue)
            
            let unprojected = unproject(location: location, in: metalView)
            touchState.initialDragOffset = CGPoint(x: CGFloat(unprojected.x) - initialX, y: CGFloat(unprojected.y) - initialY)
            touchState.videoTargetState = .dragging
            
        }
        DEBUGEndTimedBlock("Touch Ended")
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
    
    func unproject(location: CGPoint, in metalView: MetalView) -> float4 {
        let projectedX = (2.0 * (location.x / metalView.bounds.size.width)) - 1.0
        let projectedY = ((2.0 * (location.y / metalView.bounds.size.height)) - 1.0) * -1.0 // Invert y
        return unprojection * float4(Float(projectedX), Float(projectedY), 1.0, 1.0)
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
     * VideoCaptureViewControllerDelegate
     *
     **********************************************************************/
    
    func videoCaptureViewControllerDidCreateClip(videoCaptureViewController: VideoCaptureViewController, clip: Clip) {
        let markersString = "[\(clip.markers.map({ String($0) }).joined(separator: ","))]"
        let trimStart = clip.trimmedRegion.start
        let trimEnd = clip.trimmedRegion.end
        runJavascript("Steina.createVideoTarget(\"\(clip.id.uuidString)\", {fps: 30, frames: \(clip.frames), markers: \(markersString), trimStart: \(trimStart), trimEnd: \(trimEnd) });")
        updateHelpAnimations()
        saveProject()
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
        let trimStart = sound.trimmedRegion.start
        let trimEnd = sound.trimmedRegion.end
        runJavascript("Steina.createAudioTarget(\"\(sound.id.uuidString)\", {totalSamples: \(sound.length), markers: \(markersString), trimStart: \(trimStart), trimEnd: \(trimEnd) })")
        updateHelpAnimations()
        saveProject()
    }
    
    /**********************************************************************
     *
     * VideoEditorViewControllerDelegate
     *
     **********************************************************************/
    
    func videoEditorRequestedSave(editor: VideoEditorViewController, clip: Clip, markers: [Marker], trimmedRegion: EditorRange) {
        clip.markers = markers
        clip.trimmedRegion = trimmedRegion
        clip.thumbnail = generateThumbnailForClip(clip)
        
        let markersString = "[\(clip.markers.map({ String($0) }).joined(separator: ","))]"
        let trimStart = clip.trimmedRegion.start
        let trimEnd = clip.trimmedRegion.end
        runJavascript("Steina.updateVideoTargetInfo(\"\(clip.id.uuidString)\", {markers: \(markersString), trimStart: \(trimStart), trimEnd: \(trimEnd) })")
        saveProject()
        self.dismiss(animated: true, completion: nil)
    }
    
    func videoEditorRequestedDiscard(editor: VideoEditorViewController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func videoEditorRequestedRerecord(editor: VideoEditorViewController) {
        assert(false, "Video editor tried to send rerecord request to project editor")
    }
    
    
}
