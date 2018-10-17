//
//  Debug.swift
//  Steina
//
//  Created by Sean Hickey on 10/5/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

import Foundation
import QuartzCore

struct DebugTimingFrame {
    let name : String
    let start : CFTimeInterval
    
    init(_ newName: String) {
        name = newName
        start = CACurrentMediaTime()
    }
}

var debugTimingStack : [DebugTimingFrame] = []

func DEBUGBeginTimedBlock(_ name: String) {
    debugTimingStack.append(DebugTimingFrame(name))
}

func DEBUGEndTimedBlock() {
    let frame = debugTimingStack.popLast()!
//    print(String(format: "%@: %.2fms", frame.name, (CACurrentMediaTime() - frame.start) * 1000.0))
}
