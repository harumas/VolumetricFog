#include <HLSLSupport.cginc>
#ifndef DEPTH_AWARE_GAUSSIAN_BLUR_INCLUDED
#define DEPTH_AWARE_GAUSSIAN_BLUR_INCLUDED

#include "./DeclareDownsampledDepthTexture.hlsl"
#include "./ProjectionUtils.hlsl"

#define KERNEL_RADIUS 4

static const float KernelWeights[] = {0.2026, 0.1790, 0.1240, 0.0672, 0.0285};

float4 DepthAwareGaussianBlur(float2 uv,
                              float2 dir,
                              TEXTURE2D_X(textureToBlur),
                              SAMPLER(sampler_TextureToBlur),
                              float2 textureToBlurTexelSizeXy)
{
    // 中心ピクセルの色と深度を取得
    float4 centerSample = SAMPLE_TEXTURE2D_X(textureToBlur, sampler_TextureToBlur, uv);
    float centerDepth = SampleDownsampledSceneDepth(uv);
    float centerLinearEyeDepth = LinearEyeDepthConsiderProjection(centerDepth);

    int i = 0;
    float3 rgbResult = centerSample.rgb * KernelWeights[i]; // 重み付き中心ピクセルカラー
    float weights = KernelWeights[i]; // 重みの合計

    float2 texelSizeTimesDir = textureToBlurTexelSizeXy * dir; // ブラー方向のテクセルサイズ

    // カーネルの負のオフセットを反復処理
    UNITY_UNROLL
    for (i = -KERNEL_RADIUS; i < 0; ++i)
    {
        float2 uvSample = uv + (float)i * texelSizeTimesDir; // uv座標

        float depth = SampleDownsampledSceneDepth(uvSample); // サンプリングした深度
        float linearEyeDepth = LinearEyeDepthConsiderProjection(depth);
        float depthDiff = abs(centerLinearEyeDepth - linearEyeDepth) * 0.5f; // 深度差を計算 (エッジ部分を抑制する)
        float weight = exp(-depthDiff * depthDiff) * KernelWeights[-i]; // カーネルをかけ合わせた最終的な重み

        float3 rgb = SAMPLE_TEXTURE2D_X(textureToBlur, sampler_TextureToBlur, uvSample).rgb;
        rgbResult += rgb * weight; // 色に重みを適用して加算
        weights += weight;
    }

    // カーネルの負のオフセットを反復処理
    UNITY_UNROLL
    for (i = 1; i <= KERNEL_RADIUS; ++i)
    {
        float2 uvSample = uv + (float)i * texelSizeTimesDir;

        float depth = SampleDownsampledSceneDepth(uvSample);
        float linearEyeDepth = LinearEyeDepthConsiderProjection(depth);
        float depthDiff = abs(centerLinearEyeDepth - linearEyeDepth) * 0.5f;
        float weight = exp(-depthDiff * depthDiff) * KernelWeights[i];

        float3 rgb = SAMPLE_TEXTURE2D_X(textureToBlur, sampler_TextureToBlur, uvSample).rgb;
        rgbResult += rgb * weight;
        weights += weight;
    }

    // 結果を正規化して返す
    return float4(rgbResult * rcp(weights), centerSample.a);
}

#endif
