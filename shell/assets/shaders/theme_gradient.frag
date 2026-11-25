#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float cornerRadius;
    float angleRad;
    vec4 color1;
    vec4 color2;
};

float ditherNoise(vec2 uv) {
    vec3 p3 = fract(vec3(uv.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z) - 0.5;
}

float sdRoundedBox(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - (halfSize - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    float shapeAlpha = 1.0;
    if (cornerRadius > 0.5) {
        vec2 halfSize = max(vec2(1.0), size * 0.5);
        float r = clamp(cornerRadius, 0.0, min(halfSize.x, halfSize.y));
        vec2 p = (qt_TexCoord0 - vec2(0.5)) * size;
        float dist = sdRoundedBox(p, halfSize, r);
        shapeAlpha = 1.0 - smoothstep(-0.65, 0.65, dist);
    }

    vec2 dir = vec2(sin(angleRad), -cos(angleRad));
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float halfSpan = 0.5 * (abs(dir.x) + abs(dir.y));
    float t = clamp(dot(uv, dir) / max(0.0001, halfSpan) * 0.5 + 0.5, 0.0, 1.0);

    vec4 col = mix(color1, color2, t);
    col.rgb = clamp(col.rgb + vec3(ditherNoise(gl_FragCoord.xy) / 255.0), 0.0, 1.0);

    float outAlpha = shapeAlpha * qt_Opacity * col.a;
    fragColor = vec4(col.rgb * outAlpha, outAlpha);
}
