#version 460 core
#include <flutter/runtime_effect.glsl>

// The half of a grade that a 4x5 colour matrix cannot express: gamma, the
// three-point tone curve, sharpening, noise reduction and film grain.
//
// These are the sliders the exporter emits as their own FFmpeg filters
// (`eq=gamma`, `curves`, `unsharp`, `hqdn3d`, `noise`), so the preview needs
// a second pass of its own or every one of them looks like a dead control.

uniform vec2 uSize;

// FFmpeg `curves=all='0/lo 0.5/mid 1/hi'` control points.
uniform float uCurveLo;
uniform float uCurveMid;
uniform float uCurveHi;
uniform float uHasCurves;

// `eq=gamma=`: out = in ^ (1 / gamma).
uniform float uGamma;

// `unsharp` amount, `hqdn3d` strength and `noise` amplitude, all 0..1-ish.
uniform float uSharpen;
uniform float uDenoise;
uniform float uGrain;

// Varies per clip so two clips do not grain in lockstep.
uniform float uSeed;

uniform sampler2D uTexture;

out vec4 fragColor;

vec3 unpremultiply(vec4 c) {
    return c.a > 0.001 ? c.rgb / c.a : c.rgb;
}

vec3 sampleAt(vec2 uv) {
    return unpremultiply(texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0))));
}

// Piecewise-linear through the same three points the exporter fits a spline
// to. The spline's extra smoothness is invisible at preview size; the tonal
// shape is what the user is judging.
float curveMap(float x, float lo, float mid, float hi) {
    return x < 0.5 ? mix(lo, mid, x * 2.0) : mix(mid, hi, (x - 0.5) * 2.0);
}

// Cheap value noise. Deterministic per pixel, so the grain sits still
// instead of boiling while the player is paused.
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 src = texture(uTexture, uv);
    vec3 rgb = unpremultiply(src);
    vec2 texel = 1.0 / uSize;

    if (uHasCurves > 0.5) {
        rgb = vec3(
            curveMap(rgb.r, uCurveLo, uCurveMid, uCurveHi),
            curveMap(rgb.g, uCurveLo, uCurveMid, uCurveHi),
            curveMap(rgb.b, uCurveLo, uCurveMid, uCurveHi));
    }

    if (uGamma != 1.0) {
        rgb = pow(max(rgb, vec3(0.0)), vec3(1.0 / uGamma));
    }

    // One 3x3 box serves both neighbours: denoise mixes towards it, sharpen
    // mixes away from it.
    if (uDenoise > 0.0 || uSharpen > 0.0) {
        vec3 box = vec3(0.0);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                box += sampleAt(uv + vec2(float(x), float(y)) * texel);
            }
        }
        box /= 9.0;
        if (uDenoise > 0.0) rgb = mix(rgb, box, clamp(uDenoise, 0.0, 1.0));
        if (uSharpen > 0.0) rgb = rgb + (rgb - box) * uSharpen;
    }

    if (uGrain > 0.0) {
        float n = hash(FlutterFragCoord().xy + vec2(uSeed)) - 0.5;
        rgb += vec3(n * uGrain);
    }

    rgb = clamp(rgb, 0.0, 1.0);
    fragColor = vec4(rgb * src.a, src.a);
}
