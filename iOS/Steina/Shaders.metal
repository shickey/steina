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
    float4 position         [[ attribute(0) ]];
    float2 uv               [[ attribute(1) ]];
    float2 entityIndex      [[ attribute(2) ]];
    float  effectColor      [[ attribute(3) ]];
    float  effectWhirl      [[ attribute(4) ]];
    float  effectBrightness [[ attribute(5) ]];
    float  effectGhost      [[ attribute(6) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float2 uv;
    uint   entityIndex;
    float  effectColor;
    float  effectWhirl;
    float  effectBrightness;
    float  effectGhost;
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
                                    device float4x4 *transforms [[ buffer(1) ]],
                                    unsigned int vid [[ vertex_id ]]) {
    float4x4 projectionTransform = transforms[0];
    
    uint entityIdx = static_cast<uint>(in.entityIndex.y);
    float4x4 modelTransform = transforms[entityIdx + 1];
    
    VertexOut out;
    out.position = projectionTransform * modelTransform * in.position;
    out.uv = in.uv;
    out.entityIndex = entityIdx;
    out.effectColor = in.effectColor;
    out.effectWhirl = in.effectWhirl;
    out.effectBrightness = in.effectBrightness;
    out.effectGhost = in.effectGhost;
    return out;
}

fragment float4 passthrough_fragment(VertexOut v [[ stage_in ]],
                                     texture2d_array<float> texture [[ texture(0) ]],
                                     texture2d_array<float> mask [[ texture(1) ]]) {
    constexpr sampler s(coord::pixel, filter::linear);

    float maskVal = mask.sample(s, v.uv, v.entityIndex).a;
    if (maskVal < 0.01) {
        discard_fragment();
    }
    if (v.effectGhost != 0) {
        maskVal *= v.effectGhost;
    }
    
    float4 color = texture.sample(s, v.uv, v.entityIndex);
    
    if (v.effectColor != 0 || v.effectBrightness != 0) {
        float3 hsl = convertRGB2HSL(color.xyz);
            
        if (v.effectColor != 0) {
            // this code forces grayscale values to be slightly saturated
            // so that some slight change of hue will be visible
            const float minLightness = 0.11 / 2.0;
            const float minSaturation = 0.09;
            if (hsl.z < minLightness) hsl = float3(0.0, 1.0, minLightness);
            else if (hsl.y < minSaturation) hsl = float3(0.0, minSaturation, hsl.z);
            
            hsl.x = fmod(hsl.x + v.effectColor, 1.0);
            if (hsl.x < 0.0) hsl.x += 1.0;
        }
        
        if (v.effectBrightness != 0) {
            hsl.z = clamp(hsl.z + v.effectBrightness, 0.0, 1.0);
        }
        
        color.rgb = convertHSL2RGB(hsl);
    }
    
    
    
    return float4(color.rgb, maskVal);
}
