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

struct VertexOut {
    float4 position [[ position ]];
    float2 uv;
    uint   entityIndex;
};

vertex VertexOut passthrough_vertex(VertexIn in [[ stage_in ]],
                                    device float4x4 *transforms [[ buffer(1) ]],
                                    unsigned int vid [[ vertex_id ]]) {
    uint entityIdx = static_cast<uint>(in.entityIndex.y);
    float4x4 transform = transforms[entityIdx];
    
    VertexOut out;
    out.position = transform * in.position;
    out.uv = in.uv;
    out.entityIndex = entityIdx;
    return out;
}

fragment float4 passthrough_fragment(VertexOut v [[ stage_in ]],
                                     texture2d_array<float> texture [[ texture(0) ]],
                                     texture2d_array<float> mask [[ texture(1) ]]) {
    constexpr sampler s(coord::normalized, filter::linear);
    
    float4 color = texture.sample(s, v.uv, v.entityIndex);
    float maskVal = mask.sample(s, v.uv, v.entityIndex).r;
    return float4(color.rgb, maskVal);
}
