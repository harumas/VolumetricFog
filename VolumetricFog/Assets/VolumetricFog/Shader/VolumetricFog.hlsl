#ifndef VOLUMETRIC_FOG_INCLUDED
#define VOLUMETRIC_FOG_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"
#if UNITY_VERSION >= 202310 && _APV_CONTRIBUTION_ENABLED
#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
        #include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#endif
#endif
#include "./DeclareDownsampledDepthTexture.hlsl"
#include "./VolumetricShadows.hlsl"

int _FrameCount;
uint _CustomAdditionalLightsCount;
float _Distance;
float _GroundHeight;
float _Density;
float _Absortion;
float _APVContributionWeight;
int _MaxSteps;

float _Anisotropies[MAX_VISIBLE_LIGHTS];
float _Scatterings[MAX_VISIBLE_LIGHTS];
float _RadiiSq[MAX_VISIBLE_LIGHTS];

// Calculates the initial raymarching parameters.
void CalculateRaymarchingParams(float2 uv, out float3 rayOrigin, out float3 rayDirection,
                                out float iniOffsetToNearPlane, out float offsetLength)
{
    // ダウンサンプルした深度をサンプリング
    float depth = SampleDownsampledSceneDepth(uv);

    float3 posWS;

    // カメラのワールド座標を取得
    rayOrigin = GetCameraPositionWS();

    #if !UNITY_REVERSED_Z
        depth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, depth);
    #endif

    // 指定したuv座標からワールド空間の位置を計算
    posWS = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);

    float3 offset = posWS - rayOrigin;
    offsetLength = length(offset); // レイの長さ
    rayDirection = offset / offsetLength; // 正規化したレイの方向

    // カメラの正面ベクトル
    float3 camFwd = normalize(-UNITY_MATRIX_V[2].xyz);

    // カメラの正面ベクトルとレイの方向ベクトルの内積を計算
    float cos = dot(camFwd, rayDirection);

    // レイの長さの補正値
    float fragElongation = 1.0 / cos;

    // 近接平面からのオフセットを計算?
    // 正面ベクトルに近いほど値が小さくなり、平面に沿ったオフセットになる
    iniOffsetToNearPlane = fragElongation * _ProjectionParams.y;
}

float3 GetStepAdaptiveProbeVolumeEvaluation(float2 uv, float3 posWS, float density)
{
    float3 apvDiffuseGI = float3(0.0, 0.0, 0.0);

    #if UNITY_VERSION >= 202310 && _APV_CONTRIBUTION_ENABLED
    #if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
        EvaluateAdaptiveProbeVolume(posWS, uv * _ScreenSize.xy, apvDiffuseGI);
        apvDiffuseGI = apvDiffuseGI * _APVContributionWeight * density;
    #endif
    #endif

    return apvDiffuseGI;
}

float3 GetStepAdditionalLightsColor(float2 uv, float3 currPosWS, float3 rd, float density)
{
    #if _ADDITIONAL_LIGHTS_CONTRIBUTION_DISABLED
    return float3(0.0, 0.0, 0.0);
    #endif

    #if _FORWARD_PLUS
    // Forward+に必要なレンダリングデータを設定
    InputData inputData = (InputData)0;
    inputData.normalizedScreenSpaceUV = uv;
    inputData.positionWS = currPosWS;
    #endif

    float3 additionalLightsColor = float3(0.0, 0.0, 0.0);

    // 各追加ライトに対してループ
    LIGHT_LOOP_BEGIN(_CustomAdditionalLightsCount)
        // 散乱係数が0以下の場合はスキップ
        UNITY_BRANCH
        if (_Scatterings[lightIndex] <= 0.0)
            continue;

        // 追加ライトの情報を取得
        Light additionalLight = GetAdditionalPerObjectLight(lightIndex, currPosWS);

        // シャドウマップのサンプリング
        additionalLight.shadowAttenuation = VolumetricAdditionalLightRealtimeShadow(
            lightIndex, currPosWS, additionalLight.direction);

        // ライトクッキーをサンプリング
        #if _LIGHT_COOKIES
        additionalLight.color *= SampleAdditionalLightCookie(lightIndex, currPosWS);
        #endif

        // 追加ライトの座標を取得
        #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
        float4 additionalLightPos = _AdditionalLightsBuffer[lightIndex].position;
        #else
        float4 additionalLightPos = _AdditionalLightsPosition[lightIndex];
        #endif

        // サンプリング座標からライト座標へのベクトルを計算
        float3 distToPos = additionalLightPos.xyz - currPosWS;

        // ベクトルの長さの2乗を計算
        float distToPosMagnitudeSq = dot(distToPos, distToPos);

        // ライトの影響範囲を考慮して、散乱を補完
        float newScattering = smoothstep(0.0, _RadiiSq[lightIndex], distToPosMagnitudeSq);
        newScattering *= newScattering;
        newScattering *= _Scatterings[lightIndex];

        float phase = CornetteShanksPhaseFunction(_Anisotropies[lightIndex], dot(rd, additionalLight.direction));
        additionalLightsColor += additionalLight.color // ライトのカラー
            * (additionalLight.shadowAttenuation // 影の減衰度
                * additionalLight.distanceAttenuation // 距離減衰
                * phase // フォグの散乱
                * density // フォグの密度
                * newScattering); // 距離による散乱の補完
    LIGHT_LOOP_END

    return additionalLightsColor;
}

float4 VolumetricFog(float2 uv, float2 positionCS)
{
    float3 rayOrigin; // カメラのワールド座標
    float3 rayDirection; // レイの方向
    float initialOffsetNearPlane; // 近接平面からのオフセット
    float offsetLength; // レイの長さ

    // パラメータの計算
    CalculateRaymarchingParams(uv, rayOrigin, rayDirection, initialOffsetNearPlane, offsetLength);

    offsetLength -= initialOffsetNearPlane;

    // レイマーチングを開始する座標
    float3 roNearPlane = rayOrigin + rayDirection * initialOffsetNearPlane;

    // 1ステップの長さ
    float stepLength = (_Distance - initialOffsetNearPlane) / (float)_MaxSteps;

    // InterleavedGradientNoiseを使用して、レイマーチングのステップにジッターを追加
    // ノイズによって、レイマーチングのステップ均一になることで、模様を軽減させる
    float jitter = stepLength * InterleavedGradientNoise(positionCS, _FrameCount);

    // 1ステップの光の減衰
    float minusStepLengthTimesAbsortion = -stepLength * _Absortion;

    // フォグの色
    float3 volumetricFogColor = float3(0.0, 0.0, 0.0);

    // フォグの透過率
    float transmittance = 1.0;

    UNITY_LOOP
    for (int i = 0; i < _MaxSteps; ++i)
    {
        // サンプリング位置を計算
        float dist = jitter + i * stepLength;

        // 最大の長さを超えた場合は終了
        UNITY_BRANCH
        if (dist >= offsetLength)
            break;

        // ワールド座標を算出
        float3 currPosWS = roNearPlane + rayDirection * dist;

        // 地面より下はフォグなし
        float density = lerp(_Density, 0.0, currPosWS.y < _GroundHeight);

        // フォグの密度が0以下の場合はスキップ
        UNITY_BRANCH
        if (density <= 0.0)
            continue;

        // 光の吸収を計算
        float stepAttenuation = exp(minusStepLengthTimesAbsortion * density);
        transmittance *= stepAttenuation;

        // APV、追加ライトの色を計算
        float3 apvColor = GetStepAdaptiveProbeVolumeEvaluation(uv, currPosWS, density);
        float3 additionalLightsColor = GetStepAdditionalLightsColor(uv, currPosWS, rayDirection, density);

        // 全て足し合わせた色を計算
        float3 stepColor = apvColor + additionalLightsColor;

        // 透過率を考慮して最終的な色を加算
        volumetricFogColor += stepColor * (transmittance * stepLength);
    }

    return float4(volumetricFogColor, transmittance);
}

#endif
