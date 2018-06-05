//
//  EditorViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/10/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import WebKit
import CoreData
import Dispatch
import simd

typealias VideoClipId = String

struct InMemoryClip {
    let clip : Clip
    let videoClip : VideoClip
}

class EditorViewController: UIViewController, WKScriptMessageHandler, MetalViewDelegate, ClipsCollectionViewControllerDelegate {
    
    var project : Project! = nil {
        didSet {
            if let p = project {
                for untypedClip in p.clips! {
                    let clip = untypedClip as! Clip
                    let clipData = try! Data(contentsOf: clip.assetUrl)
                    let videoClip = deserializeClip(clipData)
                    videoClipIds.append(clip.id!.uuidString)
                    videoClips[clip.id!.uuidString] = InMemoryClip(clip: clip, videoClip: videoClip)
                }
            }
        }
    }
    var displayLink : CADisplayLink! = nil
    var ready = false
    var videoClipIds : [VideoClipId] = []
    var videoClips : [VideoClipId: InMemoryClip] = [:]
    var draggingVideoId : VideoClipId! = nil
    var previousRenderedIds : [VideoClipId] = []
    var renderedIds : [VideoClipId] = []
    var renderingQueue : DispatchQueue = DispatchQueue(label: "edu.mit.media.llk.Steina.Render", qos: .default, attributes: .concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem, target: nil)
    let renderDispatchGroup = DispatchGroup()
    let unproject = orthographicUnprojection(left: -320.0, right: 320.0, top: 240.0, bottom: -240.0, near: 1.0, far: -1.0)
    
    @IBOutlet weak var metalView: MetalView!
    @IBOutlet weak var webViewContainer: UIView!
    @IBOutlet weak var loadingView: UIView!
    var webView: WKWebView! = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        metalView.delegate = self
        
        initMetal(metalView)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleInsertedClips(_:)), name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: nil)
        
        // Create web view controller and bind to "steinaMsg" namespace
        let webViewController = WKUserContentController()
        webViewController.add(self, name: "cons")
        webViewController.add(self, name: "steinaMsg")
        
        // Create web view configuration
        let webViewConfig = WKWebViewConfiguration()
        webViewConfig.userContentController = webViewController
        
        // Init webview and load editor
        webView = WKWebView(frame: self.webViewContainer.bounds, configuration: webViewConfig)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.panGestureRecognizer.isEnabled = false
        webView.scrollView.bounces = false
        
        // Add subview
        self.webViewContainer!.addSubview(webView)

        // Load blocks editor
        let webFolder = Bundle.main.url(forResource: "web", withExtension: nil)!
        let indexPage = Bundle.main.url(forResource: "web/index", withExtension: "html")!
        webView.loadFileURL(indexPage, allowingReadAccessTo: webFolder)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if ready {
            onReady()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        runJavascript("vm.stopAll()")
        stopDisplayLink()
        saveProject()
        super.viewWillDisappear(animated)
    }
    
    func onScratchLoaded() {
        var js : String = ""
        for (clipId, inMemoryClip) in videoClips {
            js += "Steina.inflateVideoTarget('\(clipId)', '\(inMemoryClip.clip.targetJson!)');"
        }
        runJavascript(js) { (res, err) in
            self.ready = true
            self.onReady()
            UIView.animate(withDuration: 0.5, animations: { 
                self.loadingView.alpha = 0.0
            }, completion: { (_) in
                self.loadingView.isHidden = true
            })
            
        }
    }
    
    func saveProject() {
        self.project.thumbnail = getLastRenderedImage()
        runJavascript("Steina.serializeVideoTargets()") { (res, err) in
            if let targetDictionary = res as? Dictionary<String, String> {
                for (id, targetJson) in targetDictionary {
                    let inMemoryClip = self.videoClips[id]!
                    inMemoryClip.clip.targetJson = targetJson
                }
                try! self.project.managedObjectContext!.save()
            }
        }
    }
    
    func onReady() {
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
    
    @inline(__always)
    func runJavascript(_ js: String, _ completion: ((Any?, Error?) -> Void)? = nil) {
        webView!.evaluateJavaScript(js, completionHandler: completion)
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let clipsCollectionVC = segue.destination as? ClipsCollectionViewController {
            clipsCollectionVC.delegate = self
            clipsCollectionVC.videoClipIds = videoClipIds
            clipsCollectionVC.videoClips = videoClips
        }
        if let captureVC = segue.destination as? CaptureViewController {
            captureVC.project = project
        }
    }
    
    @objc func tick(_ sender: CADisplayLink) {
        previousRenderedIds = renderedIds
        renderedIds = []
        
        // @TODO: The step rate is hard coded in JS to be 1000 / 30
        //        but maybe we should pass the dt each time here?
        runJavascript("Steina.tick(); Steina.getVideoTargets()") { ( res , err ) in
            if let realError = err { 
                print("JS ERROR: \(realError)")
                return;
            }
            self.renderDispatchGroup.wait()
            var numEntitiesToRender = 0
            if let targets = res as? Array<Dictionary<String, Any>> {
                for target in targets {
                    let visible = target["visible"] as! Bool
                    if !visible { continue; } // Don't render anything if the video isn't visible
                    
                    let clipId = target["id"] as! String
                    let frame = (target["currentFrame"] as! NSNumber).floatValue
                    
                    var frameNumber = Int(round(frame))
                
                    let inMemoryClip = self.videoClips[clipId]!
                    
                    let videoClip = inMemoryClip.videoClip
                    if frameNumber >= videoClip.frames {
                        frameNumber = Int(videoClip.frames) - 1;
                    }
                    
                    let x         = (target["x"] as! NSNumber).floatValue
                    let y         = (target["y"] as! NSNumber).floatValue
                    let size      = (target["size"] as! NSNumber).floatValue
                    let direction = (target["direction"] as! NSNumber).floatValue
                    
                    let scale = (size / 100.0)
                    let theta = (direction - 90.0) * (.pi / 180.0)
                    
                    self.renderedIds.append(clipId)
                    
                    self.renderDispatchGroup.enter()
                    let entityIndex = numEntitiesToRender
                    self.renderingQueue.async {
                        let transform = entityTransform(scale: scale, rotate: theta, translateX: x, translateY: y)
                        pushRenderFrame(videoClip, entityIndex, frameNumber, transform)
                        self.renderDispatchGroup.leave()
                    }
                    
                    numEntitiesToRender += 1
                }
            }
            self.renderDispatchGroup.notify(queue: self.renderingQueue) {
                render(numEntitiesToRender)
            }
        }
        
    }
    
    @objc func handleInsertedClips(_ notification: Notification) {
        if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for managedObject in insertedObjects {
                if let newClip = managedObject as? Clip {
                    let clipData = try! Data(contentsOf: newClip.assetUrl)
                    let videoClip = deserializeClip(clipData)
                    let clipId = newClip.id!.uuidString
                    let inMemoryClip = InMemoryClip(clip: newClip, videoClip: videoClip)
                    videoClipIds.append(clipId)
                    videoClips[clipId] = inMemoryClip
                    runJavascript("Steina.createVideoTarget(\"\(clipId)\", 30, \(inMemoryClip.videoClip.frames));")
                }
            }
        }
    }
    
    // WKUserContentControllerDelegate
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // @TODO: Ewwwwwwwwww. Clean this mess up.
        if message.name == "steinaMsg" {
            if let body = message.body as? NSDictionary {
                if let message = body.object(forKey: "message") as? String {
                    if message == "READY" {
                        onScratchLoaded()
                    }
                }
            }
        }
        else if message.name == "cons" {
            if let body = message.body as? NSDictionary {
                if let message = body.object(forKey: "message") as? String {
                    print("JS MESSAGE: \(message)")
                }
            }
        }
    }
    
    // MetalViewDelegate
    
    func metalViewDelegateBeganTouch(_ metalView: MetalView, location: CGPoint) {
        if let draggingId = videoTargetAtLocation(location) {
            draggingVideoId = draggingId        
            runJavascript("Steina.beginDraggingVideo('\(draggingVideoId!)')")
        }
    }
    
    func metalViewDelegateMovedTouch(_ metalView: MetalView, location: CGPoint) {
        guard draggingVideoId != nil else { return }
        
        let x = (2.0 * (location.x / metalView.bounds.size.width)) - 1.0
        let y = ((2.0 * (location.y / metalView.bounds.size.height)) - 1.0) * -1.0 // Invert y
        let unprojected = unproject * float4(Float(x), Float(y), 1.0, 1.0)
        runJavascript("Steina.updateDraggingVideo('\(draggingVideoId!)', \(unprojected.x), \(unprojected.y))")
    }
    
    func metalViewDelegateEndedTouch(_ metalView: MetalView, location: CGPoint) {
        guard draggingVideoId != nil else { return }
        
        runJavascript("Steina.endDraggingVideo('\(draggingVideoId!)')")
    }
    
    func videoTargetAtLocation(_ location: CGPoint) -> VideoClipId? {
        let pixels : RawPtr = RawPtr.allocate(byteCount: 1, alignment: MemoryLayout<Float>.alignment)
        depthTex.getBytes(pixels, bytesPerRow: 640, from: MTLRegionMake2D(Int(location.x), Int(location.y), 1, 1), mipmapLevel: 0)
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
    
    // ClipsCollectionViewControllerDelegate
    
    func clipsControllerDidSelect(clipsController: ClipsCollectionViewController, clipId: VideoClipId) {
        runJavascript("vm.setEditingTarget(\"\(clipId)\")")
    }

}
