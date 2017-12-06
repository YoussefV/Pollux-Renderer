//
//  mis.metal
//  Pollux
//
//  Created by William Ho on 12/4/17.
//  Copyright © 2017 Youssef Victor. All rights reserved.
//

#include <metal_stdlib>
#include "../Data_Types/PolluxTypes.h"
#import  "Loki/loki_header.metal"
#include "intersections_header.metal"
#include "interactions_header.metal"
#include "mis_helper_header.metal"

using namespace metal;

// Generates rays with float3(0) color
kernel void kern_GenerateRaysFromCameraMIS(constant Camera& cam [[ buffer(0) ]],
                                           constant uint& traceDepth [[ buffer(1) ]] ,
                                           device Ray* rays [[ buffer(2) ]] ,
                                           const uint2 position [[thread_position_in_grid]])
{
    const int x = position.x;
    const int y = position.y;
    
    const int width = cam.data.x;
    const int height = cam.data.y;
    
    const float fov = cam.data[2];
    
    if (x < width && y < height) {
        int index = x + (y * width);
        
        // Get the ray, define that it's on the device.
        device Ray& ray = rays[index];
        
        ray.origin = cam.pos;
        ray.color = float3(0.0f, 0.0f, 0.0f);
        
        // Calculations for ray cast:
        const float yscaled = tan(fov * (3.14159 / 180));
        const float xscaled = (yscaled * width) / height;
        const float2 pixelLength = float2(2 * xscaled / (float)width
                                          , 2 * yscaled / (float)height);
        
        
        // TODO: implement antialiasing by jittering the ray
        ray.direction = normalize(cam.view
                                  - cam.right * pixelLength.x * ((float)x -  width  * 0.5f)
                                  - cam.up    * pixelLength.y * ((float)y -  height * 0.5f)
                                  );
        
        ray.idx_bounces.x = x;
        ray.idx_bounces.y = y;
        ray.idx_bounces[2] = traceDepth;
        ray.uv.x = x / width;
        ray.uv.y = y / height;
        ray.throughput = float(1);
    }
}

// Shade with MIS
kernel void kern_ShadeMaterialsMIS(constant   uint& ray_count             [[ buffer(0) ]],
                                   constant   uint& iteration             [[ buffer(1) ]],
                                   device     Ray* rays                   [[ buffer(2) ]],
                                   device     Intersection* intersections [[ buffer(3) ]],
                                   device     Geom*         geoms         [[ buffer(4)]],
                                   device     Material*     materials     [[ buffer(5) ]],
                                   // TODO: Delete buffers 5 & 6 for later stages
                                   texture2d<float, access::write> outTexture [[texture(5)]],
                                   constant uint2& imageDeets  [[ buffer(6) ]],
                                   // TODO: END DELETE
                                   const uint position [[thread_position_in_grid]]) {
    
    if (position >= ray_count) {return;}
    
    Intersection intersection = intersections[position];
    device Ray& ray = rays[position];
    
    //Naive Early Ray Termination
    // TODO: Stream Compact and remove this line
    if (ray.idx_bounces[2] <= 0) {return;}
    
    if (intersection.t > 0.0f) { // if the intersection exists...
        Material m = materials[intersection.materialId];
        
        // If the material indicates that the object was a light, "light" the ray
        thread float pdf;
        if (m.bsdf == -1) {
            //light the ray
            ray.color += (m.color * m.emittance);
            ray.idx_bounces[2] = 0;
            return;
        }
        
        // Seed a random number from the position and iteration number
        Loki rng = Loki(position, iteration + 1, ray.idx_bounces[2] + 1);
        
        //Store a copy. We only add this in the end.
        thread Ray gi_Component = ray;
        gi_Component.color = float3(1);
        float gi_pdf;
        // If the material indicates that the object was a light, "light" the ray
        shadeAndScatter(gi_Component, intersection, m, rng, gi_pdf);
        
        /*
         * Light Importance Sampling
         */
        int lightId = 0; // TODO: Assumption is one light in scene (obviously needs to be fixed)
        device Geom& light = geoms[lightId];
        device Material& light_m = materials[light.materialid];
        thread float pdf_li;
        thread Ray lightRay = ray;
        
        lightRay.origin = intersection.point + intersection.normal * EPSILON;
        float3 lightContribution = sample_li(light, light_m, intersection.point, rng, lightRay.direction, pdf_li);
        
        thread Intersection lightIntersection = intersection;
        
        getIntersection(lightRay, geoms, lightIntersection, 7); //TODO: replace with true geom_count
        
        if (lightIntersection.t > 0.f && lightIntersection.materialId != light.materialid) lightContribution = float3(0);
        
        float3 f_x = dot(intersection.normal, lightRay.direction) * m.color; //TODO: actual color function
        
        lightContribution *= (f_x * ray.throughput) / pdf_li;
        lightContribution = float3(max(0.f,lightContribution.x), max(0.f,lightContribution.y), max(0.f,lightContribution.z));
        
        /*
         * BSDF Importance Sampling
         */
        
        thread float pdf_bsdf;
        thread Ray bsdfRay = ray;
        bsdfRay.color = float3(1);
        shadeAndScatter(bsdfRay, intersection, m, rng, pdf_bsdf);
        float3 f_y = m.color;
        thread Intersection bsdfIntersection = intersection;
        getIntersection(bsdfRay, geoms, bsdfIntersection, 7);
        float3 bsdfContribution = float3(0);
        bsdfContribution = bsdfRay.color * ray.throughput;
        
        float nf = 1.f, gf = 1.f;
        float totalPowerProbability = (pdf_li * pdf_li) + (pdf_bsdf * pdf_bsdf);
        float dlWeight = powerHeuristic(nf, pdf_li, gf, pdf_bsdf);
        float bsdfWeight = powerHeuristic(nf, pdf_bsdf, gf, pdf_li);
        
        //Ray for next iteration
        ray.color +=  lightContribution * dlWeight + bsdfContribution * bsdfWeight;
        ray.throughput *= gi_Component.color;
        ray.origin = gi_Component.origin;
        ray.direction = gi_Component.direction;
        ray.idx_bounces[2]--;
    }
    else { // If there was no intersection, color the ray black.
        // TODO: Environment Map Code goes here
        //       something like: ray.color = getEnvMapColor(ray.direction);
        ray.color = float3(0);
        ray.idx_bounces[2] = 0;
    }
}


