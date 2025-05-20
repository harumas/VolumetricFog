using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace PostProcessing
{
    [System.Serializable]
    public class ScreenSpaceReflectionRenderer : ScriptableRendererFeature
    {
        [SerializeField] private Shader screenSpaceReflectionShader;

        private ScreenSpaceReflectionPass screenSpaceReflectionPass;

        public override void Create()
        {
            screenSpaceReflectionPass = new ScreenSpaceReflectionPass(screenSpaceReflectionShader);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(screenSpaceReflectionPass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            screenSpaceReflectionPass.SetRTHandle(renderer.cameraColorTargetHandle);
        }
    }
}