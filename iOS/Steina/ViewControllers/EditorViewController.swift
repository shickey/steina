//
//  EditorViewController.swift
//  Steina
//
//  Created by Sean Hickey on 5/10/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import UIKit
import WebKit

class EditorViewController: UIViewController {
    
    var project : Project! = nil

    @IBOutlet weak var metalView: MetalView!
    @IBOutlet weak var webView: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let webFolder = Bundle.main.url(forResource: "web", withExtension: nil)!
        let indexPage = Bundle.main.url(forResource: "web/index", withExtension: "html")!
        webView.loadFileURL(indexPage, allowingReadAccessTo: webFolder)
        
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        initMetal(metalView)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @inline(__always)
    func runJavascript(_ js: String) {
        webView!.evaluateJavaScript(js, completionHandler: nil)
    }
    
    @IBAction func greenFlagButtonTapped(_ sender: Any) {
        runJavascript("vm.greenFlag()")
    }
    
    @IBAction func stopButtonTapped(_ sender: Any) {
        runJavascript("vm.stopAll()")
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let captureVC = segue.destination as? CaptureViewController {
            captureVC.project = project
        }
    }

}
