#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    float reveal;
    float time;
    vec4 glowColor;
};

// Lightweight hash for OLED-safe 8-bit gradient dithering (prevents banding)
float ditherNoise(vec2 uv) {
    vec3 p3 = fract(vec3(uv.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z) - 0.5;
}

void main() {
    float aspect = resolution.x / max(1.0, resolution.y);
    vec2 p = (qt_TexCoord0 - vec2(0.5)) * vec2(aspect, 1.0);

    // Smooth emergence radius & energy as splash glow rises from darkness
    float rev = clamp(reveal, 0.0, 1.0);
    float easeRev = 1.0 - pow(1.0 - rev, 2.6);
    float spread = mix(0.42, 1.0, easeRev);

    // Primary soft radial atmospheric bloom (mirrors default shell wallpaper)
    vec2 centerOffset = vec2(0.0, -0.015);
    float dMain = length((p - centerOffset) / vec2(1.12 * spread, 0.92 * spread));
    float outerHalo = exp(-dMain * dMain * 3.4) * 0.075;
    float innerAura = exp(-dMain * dMain * 15.0) * 0.065;

    // Subtle drifting crescent rim sheen behind the orbital nucleus
    vec2 drift = vec2(cos(time * 0.85) * 0.032 + 0.028, sin(time * 0.7) * 0.022 - 0.018);
    float dRim = length((p - drift) / vec2(0.60 * spread, 0.60 * spread));
    float rimGlow = exp(-dRim * dRim * 6.5) * 0.035;

    // Soft grounded shadow pool just beneath the emblem (matches default.png depth)
    vec2 shadowPos = p - vec2(0.0, 0.11);
    float dShadow = length(shadowPos / vec2(0.24, 0.12));
    float underShadow = 1.0 - exp(-dShadow * dShadow * 2.4) * 0.38;

    float intensity = (outerHalo + innerAura + rimGlow) * underShadow * easeRev;

    // Subtle filmic dither to keep dark OLED falloff silky smooth
    float dither = ditherNoise(gl_FragCoord.xy) / 255.0;
    float alpha = clamp(intensity + dither * step(0.002, intensity), 0.0, 0.65) * qt_Opacity;

    // Slight cool silver-monochrome tint that still respects active Theme.text
    vec3 tint = mix(vec3(0.84, 0.87, 0.92), glowColor.rgb, 0.55);
    fragColor = vec4(tint * alpha, alpha);
}
