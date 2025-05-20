#ifndef DEPTH_AWARE_UPSAMPLE_INCLUDED
#define DEPTH_AWARE_UPSAMPLE_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "./DeclareDownsampledDepthTexture.hlsl"
#include "./ProjectionUtils.hlsl"

#pragma target 4.5

// Upsamples the given texture using both the downsampled and full resolution depth information.
float4 DepthAwareUpsample(float2 uv, TEXTURE2D_X(textureToUpsample))
{
    // 周囲4テクセルのUV座標を計算
    float2 downsampledTexelSize = _DownsampledCameraDepthTexture_TexelSize.xy;
    float2 downsampledTopLeftCornerUv = uv - (downsampledTexelSize * 0.5);
    float2 uvs[4] =
    {
        downsampledTopLeftCornerUv + float2(0.0, downsampledTexelSize.y),
        downsampledTopLeftCornerUv + downsampledTexelSize.xy,
        downsampledTopLeftCornerUv + float2(downsampledTexelSize.x, 0.0),
        downsampledTopLeftCornerUv
    };

    // 4テクセルのダウンサンプリングされた深度値を取得
    float4 downsampledDepths = GATHER_RED_TEXTURE2D_X(_DownsampledCameraDepthTexture, sampler_PointClamp, uv);

    // フル解像度の深度値を取得
    float fullResDepth = SampleSceneDepth(uv);

    // フル解像度の深度値をカメラからの距離に変換
    float fullResLinearEyeDepth = LinearEyeDepthConsiderProjection(fullResDepth);

    // ダウンサンプルしたテクスチャの深度値をカメラからの距離に変換
    float linearEyeDepth = LinearEyeDepthConsiderProjection(downsampledDepths[0]);

    // ダウンサンプルとフル解像度のの深度の差を計算
    float minLinearEyeDepthDist = abs(fullResLinearEyeDepth - linearEyeDepth);

    float2 nearestUv = uvs[0];
    float relativeDepthThreshold = fullResLinearEyeDepth * 0.1;
    int numValidDepths = minLinearEyeDepthDist < relativeDepthThreshold;

    UNITY_UNROLL
    for (int i = 1; i < 4; ++i)
    {
        // ダウンサンプルしたテクスチャの深度値をカメラからの距離に変換
        linearEyeDepth = LinearEyeDepthConsiderProjection(downsampledDepths[i]);

        // ダウンサンプルとフル解像度のの深度の差を計算
        float linearEyeDepthDist = abs(fullResLinearEyeDepth - linearEyeDepth);

        // ダウンサンプルしたテクスチャの深度値が現在の最小深度値よりも近い場合、最も近いUV座標を更新
        bool updateNearest = linearEyeDepthDist < minLinearEyeDepthDist;
        minLinearEyeDepthDist = updateNearest ? linearEyeDepthDist : minLinearEyeDepthDist;
        nearestUv = updateNearest ? uvs[i] : nearestUv;

        numValidDepths += (linearEyeDepthDist < relativeDepthThreshold);
    }

    // 4つの深度値がすべて有効な場合、最も近いUV座標を使用してテクスチャをサンプリング
    UNITY_BRANCH
    if (numValidDepths == 4)
        return SAMPLE_TEXTURE2D_X(textureToUpsample, sampler_LinearClamp, uv);
    else
        return SAMPLE_TEXTURE2D_X(textureToUpsample, sampler_PointClamp, nearestUv);
}

#endif
