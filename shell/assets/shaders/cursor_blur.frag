#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float blurOpacity;
    vec2 cursorUvSize;
    vec2 velUv;
    vec2 prevVelUv;
    float leadFactor;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    // 32-tap continuous directional shutter integration along curved quadratic trajectory.
    // Head sits at +leadFactor * velUv (compensating IPC + Wayland overlay latency) and trails
    // smoothly along -velUv bending into -prevVelUv for curved mouse arcs.
    vec2 headOff = velUv * leadFactor;
    vec2 p1 = -velUv * 0.52;
    vec2 p2 = -(velUv + prevVelUv * 0.42);

    vec4 accum = vec4(0.0);
    float totalW = 0.0;

    const int SAMPLES = 32;
    for (int i = 0; i < SAMPLES; ++i) {
        float t = (float(i) + 0.5) / float(SAMPLES);
        float invT = 1.0 - t;
        // Quadratic Bezier from (0,0) -> p1 -> p2, shifted by predictive headOff
        vec2 trailOff = headOff + (2.0 * invT * t * p1) + (t * t * p2);
        vec2 sUv = (qt_TexCoord0 - vec2(0.5) - trailOff) / cursorUvSize + vec2(0.5);

        // Smooth optical shutter falloff (strongest right behind cursor head, silky feathered tail)
        float w = pow(invT, 1.55);
        totalW += w;

        if (sUv.x >= 0.0 && sUv.x <= 1.0 && sUv.y >= 0.0 && sUv.y <= 1.0) {
            accum += texture(source, sUv) * w;
        }
    }

    vec4 blurred = (totalW > 0.0001) ? (accum / totalW) : vec4(0.0);
    // Boost perceived smear energy slightly since multi-tap averaging dilutes thin cursor strokes
    float gain = clamp(blurOpacity * 1.45, 0.0, 1.05) * qt_Opacity;
    fragColor = blurred * gain;
}
