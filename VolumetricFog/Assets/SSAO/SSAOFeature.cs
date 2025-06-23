using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

[System.Serializable]
public class SSAOSettings
{
    [Range(0f, 4f)]
    public float Intensity = 1.0f;
    [Range(0.01f, 1f)]
    public float Radius = 0.5f;
    [Range(4, 64)]
    public int SampleCount = 16;
}

public class SSAOFeature : ScriptableRendererFeature
{
    public SSAOSettings settings = new SSAOSettings();
    public Shader ssaoShader;

    private Material m_Material;

    public override void Create()
    {
        if (ssaoShader == null)
        {
            Debug.LogError("SSAO Shader is not assigned!");
            return;
        }
        m_Material = CoreUtils.CreateEngineMaterial(ssaoShader);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var cameraType = renderingData.cameraData.cameraType;
        // ゲームカメラ と シーンビューカメラ の両方で実行するようにする
        if (cameraType != CameraType.Game && cameraType != CameraType.SceneView)
        {
            return;
        }
        
        renderer.EnqueuePass(new SSAOPass(m_Material, settings));
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }

    private class SSAOPass : ScriptableRenderPass
    {
        private Material m_Material;
        private SSAOSettings m_Settings;

        private class PassData
        {
            public Material material;
            public SSAOSettings settings;
        }
        
        private class BlitPassData
        {
             public Material material;
             public TextureHandle ssaoTexture;
        }

        public SSAOPass(Material material, SSAOSettings settings)
        {
            this.m_Material = material;
            this.m_Settings = settings;
            this.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // カメラ情報を取得
            var cameraData = frameData.Get<UniversalCameraData>();
            
            // レンダリングののリソース情報を取得
            var resourceData = frameData.Get<UniversalResourceData>();

            // 描画先の情報を取得
            var descriptor = cameraData.cameraTargetDescriptor;
            descriptor.depthBufferBits = 0;
            descriptor.colorFormat = RenderTextureFormat.ARGB32;

            // 一時テクスチャを作成する
            TextureHandle ssaoTexture = UniversalRenderer.CreateRenderGraphTexture(renderGraph, descriptor, "SSAO_Texture", true);
            
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("SSAO Pass", out var passData))
            {
                passData.material = m_Material;
                passData.settings = m_Settings;

                builder.UseTexture(resourceData.cameraDepthTexture, AccessFlags.Read);
                builder.UseTexture(resourceData.cameraNormalsTexture, AccessFlags.Read);
                builder.SetRenderAttachment(ssaoTexture, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    data.material.SetFloat("_Intensity", data.settings.Intensity);
                    data.material.SetFloat("_Radius", data.settings.Radius);
                    data.material.SetInteger("_SampleCount", data.settings.SampleCount);

                    // 白のテクスチャにSSAOを書き込む
                    Blitter.BlitTexture(context.cmd, Texture2D.whiteTexture, Vector2.one, data.material, 0);
                });
            }
            
            using (var builder = renderGraph.AddRasterRenderPass<BlitPassData>("SSAO Composite Pass", out var passData))
            {
                passData.material = m_Material;
                passData.ssaoTexture = ssaoTexture;

                builder.UseTexture(passData.ssaoTexture, AccessFlags.Read);
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0, AccessFlags.Write);

                builder.SetRenderFunc((BlitPassData data, RasterGraphContext context) =>
                {
                    // カメラにSSAOテクスチャを書き込む
                    Blitter.BlitTexture(context.cmd, data.ssaoTexture, Vector2.one, data.material, 1);
                });
            }
        }
    }
}