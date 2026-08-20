#version 460 core
#include <flutter/runtime_effect.glsl>

// Chroma key in YUV space: keying on chroma alone means a green shirt in
// shadow still keys out, which an RGB distance test gets wrong.

uniform vec2 uSize;
uniform vec3 uKeyColor;
uniform float uSimilarity;
uniform float uBlend;
uniform sampler2D uTexture;

out vec4 fragColor;

vec2 chromaOf(vec3 rgb) {
    float u = -0.169 * rgb.r - 0.331 * rgb.g + 0.5 * rgb.b;
    float v = 0.5 * rgb.r - 0.419 * rgb.g - 0.081 * rgb.b;
    return vec2(u, v);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 src = texture(uTexture, uv);

    // Undo premultiplication so the key sees the true colour.
    vec3 rgb = src.a > 0.001 ? src.rgb / src.a : src.rgb;

    float d = distance(chromaOf(rgb), chromaOf(uKeyColor));
    float edge = max(uBlend, 0.0001);
    float keep = smoothstep(uSimilarity, uSimilarity + edge, d);

    // Pull the key colour out of the remaining fringe so edges do not glow.
    vec3 despilled = mix(vec3(dot(rgb, vec3(0.299, 0.587, 0.114))), rgb, keep);

    float a = src.a * keep;
    fragColor = vec4(despilled * a, a);
}
