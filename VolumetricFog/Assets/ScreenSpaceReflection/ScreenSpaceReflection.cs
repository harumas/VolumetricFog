using System;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace PostProcessing
{
#if UNITY_2023_1_OR_NEWER
    [VolumeComponentMenu("Custom/Screen Space Reflection")]
#if UNITY_6000_0_OR_NEWER
    [VolumeRequiresRendererFeatures(typeof(ScreenSpaceReflectionRenderer))]
#endif
    [SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
#else
[VolumeComponentMenuForRenderPipeline("Custom/Screen Space Reflection", typeof(UniversalRenderPipeline))]
#endif
    public class ScreenSpaceReflection : VolumeComponent, IPostProcessComponent
    {
        public ClampedFloatParameter intensity = new ClampedFloatParameter(value: 0f, min: 0, max: 1, overrideState: true);

        public bool IsActive() => intensity.value > 0;

        public bool IsTileCompatible() => true;
    }
}