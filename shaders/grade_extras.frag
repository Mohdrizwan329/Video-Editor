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

// `noise=c0s=` amplitude: the same idea as uGrain but on the luma plane
// only, which is what the exporter's c0-only noise does.
uniform float uFilmGrain;

// Varies per clip so two clips do not grain in lockstep.
uniform float uSeed;

// Per-hue grading: eight bands of hue shift, saturation scale and luminance
// lift, in the band order HslGrade lists. The exporter bakes the same
// numbers into a 3D LUT, so what the shader paints and what `lut3d` writes
// come from one place.
// `colorchannelmixer=rr:gg:bb` — the colour cast as per-channel scales.
uniform vec3 uColorCast;

uniform float uHslOn;
uniform float uHslHue[8];
uniform float uHslSat[8];
uniform float uHslLum[8];

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

const float kBandCentres[8] = float[8](0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 280.0, 320.0);

vec3 rgb2hsl(vec3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float l = (mx + mn) * 0.5;
    if (mx == mn) return vec3(0.0, 0.0, l);
    float d = mx - mn;
    float s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
    float h;
    if (mx == c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    else if (mx == c.g) h = (c.b - c.r) / d + 2.0;
    else h = (c.r - c.g) / d + 4.0;
    return vec3(h / 6.0, s, l);
}

float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 0.5) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 c) {
    if (c.y == 0.0) return vec3(c.z);
    float q = c.z < 0.5 ? c.z * (1.0 + c.y) : c.z + c.y - c.z * c.y;
    float p = 2.0 * c.z - q;
    return vec3(hue2rgb(p, q, c.x + 1.0 / 3.0),
                hue2rgb(p, q, c.x),
                hue2rgb(p, q, c.x - 1.0 / 3.0));
}

// The two nearest band centres share the pixel, linearly — the same split
// HslGrade.weightsFor makes, so the shader and the LUT agree at every hue.
vec3 gradeHsl(vec3 rgb) {
    vec3 hsl = rgb2hsl(rgb);
    // Grey belongs to no band: tinting it would invent colour that is not
    // in the frame.
    if (hsl.y <= 0.001) return rgb;

    float deg = mod(hsl.x * 360.0, 360.0);
    int lo = 7;
    float t = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = kBandCentres[i];
        float b = i == 7 ? 360.0 : kBandCentres[i + 1];
        if (deg >= a && deg < b) {
            lo = i;
            t = (deg - a) / (b - a);
            break;
        }
    }
    if (deg < kBandCentres[0]) {
        lo = 7;
        t = (deg + 360.0 - kBandCentres[7]) / (360.0 + kBandCentres[0] - kBandCentres[7]);
    }
    int hi = (lo + 1) % 8;
    float wLo = 1.0 - t;

    float dh = wLo * uHslHue[lo] + t * uHslHue[hi];
    float ds = wLo * uHslSat[lo] + t * uHslSat[hi];
    float dl = wLo * uHslLum[lo] + t * uHslLum[hi];

    hsl.x = fract(hsl.x + dh * 30.0 / 360.0);
    hsl.y = clamp(hsl.y * (1.0 + ds), 0.0, 1.0);
    hsl.z = clamp(hsl.z + dl * 0.35, 0.0, 1.0);
    return hsl2rgb(hsl);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    // Impeller hands the snapshot to the sampler with its origin at the
    // bottom, so a texture read straight from FlutterFragCoord comes back
    // mirrored top to bottom. Everything this shader does is per-pixel, so
    // nothing but the lookup itself noticed — the picture simply arrived
    // upside down. Flipping here fixes the read for every sample below it.
    uv.y = 1.0 - uv.y;
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

    rgb *= uColorCast;

    if (uHslOn > 0.5) {
        rgb = gradeHsl(clamp(rgb, 0.0, 1.0));
    }

    if (uGrain > 0.0) {
        float n = hash(FlutterFragCoord().xy + vec2(uSeed)) - 0.5;
        rgb += vec3(n * uGrain);
    }

    if (uFilmGrain > 0.0) {
        // Coarser and colourless, and strongest through the midtones: film
        // grain is silver in the emulsion, so it lands on brightness rather
        // than colour, and there is none of it to see in clear film or in
        // black that has already gone solid.
        float n = hash(floor(FlutterFragCoord().xy * 0.6) + vec2(uSeed * 3.1)) - 0.5;
        float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        rgb += vec3(n * uFilmGrain * 4.0 * luma * (1.0 - luma));
    }

    rgb = clamp(rgb, 0.0, 1.0);
    fragColor = vec4(rgb * src.a, src.a);
}
