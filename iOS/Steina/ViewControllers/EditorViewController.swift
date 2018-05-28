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

class EditorViewController: UIViewController, WKScriptMessageHandler {
    
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
            clipsCollectionVC.clips = project.clips!.array as! [Clip]
        }
        if let captureVC = segue.destination as? CaptureViewController {
            captureVC.project = project
        }
    }
    
    @objc func tick(_ sender: CADisplayLink) {
        clearRenderList()
        
        // @TODO: The step rate is hard coded in JS to be 1000 / 30
        //        but maybe we should pass the dt each time here?
        runJavascript("Steina.tick(); Steina.getVideoTargets()") { ( res , err ) in
            if let realError = err { 
                print("JS ERROR: \(realError)")
                return;
            }
            if let targets = res as? Array<Dictionary<String, Any>> {
//                for target in targets {
                let target = targets[0]
//                    let visible = target["visible"] as! Bool
//                    if !visible { continue; } // Don't render anything if the video isn't visible
                    
                    let clipId = target["id"] as! String
                    let time = (target["currentTime"] as! NSNumber).floatValue
                    let fps = (target["fps"] as! NSNumber).intValue
                    
                    var frameNumber = Int(round(Float(fps) * time))
                
                    let clip = self.videoClips[clipId]!
                if frameNumber >= clip.frames {
                    frameNumber = Int(clip.frames) - 1;
                }
                
                print(time)
                    
                    pushRenderFrame(clip, frameNumber)
//                }
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

}
