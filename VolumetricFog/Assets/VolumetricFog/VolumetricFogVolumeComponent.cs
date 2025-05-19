using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Harumaron
{
#if UNITY_2023_1_OR_NEWER
    [VolumeComponentMenu("Custom/Volumetric Fog")]
#if UNITY_6000_0_OR_NEWER
    [VolumeRequiresRendererFeatures(typeof(VolumetricFogRendererFeature))]
#endif
    [SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
#else
[VolumeComponentMenuForRenderPipeline("Custom/Volumetric Fog", typeof(UniversalRenderPipeline))]
#endif
    public sealed class VolumetricFogVolumeComponent : VolumeComponent, IPostProcessComponent
    {
        [Header("有効化")]
        public BoolParameter enabled = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);
        
        [Header("Distances")]
        [Header("Fogを描画する最大距離")]
        public ClampedFloatParameter distance = new ClampedFloatParameter(64.0f, 0.0f, 512.0f);

        [Header("Ground")]
        [Header("地面の有効化 (地面より下のFogは無くなる)")]
        public BoolParameter enableGround = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);

        [Header("地面の高さ")]
        public FloatParameter groundHeight = new FloatParameter(0.0f);

        [Header("Lighting")]
        [Header("Fogの密度")]
        public ClampedFloatParameter density = new ClampedFloatParameter(0.2f, 0.0f, 1.0f);

        [Header("光の減衰距離")]
        public MinFloatParameter attenuationDistance = new MinFloatParameter(128.0f, 0.05f);
        
        [Header("Adaptive Probe Volume")]
#if UNITY_2023_1_OR_NEWER
        public BoolParameter enableAPVContribution = new BoolParameter(false, BoolParameter.DisplayType.Checkbox, true);

        public ClampedFloatParameter APVContributionWeight = new ClampedFloatParameter(1.0f, 0.0f, 1.0f);
#endif

        [Header("Performance & Quality")]
        [Header("レイマーチングのステップ数　(ステップを増やすほど精度が向上する)")]
        public ClampedIntParameter maxSteps = new ClampedIntParameter(128, 8, 256);

        [Header("Fogのガウスブラーの試行回数")]
        public ClampedIntParameter blurIterations = new ClampedIntParameter(2, 1, 4);


        public VolumetricFogVolumeComponent() : base()
        {
            displayName = "Volumetric Fog";
        }

        public bool IsActive()
        {
            return enabled.value && distance.value > 0.0f && density.value > 0.0f;
        }
    }
}