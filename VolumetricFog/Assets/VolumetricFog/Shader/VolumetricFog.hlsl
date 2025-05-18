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
#include "./ProjectionUtils.hlsl"

int _FrameCount;
uint _CustomAdditionalLightsCount;
float _Distance;
float _BaseHeight;
float _MaximumHeight;
float _GroundHeight;
float _Density;
float _Absortion;
float _APVContributionWeight;
float3 _Tint;
int _MaxSteps;

float _Anisotropies[MAX_VISIBLE_LIGHTS + 1];
float _Scatterings[MAX_VISIBLE_LIGHTS + 1];
float _RadiiSq[MAX_VISIBLE_LIGHTS];

// Calculates the initial raymarching parameters.
void CalculateRaymarchingParams(float2 uv, out float3 rayOrigin, out float3 rayDirection,
                                out float iniOffsetToNearPlane, out float offsetLength, out float3 rdPhase)
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
    rdPhase = rayDirection;

    // In perspective, ray direction should vary in length depending on which fragment we are at.

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

// Gets the main light phase function.
float GetMainLightPhase(float3 rd)
{
    #if _MAIN_LIGHT_CONTRIBUTION_DISABLED
    return 0.0;
    #else
    return CornetteShanksPhaseFunction(_Anisotropies[_CustomAdditionalLightsCount], dot(rd, GetMainLight().direction));
    #endif
}

// Gets the fog density at the given world height.
float GetFogDensity(float posWSy)
{
    // 高さに基づく補間値を計算（0-1）
    float t = saturate((posWSy - _BaseHeight) / (_MaximumHeight - _BaseHeight));

    // 上下を反転（高いほど薄く、低いほど濃く） 
    t = 1.0 - t;

    // 地面より下はフォグなし
    t = lerp(t, 0.0, posWSy < _GroundHeight);

    // 基本密度と掛け合わせて最終的な密度を返す
    return _Density * t;
}

// Gets the GI evaluation from the adaptive probe volume at one raymarch step.
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

// Gets the main light color at one raymarch step.
float3 GetStepMainLightColor(float3 currPosWS, float phaseMainLight, float density)
{
    #if _MAIN_LIGHT_CONTRIBUTION_DISABLED
    return float3(0.0, 0.0, 0.0);
    #endif

    // メインライトの情報を取得
    Light mainLight = GetMainLight();

    // ワールド座標からシャドウマップの座標系に変換
    float4 shadowCoord = TransformWorldToShadowCoord(currPosWS);

    // シャドウマップのサンプリング
    mainLight.shadowAttenuation = VolumetricMainLightRealtimeShadow(shadowCoord);

    // ライトクッキーをサンプリング
    #if _LIGHT_COOKIES
    mainLight.color *= SampleMainLightCookie(currPosWS);
    #endif

    return (mainLight.color * _Tint) // 外部パラメータの色を掛け合わせる
        * (mainLight.shadowAttenuation // 影の減衰度
            * phaseMainLight // フォグの散乱
            * density // フォグの密度
            * _Scatterings[_CustomAdditionalLightsCount]); // メインライトの散乱を掛け合わせる
}

// Gets the accumulated color from additional lights at one raymarch step.
float3 GetStepAdditionalLightsColor(float2 uv, float3 currPosWS, float3 rd, float density)
{
    #if _ADDITIONAL_LIGHTS_CONTRIBUTION_DISABLED
    return float3(0.0, 0.0, 0.0);
    #endif

    #if _FORWARD_PLUS
    // Forward+ rendering path needs this data before the light loop.
    // Forward+に必要なレンダリングデータを設定
    InputData inputData = (InputData)0;
    inputData.normalizedScreenSpaceUV = uv;
    inputData.positionWS = currPosWS;
    #endif

    float3 additionalLightsColor = float3(0.0, 0.0, 0.0);

    // Loop differently through lights in Forward+ while considering Forward and Deferred too.
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
        // See universal\ShaderLibrary\RealtimeLights.hlsl - GetAdditionalPerObjectLight.
        #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
        float4 additionalLightPos = _AdditionalLightsBuffer[lightIndex].position;
        #else
        float4 additionalLightPos = _AdditionalLightsPosition[lightIndex];
        #endif

        // This is useful for both spotlights and pointlights. For the latter it is specially true when the point light is inside some geometry and casts shadows.
        // Gradually reduce additional lights scattering to zero at their origin to try to avoid flicker-aliasing.

        // サンプリング座標からライト座標へのベクトルを計算
        float3 distToPos = additionalLightPos.xyz - currPosWS;

        // ベクトルの長さの2乗を計算
        float distToPosMagnitudeSq = dot(distToPos, distToPos);

        // ライトの影響範囲を考慮して、散乱を補完
        float newScattering = smoothstep(0.0, _RadiiSq[lightIndex], distToPosMagnitudeSq);
        newScattering *= newScattering;
        newScattering *= _Scatterings[lightIndex];

        // If directional lights are also considered as additional lights when more than 1 is used, ignore the previous code when it is a directional light.
        // They store direction in additionalLightPos.xyz and have .w set to 0, while point and spotlights have it set to 1.
        // newScattering = lerp(1.0, newScattering, additionalLightPos.w);

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

// Calculates the volumetric fog. Returns the color in the RGB channels and transmittance in alpha.
float4 VolumetricFog(float2 uv, float2 positionCS)
{
    float3 rayOrigin; // カメラのワールド座標
    float3 rayDirection; // レイの方向
    float initialOffsetNearPlane; // 近接平面からのオフセット
    float offsetLength; // レイの長さ
    float3 rdPhase; // レイの方向ベクトル

    // パラメータの計算
    CalculateRaymarchingParams(uv, rayOrigin, rayDirection, initialOffsetNearPlane, offsetLength, rdPhase);

    offsetLength -= initialOffsetNearPlane;

    // レイマーチングを開始する座標
    float3 roNearPlane = rayOrigin + rayDirection * initialOffsetNearPlane;

    // 1ステップの長さ
    float stepLength = (_Distance - initialOffsetNearPlane) / (float)_MaxSteps;

    // InterleavedGradientNoiseを使用して、レイマーチングのステップにジッターを追加
    // ノイズによって、レイマーチングのステップ均一になることで、模様を軽減させる
    float jitter = stepLength * InterleavedGradientNoise(positionCS, _FrameCount);

    // フォグの散乱を計算する
    float phaseMainLight = GetMainLightPhase(rdPhase);

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

        // We are making the space between the camera position and the near plane "non existant", as if fog did not exist there.
        // However, it removes a lot of noise when in closed environments with an attenuation that makes the scene darker
        // and certain combinations of field of view, raymarching resolution and camera near plane.
        // In those edge cases, it looks so much better, specially when near plane is higher than the minimum (0.01) allowed.

        // ワールド座標を算出
        float3 currPosWS = roNearPlane + rayDirection * dist;

        // フォグの密度を算出
        // 位置のY座標を使用して、地面の高さも考慮してフォグの密度を計算
        float density = GetFogDensity(currPosWS.y);

        // フォグの密度が0以下の場合はスキップ
        UNITY_BRANCH
        if (density <= 0.0)
            continue;

        // 光の吸収を計算
        float stepAttenuation = exp(minusStepLengthTimesAbsortion * density);
        transmittance *= stepAttenuation;

        // APV、メインライト、追加ライトの色を計算
        float3 apvColor = GetStepAdaptiveProbeVolumeEvaluation(uv, currPosWS, density);
        float3 mainLightColor = GetStepMainLightColor(currPosWS, phaseMainLight, density);
        float3 additionalLightsColor = GetStepAdditionalLightsColor(uv, currPosWS, rayDirection, density);

        // TODO: Additional contributions? Reflection probes, etc...
        // 全て足し合わせた色を計算
        float3 stepColor = apvColor + mainLightColor + additionalLightsColor;

        // 透過率を考慮して最終的な色を加算
        volumetricFogColor += (stepColor * (transmittance * stepLength));

        // TODO: Break out when transmittance reaches low threshold and remap the transmittance when doing so.
        // It does not make sense right now because the fog does not properly support transparency, so having dense fog leads to issues.
    }

    return float4(volumetricFogColor, transmittance);
}

#endif
