Shader "Hidden/DownsampleDepth"
{
    // より高機能なGPUむけ
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "DownsampleDepth"

            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            // 深度のみの計算なのでRチャンネル
            ColorMask R

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma target 4.5

            // 同期コンパイルの強制
            #pragma editor_sync_compilation

            #pragma vertex Vert
            #pragma fragment Frag

            float Frag(Varyings input) : SV_Target
            {
                // ステレオレンダリングのサポート
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // 隣接する4ピクセルの深度を取得
                float4 depths = GATHER_RED_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord);

                // 4ピクセルの深度から最小値と最大値を選択
                float minDepth = Min3(depths.x, depths.y, min(depths.z, depths.w));
                float maxDepth = Max3(depths.x, depths.y, max(depths.z, depths.w));

                // ピクセルの位置の偶奇に基づいて最小値または最大値を選択
                // チェッカーボードパターン
                return (uint(input.positionCS.x + input.positionCS.y) & 1) > 0 ? minDepth : maxDepth;
            }
            ENDHLSL
        }
    }

    Fallback Off
}