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
};

layout(binding = 1) uniform sampler2D source;

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
    float outAlpha = mask * qt_Opacity * pillColor.a;
    fragColor = vec4(pillColor.rgb * outAlpha, outAlpha);
}
