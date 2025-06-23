// SSAO.shader (戻り値の型を修正した、最終版！)
Shader "Hidden/SSAO"
{
    Properties {}
    SubShader
    {
        // SSAO Pass
        Pass
        {
            Name "SSAO"
            ZTest Always Cull Off ZWrite Off

            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            #pragma vertex Vert
            #pragma fragment FragSSAO
            
            float _Intensity;
            float _Radius;
            int _SampleCount;

            // 【変更点】FragSSAOの戻り値を float から float4 に変更！
            float4 FragSSAO(Varyings input) : SV_Target
            {
                float depth = SampleSceneDepth(input.texcoord);
                float3 normalVS = SampleSceneNormals(input.texcoord);
                float3 positionVS = ComputeViewSpacePosition(input.texcoord, depth, UNITY_MATRIX_I_P);
                
                float occlusion = 0.0;
                
                // サンプリングのロジックはひとまずそのままでOK
                for(int i = 0; i < _SampleCount; ++i)
                {
                    float3 sampleDir = float3(sin(i * 1.57), cos(i * 1.57), 0.5) * _Radius; 
                    float3 samplePosVS = positionVS + sampleDir;
                    float4 samplePosCS = mul(UNITY_MATRIX_P, float4(samplePosVS, 1.0));
                    samplePosCS.xyz /= samplePosCS.w;
                    float2 sampleUV = samplePosCS.xy * 0.5 + 0.5;
                    float sampleDepth = SampleSceneDepth(sampleUV);
                    float3 sampleSurfaceVS = ComputeViewSpacePosition(sampleUV, sampleDepth, UNITY_MATRIX_I_P);
                    float rangeCheck = smoothstep(0.0, 1.0, _Radius / abs(positionVS.z - sampleSurfaceVS.z));
                    if (sampleSurfaceVS.z >= samplePosVS.z)
                    {
                        occlusion += 1.0 * rangeCheck;
                    }
                }
                occlusion /= _SampleCount;

                float ao = 1.0 - saturate(occlusion * _Intensity);

                // 【変更点】float4(R,G,B,A) の形で返す！
                // AOは白黒の値なので、R,G,Bに同じ値を入れてグレースケールにするのがお作法。
                return float4(ao, ao, ao, 1.0);
            }
            ENDHLSL
        }

        // Composite Pass は変更なし
        Pass
        {
            Name "Composite"
            ZTest Always Cull Off ZWrite Off
            Blend DstColor Zero

            HLSLPROGRAM

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            #pragma vertex Vert
            #pragma fragment FragComposite
            
            float4 FragComposite(Varyings input) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, input.texcoord);
            }
            ENDHLSL
        }
    }
}