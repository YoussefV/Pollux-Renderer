//
//  SceneParser.swift
//  Pollux
//
//  Created by Youssef Kamal Victor on 11/21/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

import Foundation
import simd

// Faster
typealias Scene = (Camera, [Geom], UInt32, [Material], Environment?, [Float])

class SceneParser {
    
    // Counts the types of lights (i.e. bsdfs < 0)
    private static var light_types = 0
    
    private static var kdTreeOffset = 0
    private static var kdTrees : [Float] = []
    
    private static func parseFloatArray(_ dict: [String: Any], _ key: String) -> float3? {
        if let arr = dict[key] {
             return float3((arr as! Array<NSNumber>).map{$0.floatValue})
        } else {
            return nil
        }
    }
    
    private static func parseEnvironment(_ environmentJSON : [String: Any]?) -> Environment?  {
        if (environmentJSON) == nil {return nil}
        let filepath = environmentJSON!["filepath"] as! String
        let emittance = float3(environmentJSON!["emittance"] as! Array<Float>)
        let env = Environment(from: filepath, with: emittance)
        return env
    }
    
    private static func parseCamera(_ cameraJSON : [String : Any]) -> Camera {
        var camera = Camera();
        camera.pos    = parseFloatArray(cameraJSON, "pos")!
        camera.lookAt = parseFloatArray(cameraJSON, "lookAt")!
        camera.up     = parseFloatArray(cameraJSON, "up")!
        camera.data   = float4(0,0, cameraJSON["fov"] as! Float, cameraJSON["depth"] as! Float)
        camera.lensData = float2(cameraJSON["lensRadius"] as? Float ?? 0.0, cameraJSON["focalDistance"] as? Float ?? 1.0)
        
        // Actually Computing the view and right vectors here
        camera.view   = simd_normalize(camera.lookAt - camera.pos);
        camera.right  = simd_cross(camera.view, camera.up);
        
        return camera
    }
    
    private static func parseGeometry(_ geomsJSON : [[String : Any]]) -> ([Geom], UInt32) {
        var light_count : UInt32 = 0
        var geoms : [Geom] = [Geom]()
        for geomJSON in geomsJSON {
            var geom = Geom();
            geom.type = GeomType(geomJSON["type"] as! UInt32)
            if (geom.type.rawValue == 3) {
               let (geomKDtree, bounds_min, bounds_max) = MeshParser.parseMesh(geomJSON["mesh_path"] as! String)
               kdTrees.append(contentsOf: geomKDtree)
               geom.meshData.minAABB = bounds_min
               geom.meshData.maxAABB = bounds_max
               geom.meshData.meshIndex = Int32(kdTreeOffset)
               SceneParser.kdTreeOffset = kdTrees.count
            } else {
               geom.meshData.meshIndex     = -1
            }
            geom.materialid  = geomJSON["material"] as! Int32
            geom.translation = parseFloatArray(geomJSON, "translate")!
            geom.rotation    = parseFloatArray(geomJSON, "rotate")!
            geom.scale       = parseFloatArray(geomJSON, "scale")!
            let s_tr = simd_translation(dt: geom.translation)
            let s_rt = simd_rotation(dr:    geom.rotation)
            let s_sc = simd_scale(ds:       geom.scale)
            geom.transform = s_tr * s_rt * s_sc;
            geom.inverseTransform = simd_inverse(geom.transform)
            geom.invTranspose     = simd_transpose(geom.inverseTransform)
            
            light_count += (geom.materialid < light_types) ? 1 : 0;
            geoms.append(geom)
        }
        
        return (geoms, light_count)
    }
    
    private static func parseMaterials(_ materialsJSON : [[String : Any]]) -> [Material] {
        var materials : [Material] = [Material]()
        for materialJSON in materialsJSON {
            var material = Material();
            material.bsdf                = materialJSON["bsdf"] as? Int16 ?? 0
            material.color               = parseFloatArray(materialJSON, "color") ?? float3(0.2, 0.2, 0.2)
            material.emittance           = parseFloatArray(materialJSON, "emittance") ?? float3(0, 0, 0)
            material.hasReflective       = materialJSON["hasReflective"] as? Float ?? 0.0
            material.hasRefractive       = materialJSON["hasRefractive"] as? Float ?? 0.0
            material.index_of_refraction = materialJSON["index_of_refraction"] as? Float ?? 0.0
            material.specular_color      = parseFloatArray(materialJSON, "specular_color") ?? float3(0, 0, 0)
            material.specular_exponent   = materialJSON["specular_exponent"] as? Float ?? 0.0
            
            self.light_types += (material.bsdf < 0) ? 1 : 0;
            
            materials.append(material)
        }
        
        return materials
    }
    
    static func parseScene(from file: String) -> Scene {
        #if os(iOS) || os(watchOS) || os(tvOS)
            let platform_file = "\(file)-ios"
        #else
            let platform_file = file
        #endif

        if let file = Bundle.main.url(forResource: platform_file, withExtension: "json") {
            do {
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                let jsonFile    = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                let camera      = parseCamera(jsonFile["camera"] as! [String : NSObject])
                let materials   = parseMaterials(jsonFile["materials"] as! [[String : Any]])
                let environment = parseEnvironment(jsonFile["environment"] as? [String : Any] ?? nil) ?? nil
                let (geometry, light_count)  = parseGeometry(jsonFile["geometry"] as! [[String : Any]])
                return (camera, geometry, light_count, materials, environment, SceneParser.kdTrees)
            } catch let error {
                fatalError(error.localizedDescription)
            }
        } else {
            fatalError("Could not find scene file: \(platform_file), please check file path and try again.")
        }
    }
}
