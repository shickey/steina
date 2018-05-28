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
    float4 position [[ attribute(0) ]];
    float2 uv       [[ attribute(1) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float2 uv;
};

vertex VertexOut passthrough_vertex(VertexIn in [[ stage_in ]],
                           unsigned int vid [[ vertex_id ]]) {
    VertexOut out;
    out.position = in.position;
    out.uv = in.uv;
    return out;
}

fragment float4 passthrough_fragment(VertexOut v [[ stage_in ]],
                                     texture2d_array<float> texture [[ texture(0) ]] ) {
    constexpr sampler s(coord::normalized, filter::linear);
    
    float4 color = texture.sample(s, v.uv, 0);
    return float4(color);
}
