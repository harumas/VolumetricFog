Shader "Unlit/HaruToon"
{
    Properties
    {
        [Header(MainTexture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color", Color) = (0.5, 0.5, 0.5, 1)
        _NoiseScale ("Noise Scale", Float) = 50
        _NoiseStrength ("Noise Strength", Range(0, 1)) = 0.1
        
        [Header(OutLine)]
        _OutLineColor ("OutLineColor", Color) = (0, 0, 0, 1)
        _OutLineColor2 ("OutLineColor2", Color) = (0, 0, 0, 1)
        _OutLineThickness ("OutLineThickness", float) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "LightMode" = "UniversalForward"
        }

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "RenderType" = "Opaque"
                "Queue" = "Opaque"
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
            };

            float2 hash2D(float2 p)
            {
                float2 k = float2(0.3183099, 0.3678794);
                p = p * k + k.yx;
                return -1.0 + 2.0 * frac(16.0 * k * frac(p.x * p.y * (p.x + p.y)));
            }

            float perlinNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);

                return lerp(
                    lerp(dot(hash2D(i + float2(0, 0)), f - float2(0, 0)),
                         dot(hash2D(i + float2(1, 0)), f - float2(1, 0)), u.x),
                    lerp(dot(hash2D(i + float2(0, 1)), f - float2(0, 1)),
                         dot(hash2D(i + float2(1, 1)), f - float2(1, 1)), u.x), u.y);
            }

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _ShadowColor;
                float _NoiseScale;
                float _NoiseStrength;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionHCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.screenPos = ComputeScreenPos(output.positionHCS);

                // ワールド空間での頂点位置を計算
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);

                // カメラへの方向ベクトルを計算
                output.viewDirWS = normalize(GetWorldSpaceViewDir(positionWS));
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                Light mainLight = GetMainLight();

                float3 normalWS = normalize(input.normalWS);
                float fresnel = pow(1.0 - dot(normalWS, input.viewDirWS), 1);
                float NdotL = dot(normalWS, mainLight.direction) * 0.5f + 0.2f - fresnel;

                float2 screenUV = input.screenPos.xy / input.screenPos.w;
                float noise = perlinNoise(screenUV * _NoiseScale) * _NoiseStrength;

                half4 finalColor = lerp(_ShadowColor, _BaseColor, saturate(noise + NdotL + 1.0f)) * color;
                return finalColor;
            }
            ENDHLSL
        }

        Pass
        {
            Name "OutLine"
            Tags
            {
                "Queue" = "Transparent"
                "RenderType" = "Transparent"
                "LightMode" = "UniversalForward"
            }
            
            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


            float _OutLineThickness;
            half4 _OutLineColor;
            half4 _OutLineColor2;
            float _NoiseScale;
            float _NoiseStrength;

            float2 hash2D(float2 p)
            {
                float2 k = float2(0.3183099, 0.3678794);
                p = p * k + k.yx;
                return -1.0 + 2.0 * frac(16.0 * k * frac(p.x * p.y * (p.x + p.y)));
            }

            float perlinNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);

                return lerp(
                    lerp(dot(hash2D(i + float2(0, 0)), f - float2(0, 0)),
                         dot(hash2D(i + float2(1, 0)), f - float2(1, 0)), u.x),
                    lerp(dot(hash2D(i + float2(0, 1)), f - float2(0, 1)),
                         dot(hash2D(i + float2(1, 1)),
                             f - float2(1, 1)), u.x), u.y);
            }

            struct a2v
            {
                float4 positionOS: POSITION;
                float4 normalOS: NORMAL;
                float4 tangentOS: TANGENT;
            };

            struct v2f
            {
                float4 positionCS: SV_POSITION;
                float4 screenPos : TEXCOORD2;
            };

            v2f vert(a2v v)
            {
                v2f o;

                VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);

                float3 normalWS = vertexNormalInput.normalWS;
                float3 normalCS = TransformWorldToHClipDir(normalWS);

                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = positionInputs.positionCS + float4(normalCS.xy * 0.001 * _OutLineThickness, 0, 0);
                o.screenPos = ComputeScreenPos(TransformObjectToHClip(v.positionOS.xyz));


                return o;
            }

            half4 frag(v2f i): SV_Target
            {
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float noise = perlinNoise(screenUV * _NoiseScale) * _NoiseStrength;
                half4 finalColor = _OutLineColor;
                finalColor.a = noise + 1.0f;

                return finalColor;
            }
            ENDHLSL

        }
    }
}