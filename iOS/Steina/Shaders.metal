//
//  Shaders.metal
//  Steina
//
//  Created by Sean Hickey on 5/21/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position    [[ attribute(0) ]];
    float2 uv          [[ attribute(1) ]];
    float2 entityIndex [[ attribute(2) ]];  
};

struct VideoEffects {
    float color;
    float whirl;
    float brightness;
    float ghost;
};

struct VideoUniforms {
    uint entityIndex;
    float width;
    float height;
    float4x4 transform;
    VideoEffects effects;
};

struct VertexOut {
    float4 position [[ position ]];
    float2 uv;
    uint   entityIndex;
};

constant float epsilon = 1e-3;
float3 convertRGB2HSL(float3 rgb) {
    const float4 hueOffsets = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 temp1 = rgb.b > rgb.g ? float4(rgb.bg, hueOffsets.wz) : float4(rgb.gb, hueOffsets.xy);
    float4 temp2 = rgb.r > temp1.x ? float4(rgb.r, temp1.yzx) : float4(temp1.xyw, rgb.r);
    float m = min(temp2.y, temp2.w);
    float C = temp2.x - m;
    float L = 0.5 * (temp2.x + m);
    
    return float3(
                abs(temp2.z + (temp2.w - temp2.y) / (6.0 * C + epsilon)), // Hue
                C / (1.0 - abs(2.0 * L - 1.0) + epsilon), // Saturation
                L); // Lightness
}

float3 convertHue2RGB(float hue) {
    float r = abs(hue * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(hue * 6.0 - 2.0);
    float b = 2.0 - abs(hue * 6.0 - 4.0);
    return clamp(float3(r, g, b), 0.0, 1.0);
}

float3 convertHSL2RGB(float3 hsl) {
    float3 rgb = convertHue2RGB(hsl.x);
    float c = (1.0 - abs(2.0 * hsl.z - 1.0)) * hsl.y;
    return (rgb - 0.5) * c + hsl.z;
}

vertex VertexOut passthrough_vertex(VertexIn in [[ stage_in ]],
                                    device VideoUniforms *videoUniforms [[ buffer(1) ]],
                                    unsigned int vid [[ vertex_id ]]) {
    
    uint entityIdx = static_cast<uint>(in.entityIndex.y);
    VideoUniforms uniforms = videoUniforms[entityIdx + 1];
    float4x4 modelTransform = uniforms.transform;
    
    float4x4 projectionTransform = videoUniforms[0].transform;
    
    VertexOut out;
    out.position = projectionTransform * modelTransform * in.position;
    out.uv = in.uv;
    out.entityIndex = entityIdx;
    return out;
}

fragment float4 passthrough_fragment(VertexOut v [[ stage_in ]],
                                     texture2d_array<float> texture [[ texture(0) ]],
                                     texture2d_array<float> mask [[ texture(1) ]],
                                     device VideoUniforms *videoUniforms [[ buffer(0) ]]) {
    constexpr sampler s(coord::pixel, filter::linear);
    
    VideoUniforms uniforms = videoUniforms[v.entityIndex + 1];
    float2 texCoord = v.uv;
    
    // Whirl
    if (uniforms.effects.whirl != 0) {
        float kRadius = uniforms.width / 2.0;
        float2 kCenter = float2(uniforms.width / 2.0, uniforms.height / 2.0);
        float2 offset = texCoord - kCenter;
        float offsetMagnitude = length(offset);
        float whirlFactor = max(1.0 - (offsetMagnitude / kRadius), 0.0);
        float whirlActual = uniforms.effects.whirl * whirlFactor * whirlFactor;
        float sinWhirl = sin(whirlActual);
        float cosWhirl = cos(whirlActual);
        float2x2 rotationMatrix = float2x2(
                                   cosWhirl, -sinWhirl,
                                   sinWhirl, cosWhirl
                                   );
        
        texCoord = rotationMatrix * offset + kCenter;
    }
    
    float maskVal = mask.sample(s, texCoord, v.entityIndex).a;
    if (maskVal < 0.01) {
        discard_fragment();
    }
    
    // Ghost
    if (uniforms.effects.ghost != 0) {
        maskVal *= uniforms.effects.ghost;
    }
    
    float4 color = texture.sample(s, texCoord, v.entityIndex);
    
    // Color & Brightness
    if (uniforms.effects.color != 0 || uniforms.effects.brightness != 0) {
        float3 hsl = convertRGB2HSL(color.xyz);
            
        if (uniforms.effects.color != 0) {
            // this code forces grayscale values to be slightly saturated
            // so that some slight change of hue will be visible
            const float minLightness = 0.11 / 2.0;
            const float minSaturation = 0.09;
            if (hsl.z < minLightness) hsl = float3(0.0, 1.0, minLightness);
            else if (hsl.y < minSaturation) hsl = float3(0.0, minSaturation, hsl.z);
            
            hsl.x = fmod(hsl.x + uniforms.effects.color, 1.0);
            if (hsl.x < 0.0) hsl.x += 1.0;
        }
        
        if (uniforms.effects.brightness != 0) {
            hsl.z = clamp(hsl.z + uniforms.effects.brightness, 0.0, 1.0);
        }
        
        color.rgb = convertHSL2RGB(hsl);
    }
    
    
    
    return float4(color.rgb, maskVal);
}
