using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

namespace PostProcessing
{
    [System.Serializable]
    public class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        private readonly int intensityId = Shader.PropertyToID("_Intensity");
        private const string ScreenSpaceReflectionRTName = "_ScreenSpaceReflection";

        private RTHandle rtHandle;
        private Material effectMaterial;
        private ProfilingSampler ssrProfilingSampler;

        private class PassData
        {
            public float parameter;
            public TextureHandle inputTexture;
            public TextureHandle outputTexture;
            public RTHandle source;
            public Material material;
            public int materialPassIndex;
        }

        public ScreenSpaceReflectionPass(Shader shader)
        {
            effectMaterial = CoreUtils.CreateEngineMaterial(shader);
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        public void SetRTHandle(RTHandle rtHandle)
        {
            this.rtHandle = rtHandle;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            UniversalLightData lightData = frameData.Get<UniversalLightData>();
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            RenderTextureDescriptor cameraTargetDescriptor = cameraData.cameraTargetDescriptor;

            cameraTargetDescriptor.graphicsFormat = GraphicsFormat.R32G32B32A32_SFloat; // 32bitRGBAチャンネル 符号付き
            TextureHandle cameraTextureTarget = UniversalRenderer.CreateRenderGraphTexture(renderGraph,
                cameraTargetDescriptor,
                ScreenSpaceReflectionRTName,
                false,
                FilterMode.Bilinear);

            using (IRasterRenderGraphBuilder builder =
                   renderGraph.AddRasterRenderPass("Screen Space Reflection Pass", out PassData passData, ssrProfilingSampler))
            {
                passData.inputTexture = resourceData.cameraOpaqueTexture;
                passData.material = effectMaterial;

                builder.SetRenderAttachment(cameraTextureTarget, 0, AccessFlags.WriteAll);
                builder.UseTexture(resourceData.cameraDepthTexture);
                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitCameraTexture(context.cmd, data.source,data.source, data.material, 0);
                });
            }
        }

        // The actual execution of the pass. This is where custom rendering occurs.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // カスタムエフェクトを取得
            VolumeStack stack = VolumeManager.instance.stack;
            var customEffect = stack.GetComponent<ScreenSpaceReflection>();

            // 無効だったらポストプロセスかけない
            if (!customEffect.IsActive())
                return;

            // CommandBufferを取得
            CommandBuffer cmd = CommandBufferPool.Get("ScreenSpaceReflection");

            using (new ProfilingScope(cmd, profilingSampler))
            {
                effectMaterial.SetFloat(intensityId, customEffect.intensity.value);
                effectMaterial.SetVector("_BlitScaleBias", new Vector4(1, 1, 0, 0));

                Blitter.BlitCameraTexture(cmd, rtHandle, rtHandle, effectMaterial, 0);
            }

            context.ExecuteCommandBuffer(cmd);

            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }
    }
}