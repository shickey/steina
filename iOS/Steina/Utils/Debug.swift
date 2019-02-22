//
//  Debug.swift
//  Steina
//
//  Created by Sean Hickey on 10/5/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import QuartzCore
#if DEBUG
import os.signpost
#endif

#if DEBUG
let logger = OSLog(subsystem: "edu.mit.media.llk.Bricoleur", category: "Timing")
#endif

@inline(__always)
func DEBUGBeginTimedBlock(_ name: StaticString) {
    #if DEBUG
    if #available(iOS 12.0, *) {
        os_signpost(.begin, log: logger, name: name)
    }
    #endif
}

@inline(__always)
func DEBUGEndTimedBlock(_ name: StaticString) {
    #if DEBUG
    if #available(iOS 12.0, *) {
        os_signpost(.end, log: logger, name: name)
    }
    #endif
}
