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

            float _SamplingRotations[6];
            float _SamplingDistances[6];
            float _Blend;
            float _OcclusionSampleLength;
            float _OcclusionMinDistance;
            float _OcclusionMaxDistance;
            float _OcclusionBias;
            float _OcclusionStrength;
            float _OcclusionPower;
            float4 _OcclusionColor;


            float SampleRawDepth(float2 uv)
            {
                float rawDepth = SAMPLE_DEPTH_TEXTURE_LOD(
                    _CameraDepthTexture,
                    sampler_CameraDepthTexture,
                    UnityStereoTransformScreenSpaceTex(uv),
                    0
                );
                return rawDepth;
            }

            float2x2 GetRotationMatrix(float rad)
            {
                float c = cos(rad);
                float s = sin(rad);
                return float2x2(c, -s, s, c);
            }

            float SampleRawDepthByViewPosition(float3 viewPosition, float3 offset)
            {
                float4 offsetViewPosition = float4(viewPosition + offset, 1.0);
                float4 offsetClipPosition = mul(UNITY_MATRIX_P, offsetViewPosition);

                #if UNITY_UV_STARTS_AT_TOP
                offsetClipPosition.y = -offsetClipPosition.y;
                #endif

                // スクリーン座標に変換
                float2 samplingCoord = (offsetClipPosition.xy / offsetClipPosition.w) * 0.5 + 0.5;
                float samplingRawDepth = SampleRawDepth(samplingCoord);

                return samplingRawDepth;
            }


            float4 FragSSAO(Varyings input) : SV_Target
            {
                // 深度値を取得
                float d = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, input.texcoord).r;

                // ワールド座標を復元
                float3 worldPos = ComputeWorldSpacePosition(input.texcoord, d, UNITY_MATRIX_I_VP);

                // return float4(worldPos, 1.0);
                
                // ビュー座標に変換
                float3 viewPosition = mul(UNITY_MATRIX_V, float4(worldPos, 1.0)).xyz;

                viewPosition.z = -viewPosition.z;

                float4 color = float4(1, 1, 1, 1);

                float rawDepth = SampleRawDepth(input.texcoord);
                float depth = Linear01Depth(rawDepth, _ZBufferParams);

                // デバッグ用
                // return float4(depth, depth, depth, 1);
                // return float4(rawDepth, rawDepth, rawDepth, 1.0);


                const float epsilon = 0.0001;

                if (depth > 1.0 - epsilon)
                {
                    return color;
                }

                float occludedAcc = 0;
                const int samplingCount = 6;

                for (int i = 0; i < samplingCount; i++)
                {
                    // サンプリング角度の回転行列を取得
                    float2x2 rotationMatrix = GetRotationMatrix(_SamplingRotations[i]);

                    float offsetLength = _SamplingDistances[i] * _OcclusionSampleLength;
                    float3 offsetA = float3(mul(rotationMatrix, float2(1, 0)), 0) * offsetLength;
                    float3 offsetB = -offsetA;

                    float rawDepthA = SampleRawDepthByViewPosition(viewPosition, offsetA);
                    float rawDepthB = SampleRawDepthByViewPosition(viewPosition, offsetB);


                    float depthA = Linear01Depth(rawDepthA, _ZBufferParams);
                    float depthB = Linear01Depth(rawDepthB, _ZBufferParams);
                    
                    float3 viewPositionA = ComputeViewSpacePosition(input.texcoord, depthA, UNITY_MATRIX_I_P);
                    float3 viewPositionB = ComputeViewSpacePosition(input.texcoord, depthB, UNITY_MATRIX_I_P);
                    
                    float distA = distance(viewPositionA, viewPosition);
                    float distB = distance(viewPositionB, viewPosition);
                    
                    if (abs(depth - depthA) < _OcclusionBias)
                    {
                        continue;
                    }
                    if (abs(depth - depthB) < _OcclusionBias)
                    {
                        continue;
                    }
                    
                    if (distA < _OcclusionMinDistance || _OcclusionMaxDistance < distA)
                    {
                        continue;
                    }
                    if (distB < _OcclusionMinDistance || _OcclusionMaxDistance < distB)
                    {
                        continue;
                    }
                    
                    // pattern_2: compare with surface to camera
                    float3 surfaceToCameraDir = -normalize(viewPosition);
                    float dotA = dot(normalize(viewPositionA - viewPosition), surfaceToCameraDir);
                    float dotB = dot(normalize(viewPositionB - viewPosition), surfaceToCameraDir);
                    float ao = (dotA + dotB) * 0.5;
                    
                    occludedAcc += ao;
                }

                float aoRate = occludedAcc / (float)samplingCount;

                float ao = saturate(pow(saturate(aoRate), _OcclusionPower) * _OcclusionStrength);

                ao = 1 - ao;

                return float4(ao, ao, ao, 1.0);
            }
            ENDHLSL
        }

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