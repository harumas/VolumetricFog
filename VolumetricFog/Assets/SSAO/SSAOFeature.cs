using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class SSAOFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class SSAOSettings
    {
        [Range(0f, 1f)] public float Blend = 0.5f;
        [Range(0.01f, 5f)] public float OcclusionSampleLength = 1f;
        [Range(0f, 5f)] public float OcclusionMinDistance = 0f;
        [Range(0f, 50f)] public float OcclusionMaxDistance = 5f;
        [Range(0f, 1f)] public float OcclusionBias = 0.001f;
        [Range(0f, 4f)] public float OcclusionStrength = 1f;
        [Range(0.1f, 4f)] public float OcclusionPower = 1f;
        public Color OcclusionColor = Color.black;
        public float[] SamplingRotations = new float[6];
        public float[] SamplingDistances = new float[6];
        public Shader ssaoShader;
    }

    public SSAOSettings settings = new SSAOSettings();

    private Material m_Material;
    private SSAOPass m_Pass;

    public override void Create()
    {
        if (settings.ssaoShader != null)
            m_Material = CoreUtils.CreateEngineMaterial(settings.ssaoShader);
        else
            Debug.LogWarning("SSAO shader not assigned in SSAOFeature.");
        m_Pass = new SSAOPass(m_Material, settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_Pass != null)
            renderer.EnqueuePass(m_Pass);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }

    // ------------------------------------------------------------
    // ScriptableRenderPass implementing RenderGraph usage
    // ------------------------------------------------------------
    private class SSAOPass : ScriptableRenderPass
    {
        private readonly Material material;
        private readonly SSAOSettings settings;

        // shader property IDs
        private static readonly int BlendID = Shader.PropertyToID("_Blend");
        private static readonly int OcclusionColorID = Shader.PropertyToID("_OcclusionColor");
        private static readonly int OcclusionSampleLengthID = Shader.PropertyToID("_OcclusionSampleLength");
        private static readonly int OcclusionMinDistanceID = Shader.PropertyToID("_OcclusionMinDistance");
        private static readonly int OcclusionMaxDistanceID = Shader.PropertyToID("_OcclusionMaxDistance");
        private static readonly int OcclusionBiasID = Shader.PropertyToID("_OcclusionBias");
        private static readonly int OcclusionStrengthID = Shader.PropertyToID("_OcclusionStrength");
        private static readonly int OcclusionPowerID = Shader.PropertyToID("_OcclusionPower");
        private static readonly int SamplingRotationsID = Shader.PropertyToID("_SamplingRotations");
        private static readonly int SamplingDistancesID = Shader.PropertyToID("_SamplingDistances");

        public SSAOPass(Material mat, SSAOSettings settings)
        {
            this.material = mat;
            this.settings = settings;
            this.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        private class PassData
        {
            public Material material;
            public TextureHandle color; // カメラのカラーデータ
            public TextureHandle depth; // depth handle (読み取り)
            public TextureHandle dst; // 書き込み先 (temp)
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // フレームデータを取得
            var cameraData = frameData.Get<UniversalCameraData>();
            var resourceData = frameData.Get<UniversalResourceData>();

            // マテリアルがnullだったら終了
            if (material == null)
                return;

            var desc = cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.colorFormat = RenderTextureFormat.ARGB32;

            // SSAOを書き込むための一時テクスチャを作成
            TextureHandle tempColor = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "SSAO_TempColor", false);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("SSAO: Compute", out var passData))
            {
                passData.material = material;
                passData.depth = resourceData.cameraDepthTexture; // 深度テクスチャを取得
                passData.dst = tempColor; // 書き込み先を登録

                builder.UseTexture(passData.depth, AccessFlags.Read);

                // 描画先を登録
                builder.SetRenderAttachment(passData.dst, 0);

                builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
                {
                    // パラメータを設定
                    data.material.SetFloat(BlendID, settings.Blend);
                    data.material.SetColor(OcclusionColorID, settings.OcclusionColor);
                    data.material.SetFloat(OcclusionSampleLengthID, settings.OcclusionSampleLength);
                    data.material.SetFloat(OcclusionMinDistanceID, settings.OcclusionMinDistance);
                    data.material.SetFloat(OcclusionMaxDistanceID, settings.OcclusionMaxDistance);
                    data.material.SetFloat(OcclusionBiasID, settings.OcclusionBias);
                    data.material.SetFloat(OcclusionStrengthID, settings.OcclusionStrength);
                    data.material.SetFloat(OcclusionPowerID, settings.OcclusionPower);
                    data.material.SetFloatArray(SamplingRotationsID, settings.SamplingRotations);
                    data.material.SetFloatArray(SamplingDistancesID, settings.SamplingDistances);

                    // 描画
                    Blitter.BlitTexture(ctx.cmd, Texture2D.whiteTexture, new Vector4(1, 1, 0, 0), data.material, 0);
                });
            }

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("SSAO: Commit to Camera", out var passData2))
            {
                passData2.dst = resourceData.activeColorTexture;
                
                builder.UseTexture(tempColor, AccessFlags.Read);
                builder.SetRenderAttachment(passData2.dst, 0);

                builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
                {
                    Blitter.BlitTexture(ctx.cmd, data.dst, new Vector4(1, 1, 0, 0), material, 1);
                });
            }
        }
    }
}