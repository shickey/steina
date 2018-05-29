//
//  EditorViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/10/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import WebKit

typealias VideoClipId = String

class EditorViewController: UIViewController, WKScriptMessageHandler, ClipsCollectionViewControllerDelegate {
    
    var project : Project! = nil
    
    var displayLink : CADisplayLink! = nil

    @IBOutlet weak var metalView: MetalView!
    @IBOutlet weak var webViewContainer: UIView!
    
    var webView: WKWebView! = nil
    
    var videoClips : [VideoClipId: VideoClip] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        for untypedClip in project.clips! {
            let clip = untypedClip as! Clip
            let clipData = try! Data(contentsOf: clip.assetUrl)
            let videoClip = deserializeClip(clipData)
            videoClips[clip.id!.uuidString] = videoClip
        }
        
        // Create web view controller and bind to "steinaMsg" namespace
        let webViewController = WKUserContentController()
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

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func onReady() {
        for (clipId, clip) in videoClips {
            runJavascript("Steina.createVideoTarget(\"\(clipId)\", 30, \(clip.frames))")
        }
        initMetal(metalView)
        startDisplayLink()
    }
    
    func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink.preferredFramesPerSecond = 30
        displayLink.add(to: .current, forMode: .defaultRunLoopMode)
    }
    
    @inline(__always)
    func runJavascript(_ js: String, _ completion: ((Any?, Error?) -> Void)? = nil) {
        webView!.evaluateJavaScript(js, completionHandler: completion)
    }
    
    @IBAction func greenFlagButtonTapped(_ sender: Any) {
        runJavascript("vm.greenFlag()")
    }
    
    @IBAction func stopButtonTapped(_ sender: Any) {
        runJavascript("vm.stopAll()")
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let clipsCollectionVC = segue.destination as? ClipsCollectionViewController {
            clipsCollectionVC.delegate = self
            clipsCollectionVC.project = project
        }
        if let captureVC = segue.destination as? CaptureViewController {
            captureVC.project = project
        }
    }
    
    @objc func tick(_ sender: CADisplayLink) {
        
        // @TODO: The step rate is hard coded in JS to be 1000 / 30
        //        but maybe we should pass the dt each time here?
        runJavascript("Steina.tick(); Steina.getVideoTargets()") { ( res , err ) in
            if let realError = err { 
                print("JS ERROR: \(realError)")
                return;
            }
            if let targets = res as? Array<Dictionary<String, Any>> {
                for target in targets {
                    let visible = target["visible"] as! Bool
                    if !visible { continue; } // Don't render anything if the video isn't visible
                    
                    let clipId = target["id"] as! String
                    let frame = (target["currentFrame"] as! NSNumber).floatValue
                    
                    var frameNumber = Int(round(frame))
                
                    let clip = self.videoClips[clipId]!
                    if frameNumber >= clip.frames {
                        frameNumber = Int(clip.frames) - 1;
                    }
                    
                    let x         = (target["x"] as! NSNumber).floatValue
                    let y         = (target["y"] as! NSNumber).floatValue
                    let size      = (target["size"] as! NSNumber).floatValue
                    let direction = (target["direction"] as! NSNumber).floatValue
                    
                    let scale = (size / 100.0)
                    let theta = (direction - 90.0) * (.pi / 180.0)
                    
                    let transform = entityTransform(scale: scale, rotate: theta, translateX: x, translateY: y)
                    pushRenderFrame(clip, frameNumber, transform)
                }
            }
            render()
        }
        
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // @TODO: Ewwwwwwwwww. Clean this mess up.
        if message.name == "steinaMsg" {
            if let body = message.body as? NSDictionary {
                if let message = body.object(forKey: "message") as? String {
                    if message == "READY" {
                        onReady()
                    }
                }
            }
        }
    }
    
    // ClipsCollectionViewControllerDelegate
    
    func clipsControllerDidSelect(clipsController: ClipsCollectionViewController, clip: Clip) {
        let id = clip.id!.uuidString
        runJavascript("vm.setEditingTarget(\"\(id)\")")
    }

}
