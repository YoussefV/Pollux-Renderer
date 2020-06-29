//
//  Environment.swift
//  Pollux
//
//  Created by William Ho on 12/6/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

import Foundation

struct Environment {
    var filename : String
    var emittance : SIMD3<Float>
    
    init(from file: String, with emittance: SIMD3<Float>) {
        self.filename = file
        self.emittance = emittance
    }
}

