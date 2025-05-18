using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Harumaron
{
    [DisallowMultipleRendererFeature("Volumetric Fog")]
    public sealed class VolumetricFogRendererFeature : ScriptableRendererFeature
    {
        [HideInInspector]
        [SerializeField] private Shader downsampleShader;

        [HideInInspector]
        [SerializeField] private Shader volumetricFogShader;

        private Material downsampleMaterial;
        private Material volumetricFogMaterial;

        private VolumetricFogRenderPass renderPass;

        public override void Create()
        {
            // マテリアルを作成
            if (!TryCreateMaterials())
            {
                throw new System.Exception("Failed to create materials for volumetric fog render pass.");
            }

            renderPass = new VolumetricFogRenderPass(downsampleMaterial, volumetricFogMaterial, VolumetricFogRenderPass.DefaultRenderPassEvent);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            bool isPostProcessEnabled = renderingData.postProcessingEnabled && renderingData.cameraData.postProcessEnabled;
            bool shouldAddVolumetricFogRenderPass = ShouldAddVolumetricFogRenderPass(renderingData.cameraData.cameraType);

            if (isPostProcessEnabled && shouldAddVolumetricFogRenderPass)
            {
                renderPass.renderPassEvent = GetRenderPassEvent();
                renderPass.ConfigureInput(ScriptableRenderPassInput.Depth);
                renderer.EnqueuePass(renderPass);
            }
        }

        protected override void Dispose(bool disposing)
        {
            base.Dispose(disposing);

            CoreUtils.Destroy(downsampleMaterial);
            CoreUtils.Destroy(volumetricFogMaterial);
        }

        private bool TryCreateMaterials()
        {
#if UNITY_EDITOR
            downsampleShader = Shader.Find("Hidden/DownsampleDepth");
            volumetricFogShader = Shader.Find("Hidden/VolumetricFog");
#endif
            CoreUtils.Destroy(downsampleMaterial);
            downsampleMaterial = CoreUtils.CreateEngineMaterial(downsampleShader);

            CoreUtils.Destroy(volumetricFogMaterial);
            volumetricFogMaterial = CoreUtils.CreateEngineMaterial(volumetricFogShader);


            bool isDownsampleFound = downsampleShader != null && downsampleMaterial != null;
            bool isVolumetricFogFound = volumetricFogShader != null && volumetricFogMaterial != null;
            
            return isDownsampleFound && isVolumetricFogFound;
        }

        private bool ShouldAddVolumetricFogRenderPass(CameraType cameraType)
        {
            VolumetricFogVolumeComponent fogVolume = VolumeManager.instance.stack.GetComponent<VolumetricFogVolumeComponent>();

            bool isVolumeOk = fogVolume != null && fogVolume.IsActive();
            bool isCameraOk = cameraType != CameraType.Preview && cameraType != CameraType.Reflection;

            return isActive && isVolumeOk && isCameraOk;
        }

        private RenderPassEvent GetRenderPassEvent()
        {
            VolumetricFogVolumeComponent fogVolume = VolumeManager.instance.stack.GetComponent<VolumetricFogVolumeComponent>();

            return (RenderPassEvent)fogVolume.renderPassEvent.value;
        }
    }
}