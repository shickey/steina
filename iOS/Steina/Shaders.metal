//
//  Shaders.metal
//  Steina
//
//  Created by Sean Hickey on 5/21/18.
//  Copyright © 2018 Massachusetts Institute of Technology. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float4 position [[ position ]];
    float4 color;
};

vertex Vertex passthrough_vertex(device Vertex *vertices [[ buffer(0) ]],
                           unsigned int vid [[ vertex_id ]]) {
    return vertices[vid];
}

fragment float4 passthrough_fragment(Vertex v [[ stage_in ]]) {
    return float4(v.color);
}
