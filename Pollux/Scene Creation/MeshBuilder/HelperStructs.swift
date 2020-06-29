//
//  HelperStructs.swift
//  Pollux
//
//  Created by Youssef Victor on 12/9/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import simd

// This file contains:
// - AABB:                 The axis aligned bounding box of a shape
// - Triangle:             A quick representation of a triangle
// - Compact Triangle:     A compact representation of the triangle for fast GPU access
// - CompactNode:          A compact representation of a kd-tree node for fast GPU traversal


struct AABB {
    static let aabb   =  [SIMD3<Float>( 1, 1, 1),
                          SIMD3<Float>( 1, 1,-1),
                          SIMD3<Float>( 1,-1, 1),
                          SIMD3<Float>( 1,-1,-1),
                          SIMD3<Float>(-1, 1, 1),
                          SIMD3<Float>(-1, 1,-1),
                          SIMD3<Float>(-1,-1, 1),
                          SIMD3<Float>(-1,-1,-1)]
    
    let bounds_min    : SIMD3<Float>;
    let bounds_max    : SIMD3<Float>;
    let bounds_center : SIMD3<Float>;

    init (_ min : SIMD3<Float> = SIMD3<Float>(repeating: 0), _ max : SIMD3<Float> = SIMD3<Float>(repeating: 0)) {
        self.bounds_min = min
        self.bounds_max = max
        self.bounds_center = (min + max) * 0.5;
    }
    
    // Intersection is handled in device
    func Encapsulate(_ bounds : AABB) -> AABB {
        return AABB(simd_min(self.bounds_min, bounds.bounds_min), simd_max(self.bounds_max, bounds.bounds_max));
    }
    
    func Transform(transform : inout simd_float4x4) ->AABB {
        // If infinite box, prevent overflowing
        if (self.bounds_min.x == -Float.greatestFiniteMagnitude ||
            self.bounds_min.y == -Float.greatestFiniteMagnitude ||
            self.bounds_min.z == -Float.greatestFiniteMagnitude
            ||
            self.bounds_max.x ==  Float.greatestFiniteMagnitude ||
            self.bounds_max.y ==  Float.greatestFiniteMagnitude ||
            self.bounds_max.z ==  Float.greatestFiniteMagnitude)
        {
            return self;
        }
        
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        
        let halfSize = (bounds_max - bounds_center);
        
        for i in 0..<8
        {
            let v : SIMD3<Float> = bounds_center + (AABB.aabb[i] * halfSize);
            let tPoint = transform *  SIMD4<Float>(v, 1);
            
            maxX = max(tPoint.x, maxX);
            maxY = max(tPoint.y, maxY);
            maxZ = max(tPoint.z, maxZ);
            
            minX = min(tPoint.x, minX);
            minY = min(tPoint.y, minY);
            minZ = min(tPoint.z, minZ);
        }
        
        let newMin = SIMD3<Float>(minX, minY, minZ);
        let newMax = SIMD3<Float>(maxX, maxY, maxZ);
        
        return AABB(newMin, newMax);
    }
}


struct Triangle
{
    // The actual points
    let p1: SIMD3<Float>;
    let p2: SIMD3<Float>;
    let p3: SIMD3<Float>;
    
    // Normals
    let n1: SIMD3<Float>;
    let n2: SIMD3<Float>;
    let n3: SIMD3<Float>;
    
    // UVs
    let t1: SIMD2<Float>;
    let t2: SIMD2<Float>;
    let t3: SIMD2<Float>;
    
    // The triangle's axis aligned bounding box
    let bounds: AABB;
};


/**************************************************
 **************************************************
 **********    Compact Data Structures   **********
 **************************************************
 **************************************************/


struct CompactTriangle
{
    // Data
    
    // The e vectors are used for triangle intersections
    // they represent the triangle's sides
    // This makes triangle intersections faster as you
    // don't need to recompute these every single time
    // and that's all you care about at the end of the
    // day.
    
    // e1 = p2 - p1
    let e1x: Float;
    let e1y: Float;
    let e1z: Float;

    // e1 = p3 - p1
    let e2x: Float;
    let e2y: Float;
    let e2z: Float;

    // One point defining the triangle
    // The rest can be computed using e's
    let p1x: Float;
    let p1y: Float;
    let p1z: Float;

    // Normals
    let n1x: Float;
    let n1y: Float;
    let n1z: Float;

    let n2x: Float;
    let n2y: Float;
    let n2z: Float;

    let n3x: Float;
    let n3y: Float;
    let n3z: Float;
};

struct CompactNode
{
    // Data is laid out as follows:
    // - leftNode, rightNode, split_axis, triangleCount
    let node_data : packed_float4
    
    // The split point along `split_axis`
    let split     : Float;
};

