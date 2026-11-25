#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texelSize;
    float threshold;
    float softness;
    vec4 pillColor;
    vec4 pillColorMid;
    vec4 pillColor2;
    float angleRad;
    float gradEnabled;
};

layout(binding = 1) uniform sampler2D source;

float ditherNoise(vec2 uv) {
    vec3 p3 = fract(vec3(uv.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z) - 0.5;
}

void main() {
    // 25-tap separable-style isotropic blur kernel (~6px radius at 1x) for liquid metaball bridge
    float sum = 0.0;
    float totalWeight = 0.0;
    for (int x = -3; x <= 3; ++x) {
        for (int y = -3; y <= 3; ++y) {
            float r2 = float(x * x + y * y);
            float w = exp(-r2 / 5.5);
            vec2 offset = vec2(float(x), float(y)) * texelSize * 2.2;
            sum += texture(source, qt_TexCoord0 + offset).a * w;
            totalWeight += w;
        }
    }
    float alpha = sum / totalWeight;
    float mask = smoothstep(threshold - softness, threshold + softness, alpha);
    vec4 fillCol = pillColor;
    if (gradEnabled > 0.5) {
        vec2 dir = vec2(sin(angleRad), -cos(angleRad));
        vec2 uv = qt_TexCoord0 - vec2(0.5);
        float halfSpan = 0.5 * (abs(dir.x) + abs(dir.y));
        float t = clamp(dot(uv, dir) / max(0.0001, halfSpan) * 0.5 + 0.5, 0.0, 1.0);
        float omt = 1.0 - t;
        fillCol = omt * omt * pillColor + 2.0 * omt * t * pillColorMid + t * t * pillColor2;
        fillCol.rgb = clamp(fillCol.rgb + vec3(ditherNoise(gl_FragCoord.xy) / 255.0), 0.0, 1.0);
    }
    float outAlpha = mask * qt_Opacity * fillCol.a;
    fragColor = vec4(fillCol.rgb * outAlpha, outAlpha);
}
