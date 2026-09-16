#version 460 core
#include <flutter/runtime_effect.glsl>

// 液态玻璃（iOS Liquid Glass 风格）背景滤镜。
//
// 与普通的「高斯模糊玻璃」不同，这里对背景做了真实的**边缘折射**：
// 用圆角矩形的有向距离场求出边缘法线，沿法线把背景往内推，
// 于是靠近边缘的背景被压缩、产生透镜凸起感；再叠上饱和度提升、
// 玻璃底色与左上方向的镜面高光。
//
// 约定（由引擎绑定，见 ImageFilter.shader 文档）：
//   - 第一个 uniform 必须是 vec2，引擎会写入输入纹理的尺寸
//   - 第一个 sampler2D uniform 会绑定为滤镜输入

precision highp float;

uniform vec2 u_size;        // 输入纹理尺寸（设备像素，引擎写入）
uniform sampler2D u_texture; // 滤镜输入（引擎绑定）
uniform vec2 u_logical;     // 控件逻辑尺寸
uniform float u_radius;     // 圆角半径（逻辑像素）
uniform float u_refraction; // 边缘折射强度（逻辑像素）
uniform vec4 u_tint;        // 玻璃底色（rgb + 底色浓度）
uniform float u_saturation; // 透过来的背景饱和度提升
uniform float u_highlight;  // 镜面高光强度
uniform float u_opacity;    // 整块玻璃的不透明度（用于淡入）

out vec4 frag_color;

/// 圆角矩形有向距离场：内部为负，外部为正
float sdRoundedBox(vec2 p, vec2 half_size, float r) {
  vec2 q = abs(p) - half_size + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
  // 逻辑像素 -> 纹理像素的比例（兼容高 DPI）
  float k = u_size.x / max(u_logical.x, 1.0);

  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / u_size;

#ifdef IMPELLER_TARGET_OPENGLES
  // OpenGL 后端的纹理是上下翻转的，采样前需要还原
  uv.y = 1.0 - uv.y;
#endif

  vec2 half_size = u_size * 0.5;
  vec2 p = frag - half_size;

  float radius = u_radius * k;
  float d = sdRoundedBox(p, half_size, radius);

  // 折射只发生在贴近边缘的一条窄带里
  float band = max(u_refraction * k * 3.0, 2.0);
  float edge = 1.0 - smoothstep(-band, 0.0, d);

  // 用 SDF 的梯度求边缘法线
  vec2 grad = vec2(
    sdRoundedBox(p + vec2(1.0, 0.0), half_size, radius) - d,
    sdRoundedBox(p + vec2(0.0, 1.0), half_size, radius) - d
  );
  vec2 normal = normalize(grad + vec2(1e-6));

  // 沿法线把背景往内推：边缘处背景被压缩，形成透镜（放大）效果
  vec2 offset = -normal * u_refraction * k * pow(edge, 1.7);
  vec2 sample_uv = clamp(uv + offset / u_size, vec2(0.0005), vec2(0.9995));

  // 3x3 轻微模糊，做出玻璃的通透磨砂感（比纯高斯省，且能与折射共存）
  vec2 texel = 1.0 / u_size;
  vec3 color = vec3(0.0);
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 o = vec2(float(x), float(y)) * texel * 1.6;
      color += texture(u_texture, clamp(sample_uv + o, vec2(0.0), vec2(1.0))).rgb;
    }
  }
  color /= 9.0;

  // iOS 液态玻璃会把透过的背景「提鲜」，避免玻璃发灰
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, u_saturation);

  // 叠加玻璃自身的底色
  color = mix(color, u_tint.rgb, u_tint.a);

  // 镜面高光：左上方向的光打在边缘法线上最亮
  vec2 light_dir = normalize(vec2(-0.5, -0.86));
  float rim = pow(edge, 2.4) * max(dot(normal, light_dir), 0.0);

  // 内侧一圈更柔和的亮边，模拟玻璃的厚度
  float inner = smoothstep(-band * 1.1, 0.0, d) *
      (1.0 - smoothstep(-band * 0.12, 0.0, d));

  color += u_highlight * (rim * 0.85 + inner * 0.4);

  // 输出带透明度：整体淡入时不会在玻璃上套一层 Opacity，
  // 避免 Opacity 图层让 BackdropFilter 拿不到背景
  frag_color = vec4(color, u_opacity);
}
