Shader "Hidden/Custom/SSAOAngleBased"
{
    Properties {}

    SubShader
    {
        Pass
        {
            Name "SSAO"
            ZTest Always Cull Off ZWrite Off

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            #pragma vertex Vert
            #pragma fragment Frag

            float _Blend;
            float _SamplingRotations[6];
            float _SamplingDistances[6];
            float _OcclusionSampleLength;
            float _OcclusionMinDistance;
            float _OcclusionMaxDistance;
            float _OcclusionBias;
            float _OcclusionStrength;
            float _OcclusionPower;
            float4 _OcclusionColor;

            // ------------------------------------------------------------------------------------------------
            // ref: UnityCG.cginc
            // ------------------------------------------------------------------------------------------------

            float DecodeFloatRG(float2 enc)
            {
                float2 kDecodeDot = float2(1.0, 1 / 255.0);
                return dot(enc, kDecodeDot);
            }


            float3 DecodeViewNormalStereo(float4 enc4)
            {
                float kScale = 1.7777;
                float3 nn = enc4.xyz * float3(2 * kScale, 2 * kScale, 0) + float3(-kScale, -kScale, 1);
                float g = 2.0 / dot(nn.xyz, nn.xyz);
                float3 n;
                n.xy = g * nn.xy;
                n.z = g - 1;
                return n;
            }

            void DecodeDepthNormal(float4 enc, out float depth, out float3 normal)
            {
                depth = DecodeFloatRG(enc.zw);
                normal = DecodeViewNormalStereo(enc);
            }

            // ------------------------------------------------------------------------------------------------


            float3 ReconstructWorldPositionFromDepth(float2 screenUV, float rawDepth)
            {
                // TODO: depthはgraphicsAPIを考慮している必要があるはず
                float4 clipPos = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                clipPos.y = -clipPos.y;
                #endif
                float4 worldPos = mul(UNITY_MATRIX_I_VP, clipPos);
                return worldPos.xyz / worldPos.w;
            }

            float3 ReconstructViewPositionFromDepth(float2 screenUV, float rawDepth)
            {
                // TODO: depthはgraphicsAPIを考慮している必要があるはず
                float4 clipPos = float4(screenUV * 2.0 - 1.0, rawDepth, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                clipPos.y = -clipPos.y;
                #endif
                float4 viewPos = mul(UNITY_MATRIX_I_P, clipPos);
                return viewPos.xyz / viewPos.w;
            }

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

            float SampleLinear01Depth(float2 uv)
            {
                float rawDepth = SampleRawDepth(uv);
                float depth = Linear01Depth(rawDepth, _ZBufferParams);
                return depth;
            }

            float InverseLinear01Depth(float d)
            {
                // Linear01Depth
                // return 1.0 / (_ZBufferParams.x * z + _ZBufferParams.y);

                // d = 1.0 / (_ZBufferParams.x * z + _ZBufferParams.y);
                // d * (_ZBufferParams.x * z + _ZBufferParams.y) = 1.0;
                // _ZBufferParams.x * z * d + _ZBufferParams.y * d = 1.0;
                // _ZBufferParams.x * z * d = 1.0 - _ZBufferParams.y * d;
                // z = (1.0 - _ZBufferParams.y * d) / (_ZBufferParams.x * d);

                return (1 - _ZBufferParams.y * d) / (_ZBufferParams.x * d);
            }

            float3x3 GetTBNMatrix(float3 viewNormal)
            {
                float3 tangent = float3(1, 0, 0);
                float3 bitangent = float3(0, 1, 0);
                float3 normal = viewNormal;
                float3x3 tbn = float3x3(tangent, bitangent, normal);
                return tbn;
            }

            float2x2 GetRotationMatrix(float rad)
            {
                float c = cos(rad);
                float s = sin(rad);
                return float2x2(c, -s, s, c);
            }

            float SampleRawDepthByViewPosition(float3 viewPosition, float3 offset)
            {
                // 1: world -> view -> clip
                // float4 offsetWorldPosition = float4(worldPosition, 1.) + offset * _OcclusionSampleLength;
                // float4 offsetViewPosition = mul(_ViewMatrix, offsetWorldPosition);
                // float4 offsetClipPosition = mul(_ViewProjectionMatrix, offsetWorldPosition);

                // 2: view -> clip
                float4 offsetViewPosition = float4(viewPosition + offset, 1.);
                float4 offsetClipPosition = mul(UNITY_MATRIX_P, offsetViewPosition);

                #if UNITY_UV_STARTS_AT_TOP
                offsetClipPosition.y = -offsetClipPosition.y;
                #endif

                // TODO: reverse zを考慮してあるべき？
                float2 samplingCoord = (offsetClipPosition.xy / offsetClipPosition.w) * 0.5 + 0.5;
                float samplingRawDepth = SampleRawDepth(samplingCoord);

                return samplingRawDepth;
            }

            // ------------------------------------------------------------------------------------------------

            float4 Frag(Varyings i) : SV_Target
            {
                // 1. depth を depth texture から参照する場合
                // return float4(i.texcoord.r, i.texcoord.g, 1.0, 1.0);
                float rawDepth = SampleRawDepth(i.texcoord);
                float depth = Linear01Depth(rawDepth, _ZBufferParams);
                // return float4(depth, depth, depth, 1.);

                float3 viewPosition = ReconstructViewPositionFromDepth(i.texcoord, rawDepth);

                // return float4(viewPosition, 1.);
                // return float4(rawDepth, rawDepth, rawDepth, 1.);
                // return float4(depth, depth, depth, 1.);

                float eps = .0001;

                // mask exists depth
                if (depth > 1. - eps)
                {
                    return float4(1, 1, 1, 1);
                }

                float occludedAcc = 0.;
                int samplingCount = 6;
                float aaaaa = 0.;

                for (int j = 0; j < samplingCount; j++)
                {
                    float2x2 rot = GetRotationMatrix(_SamplingRotations[j]);
                    float offsetLen = _SamplingDistances[j] * _OcclusionSampleLength;
                    float3 offsetA = float3(mul(rot, float2(1, 0)), 0.) * offsetLen;
                    float3 offsetB = -offsetA;

                    float rawDepthA = SampleRawDepthByViewPosition(viewPosition, offsetA);
                    float rawDepthB = SampleRawDepthByViewPosition(viewPosition, offsetB);

                    aaaaa += rawDepthA + rawDepthB;

                    float depthA = Linear01Depth(rawDepthA, _ZBufferParams);
                    float depthB = Linear01Depth(rawDepthB, _ZBufferParams);

                    float3 viewPositionA = ReconstructViewPositionFromDepth(i.texcoord, rawDepthA);
                    float3 viewPositionB = ReconstructViewPositionFromDepth(i.texcoord, rawDepthB);

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

                    // pattern_1: calc angle by view z
                    // float tanA = (viewPositionA.z - viewPosition.z) / distance(viewPositionA.xy, viewPosition.xy);
                    // float tanB = (viewPositionB.z - viewPosition.z) / distance(viewPositionB.xy, viewPosition.xy);
                    // float angleA = atan(tanA);
                    // float angleB = atan(tanB);
                    // float ao = min((angleA + angleB) / PI, 1.);

                    // pattern_2: compare with surface to camera
                    float3 surfaceToCameraDir = -normalize(viewPosition);
                    float dotA = dot(normalize(viewPositionA - viewPosition), surfaceToCameraDir);
                    float dotB = dot(normalize(viewPositionB - viewPosition), surfaceToCameraDir);
                    float ao = (dotA + dotB) * .5;

                    occludedAcc += ao;
                }

                float aoRate = occludedAcc / (float)samplingCount;
                return float4(aoRate, aoRate, aoRate, 1.0);
            }
            ENDHLSL

        }
    }
}