using System;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace Harumaron
{
    public class VolumetricFogRenderPass : ScriptableRenderPass
    {
        private const int DownsampleFactor = 2;
        private const string DownsampledCameraDepthRTName = "_DownsampledCameraDepth";
        private const string VolumetricFogRenderRTName = "_VolumetricFog";
        private const string VolumetricFogBlurRTName = "_VolumetricFogBlur";
        private const string VolumetricFogUpsampleCompositionRTName = "_VolumetricFogUpsampleComposition";

        public const RenderPassEvent DefaultRenderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public const VolumetricFogRenderPassEvent DefaultVolumetricFogRenderPassEvent = (VolumetricFogRenderPassEvent)DefaultRenderPassEvent;

        private ProfilingSampler downsampleDepthProfilingSampler;
        private Material downsampleDepthMaterial;
        private Material volumetricFogMaterial;

        private int downsampleDepthPassIndex;
        private int volumetricFogRenderPassIndex;
        private int volumetricFogHorizontalBlurPassIndex;
        private int volumetricFogVerticalBlurPassIndex;
        private int volumetricFogUpsampleCompositionPassIndex;

        private static readonly int DownsampledCameraDepthTextureId = Shader.PropertyToID("_DownsampledCameraDepthTexture");
        private static readonly int VolumetricFogTextureId = Shader.PropertyToID("_VolumetricFogTexture");
        private static readonly int FrameCountId = Shader.PropertyToID("_FrameCount");
        private static readonly int CustomAdditionalLightsCountId = Shader.PropertyToID("_CustomAdditionalLightsCount");
        private static readonly int DistanceId = Shader.PropertyToID("_Distance");
        private static readonly int BaseHeightId = Shader.PropertyToID("_BaseHeight");
        private static readonly int MaximumHeightId = Shader.PropertyToID("_MaximumHeight");
        private static readonly int GroundHeightId = Shader.PropertyToID("_GroundHeight");
        private static readonly int DensityId = Shader.PropertyToID("_Density");
        private static readonly int AbsortionId = Shader.PropertyToID("_Absortion");
        private static readonly int APVContributionWeigthId = Shader.PropertyToID("_APVContributionWeight");
        private static readonly int TintId = Shader.PropertyToID("_Tint");
        private static readonly int MaxStepsId = Shader.PropertyToID("_MaxSteps");

        private static readonly int AnisotropiesArrayId = Shader.PropertyToID("_Anisotropies");
        private static readonly int ScatteringsArrayId = Shader.PropertyToID("_Scatterings");
        private static readonly int RadiiSqArrayId = Shader.PropertyToID("_RadiiSq");

        private static readonly float[] Anisotropies = new float[UniversalRenderPipeline.maxVisibleAdditionalLights + 1];
        private static readonly float[] Scatterings = new float[UniversalRenderPipeline.maxVisibleAdditionalLights + 1];
        private static readonly float[] RadiiSq = new float[UniversalRenderPipeline.maxVisibleAdditionalLights];

        /// <summary>
        /// The subpasses the volumetric fog render pass is made of.
        /// </summary>
        private enum PassStage : byte
        {
            DownsampleDepth,
            VolumetricFogRender,
            VolumetricFogBlur,
            VolumetricFogUpsampleComposition
        }

        /// <summary>
        /// Holds the data needed by the execution of the volumetric fog render pass subpasses.
        /// </summary>
        private class PassData
        {
            public PassStage stage;

            public TextureHandle source;
            public TextureHandle target;

            public Material material;
            public int materialPassIndex;
            public int materialAdditionalPassIndex;

            public TextureHandle downsampledCameraDepthTarget;
            public TextureHandle volumetricFogRenderTarget;
            public UniversalLightData lightData;
        }

        public VolumetricFogRenderPass(Material downsampleDepthMaterial, Material volumetricFogMaterial, RenderPassEvent passEvent)
        {
            profilingSampler = new ProfilingSampler("Volumetric Fog");
            downsampleDepthProfilingSampler = new ProfilingSampler("Downsample Depth");
            renderPassEvent = passEvent;
#if UNITY_6000_0_OR_NEWER
            requiresIntermediateTexture = false;
#endif

            this.downsampleDepthMaterial = downsampleDepthMaterial;
            this.volumetricFogMaterial = volumetricFogMaterial;

            InitializePassesIndices();
        }

        /// <summary>
        /// Initializes the passes indices.
        /// </summary>
        private void InitializePassesIndices()
        {
            downsampleDepthPassIndex = downsampleDepthMaterial.FindPass("DownsampleDepth");
            volumetricFogRenderPassIndex = volumetricFogMaterial.FindPass("VolumetricFogRender");
            volumetricFogHorizontalBlurPassIndex = volumetricFogMaterial.FindPass("VolumetricFogHorizontalBlur");
            volumetricFogVerticalBlurPassIndex = volumetricFogMaterial.FindPass("VolumetricFogVerticalBlur");
            volumetricFogUpsampleCompositionPassIndex = volumetricFogMaterial.FindPass("VolumetricFogUpsampleComposition");
        }

        /// <summary>
        /// <inheritdoc/>
        /// </summary>
        /// <param name="renderGraph"></param>
        /// <param name="frameData"></param>
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalLightData lightData = frameData.Get<UniversalLightData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            CreateRenderGraphTextures(renderGraph,
                cameraData,
                out TextureHandle downsampledCameraDepthTarget,
                out TextureHandle volumetricFogRenderTarget,
                out TextureHandle volumetricFogBlurRenderTarget,
                out TextureHandle volumetricFogUpsampleCompositionTarget);

            using (IRasterRenderGraphBuilder builder =
                   renderGraph.AddRasterRenderPass("Downsample Depth Pass", out PassData passData, downsampleDepthProfilingSampler))
            {
                passData.stage = PassStage.DownsampleDepth;
                passData.source = resourceData.cameraDepthTexture;
                passData.target = downsampledCameraDepthTarget;
                passData.material = downsampleDepthMaterial;
                passData.materialPassIndex = downsampleDepthPassIndex;

                builder.SetRenderAttachment(downsampledCameraDepthTarget, 0, AccessFlags.WriteAll);
                builder.UseTexture(resourceData.cameraDepthTexture);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) => ExecutePass(data, context));
            }

            using (IRasterRenderGraphBuilder builder =
                   renderGraph.AddRasterRenderPass("Volumetric Fog Render Pass", out PassData passData, profilingSampler))
            {
                passData.stage = PassStage.VolumetricFogRender;
                passData.source = downsampledCameraDepthTarget;
                passData.target = volumetricFogRenderTarget;
                passData.material = volumetricFogMaterial;
                passData.materialPassIndex = volumetricFogRenderPassIndex;
                passData.downsampledCameraDepthTarget = downsampledCameraDepthTarget;
                passData.lightData = lightData;

                builder.SetRenderAttachment(volumetricFogRenderTarget, 0, AccessFlags.WriteAll);
                builder.UseTexture(downsampledCameraDepthTarget);
                if (resourceData.mainShadowsTexture.IsValid())
                    builder.UseTexture(resourceData.mainShadowsTexture);
                if (resourceData.additionalShadowsTexture.IsValid())
                    builder.UseTexture(resourceData.additionalShadowsTexture);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) => ExecutePass(data, context));
            }

            using (IUnsafeRenderGraphBuilder builder = renderGraph.AddUnsafePass("Volumetric Fog Blur Pass", out PassData passData, profilingSampler))
            {
                passData.stage = PassStage.VolumetricFogBlur;
                passData.source = volumetricFogRenderTarget;
                passData.target = volumetricFogBlurRenderTarget;
                passData.material = volumetricFogMaterial;
                passData.materialPassIndex = volumetricFogHorizontalBlurPassIndex;
                passData.materialAdditionalPassIndex = volumetricFogVerticalBlurPassIndex;

                builder.UseTexture(volumetricFogRenderTarget, AccessFlags.ReadWrite);
                builder.UseTexture(volumetricFogBlurRenderTarget, AccessFlags.ReadWrite);
                builder.SetRenderFunc((PassData data, UnsafeGraphContext context) => ExecuteUnsafeBlurPass(data, context));
            }

            using (IRasterRenderGraphBuilder builder =
                   renderGraph.AddRasterRenderPass("Volumetric Fog Upsample Composition Pass", out PassData passData, profilingSampler))
            {
                passData.stage = PassStage.VolumetricFogUpsampleComposition;
                passData.source = resourceData.cameraColor;
                passData.target = volumetricFogUpsampleCompositionTarget;
                passData.material = volumetricFogMaterial;
                passData.materialPassIndex = volumetricFogUpsampleCompositionPassIndex;
                passData.volumetricFogRenderTarget = volumetricFogRenderTarget;

                builder.SetRenderAttachment(volumetricFogUpsampleCompositionTarget, 0, AccessFlags.WriteAll);
                builder.UseTexture(resourceData.cameraDepthTexture);
                builder.UseTexture(downsampledCameraDepthTarget);
                builder.UseTexture(volumetricFogRenderTarget);
                builder.UseTexture(resourceData.cameraColor);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) => ExecutePass(data, context));
            }

            resourceData.cameraColor = volumetricFogUpsampleCompositionTarget;
        }

        private void CreateRenderGraphTextures(RenderGraph renderGraph,
            UniversalCameraData cameraData,
            out TextureHandle downsampledCameraDepthTarget,
            out TextureHandle volumetricFogRenderTarget,
            out TextureHandle volumetricFogBlurRenderTarget,
            out TextureHandle volumetricFogUpsampleCompositionTarget)
        {
            // RenderTextureを作成するための情報
            RenderTextureDescriptor cameraTargetDescriptor = cameraData.cameraTargetDescriptor;
            cameraTargetDescriptor.depthBufferBits = (int)DepthBits.None;

            RenderTextureFormat originalColorFormat = cameraTargetDescriptor.colorFormat;
            Vector2Int originalResolution = new Vector2Int(cameraTargetDescriptor.width, cameraTargetDescriptor.height);

            // 半分のサイズで深度バッファRenderTextureを作成
            cameraTargetDescriptor.width /= DownsampleFactor;
            cameraTargetDescriptor.height /= DownsampleFactor;
            cameraTargetDescriptor.graphicsFormat = GraphicsFormat.R32_SFloat; // 32bitRチャンネル 符号付き
            downsampledCameraDepthTarget =
                UniversalRenderer.CreateRenderGraphTexture(renderGraph, cameraTargetDescriptor, DownsampledCameraDepthRTName, false);

            // 半分のサイズでボリューメトリックフォグ用のRenderTextureを作成
            cameraTargetDescriptor.colorFormat = RenderTextureFormat.ARGBHalf; // 16bitRGBAチャンネル 符号なし
            volumetricFogRenderTarget =
                UniversalRenderer.CreateRenderGraphTexture(renderGraph, cameraTargetDescriptor, VolumetricFogRenderRTName, false);
            volumetricFogBlurRenderTarget =
                UniversalRenderer.CreateRenderGraphTexture(renderGraph, cameraTargetDescriptor, VolumetricFogBlurRTName, false);


            // 元のサイズのRenderTextureを作成
            cameraTargetDescriptor.width = originalResolution.x;
            cameraTargetDescriptor.height = originalResolution.y;
            cameraTargetDescriptor.colorFormat = originalColorFormat;
            volumetricFogUpsampleCompositionTarget =
                UniversalRenderer.CreateRenderGraphTexture(renderGraph, cameraTargetDescriptor, VolumetricFogUpsampleCompositionRTName, false);
        }


        /// <summary>
        /// Executes the pass with the information from the pass data.
        /// </summary>
        /// <param name="passData"></param>
        /// <param name="context"></param>
        private static void ExecutePass(PassData passData, RasterGraphContext context)
        {
            PassStage stage = passData.stage;

            if (stage == PassStage.VolumetricFogRender)
            {
                passData.material.SetTexture(DownsampledCameraDepthTextureId, passData.downsampledCameraDepthTarget);
                UpdateVolumetricFogMaterialParameters(passData.material, passData.lightData.mainLightIndex, passData.lightData.additionalLightsCount,
                    passData.lightData.visibleLights);
            }
            else if (stage == PassStage.VolumetricFogUpsampleComposition)
            {
                passData.material.SetTexture(VolumetricFogTextureId, passData.volumetricFogRenderTarget);
            }

            Blitter.BlitTexture(context.cmd, passData.source, Vector2.one, passData.material, passData.materialPassIndex);
        }


        private static void ExecuteUnsafeBlurPass(PassData passData, UnsafeGraphContext context)
        {
            CommandBuffer unsafeCmd = CommandBufferHelpers.GetNativeCommandBuffer(context.cmd);

            int blurIterations = VolumeManager.instance.stack.GetComponent<VolumetricFogVolumeComponent>().blurIterations.value;

            for (int i = 0; i < blurIterations; ++i)
            {
                Blitter.BlitCameraTexture(unsafeCmd, passData.source, passData.target, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    passData.material, passData.materialPassIndex);
                Blitter.BlitCameraTexture(unsafeCmd, passData.target, passData.source, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store,
                    passData.material, passData.materialAdditionalPassIndex);
            }
        }

        private static void UpdateVolumetricFogMaterialParameters(Material volumetricFogMaterial, int mainLightIndex, int additionalLightsCount,
            NativeArray<VisibleLight> visibleLights)
        {
            VolumetricFogVolumeComponent fogVolume = VolumeManager.instance.stack.GetComponent<VolumetricFogVolumeComponent>();

            bool enableMainLightContribution =
                fogVolume.enableMainLightContribution.value && fogVolume.scattering.value > 0.0f && mainLightIndex > -1;
            bool enableAdditionalLightsContribution = fogVolume.enableAdditionalLightsContribution.value && additionalLightsCount > 0;

#if UNITY_2023_1_OR_NEWER
            bool enableAPVContribution = fogVolume.enableAPVContribution.value && fogVolume.APVContributionWeight.value > 0.0f;
            if (enableAPVContribution)
                volumetricFogMaterial.EnableKeyword("_APV_CONTRIBUTION_ENABLED");
            else
                volumetricFogMaterial.DisableKeyword("_APV_CONTRIBUTION_ENABLED");
#endif

            if (enableMainLightContribution)
                volumetricFogMaterial.DisableKeyword("_MAIN_LIGHT_CONTRIBUTION_DISABLED");
            else
                volumetricFogMaterial.EnableKeyword("_MAIN_LIGHT_CONTRIBUTION_DISABLED");

            if (enableAdditionalLightsContribution)
                volumetricFogMaterial.DisableKeyword("_ADDITIONAL_LIGHTS_CONTRIBUTION_DISABLED");
            else
                volumetricFogMaterial.EnableKeyword("_ADDITIONAL_LIGHTS_CONTRIBUTION_DISABLED");

            UpdateLightsParameters(volumetricFogMaterial, fogVolume, enableMainLightContribution, enableAdditionalLightsContribution, mainLightIndex,
                visibleLights);

            volumetricFogMaterial.SetInteger(FrameCountId, Time.renderedFrameCount % 64);
            volumetricFogMaterial.SetInteger(CustomAdditionalLightsCountId, additionalLightsCount);
            volumetricFogMaterial.SetFloat(DistanceId, fogVolume.distance.value);
            volumetricFogMaterial.SetFloat(BaseHeightId, fogVolume.baseHeight.value);
            volumetricFogMaterial.SetFloat(MaximumHeightId, fogVolume.maximumHeight.value);
            volumetricFogMaterial.SetFloat(GroundHeightId,
                (fogVolume.enableGround.overrideState && fogVolume.enableGround.value) ? fogVolume.groundHeight.value : float.MinValue);
            volumetricFogMaterial.SetFloat(DensityId, fogVolume.density.value);
            volumetricFogMaterial.SetFloat(AbsortionId, 1.0f / fogVolume.attenuationDistance.value);
#if UNITY_2023_1_OR_NEWER
            volumetricFogMaterial.SetFloat(APVContributionWeigthId,
                fogVolume.enableAPVContribution.value ? fogVolume.APVContributionWeight.value : 0.0f);
#endif
            volumetricFogMaterial.SetColor(TintId, fogVolume.tint.value);
            volumetricFogMaterial.SetInteger(MaxStepsId, fogVolume.maxSteps.value);
        }


        private static void UpdateLightsParameters(Material volumetricFogMaterial, VolumetricFogVolumeComponent fogVolume,
            bool enableMainLightContribution, bool enableAdditionalLightsContribution, int mainLightIndex, NativeArray<VisibleLight> visibleLights)
        {
            if (enableMainLightContribution)
            {
                Anisotropies[visibleLights.Length - 1] = fogVolume.anisotropy.value;
                Scatterings[visibleLights.Length - 1] = fogVolume.scattering.value;
            }

            if (enableAdditionalLightsContribution)
            {
                int additionalLightIndex = 0;

                for (int i = 0; i < visibleLights.Length; ++i)
                {
                    if (i == mainLightIndex)
                        continue;

                    float anisotropy = 0.0f;
                    float scattering = 0.0f;
                    float radius = 0.0f;

                    if (visibleLights[i].light.TryGetComponent(out VolumetricAdditionalLight volumetricLight))
                    {
                        if (volumetricLight.gameObject.activeInHierarchy && volumetricLight.enabled)
                        {
                            anisotropy = volumetricLight.Anisotropy;
                            scattering = volumetricLight.Scattering;
                            radius = volumetricLight.Radius;
                        }
                    }

                    Anisotropies[additionalLightIndex] = anisotropy;
                    Scatterings[additionalLightIndex] = scattering;
                    RadiiSq[additionalLightIndex++] = radius * radius;
                }
            }

            if (enableMainLightContribution || enableAdditionalLightsContribution)
            {
                volumetricFogMaterial.SetFloatArray(AnisotropiesArrayId, Anisotropies);
                volumetricFogMaterial.SetFloatArray(ScatteringsArrayId, Scatterings);
                volumetricFogMaterial.SetFloatArray(RadiiSqArrayId, RadiiSq);
            }
        }
    }
}