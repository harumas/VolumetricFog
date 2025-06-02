Shader "Example/Outline"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _SpecColor ("Specular Color", Color) = (1, 1, 1, 1)
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width", Range(0, 100)) = 1
        _OutlineOffset ("Outline Offset", Range(-10, 10)) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _NoiseScale ("Noise Scale", Range(0.1, 50)) = 5
        _NoiseStrength ("Noise Strength", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalRenderPipeline"
        }

        // 通常描画パス
        Pass
        {
            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _SpecColor;
                float _Smoothness;
                float _NoiseScale;
                float _NoiseStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
            };


            float random2(float2 st)
            {
                st = float2(dot(st, float2(127.1, 311.7)),
                                                                     dot(st, float2(269.5, 183.3)));
                return -1.0 + 2.0 * frac(sin(st) * 43758.5453123);
            }

            // 2Dパーリンノイズ
            float perlin2D(float2 st)
            {
                float2 i = floor(st);
                float2 f = frac(st);

                float2 u = f * f * (3.0 - 2.0 * f);

                float2 ga = random2(i + float2(0.0, 0.0));
                float2 gb = random2(i + float2(1.0, 0.0));
                float2 gc = random2(i + float2(0.0, 1.0));
                float2 gd = random2(i + float2(1.0, 1.0));

                float va = dot(ga, f - float2(0.0, 0.0));
                float vb = dot(gb, f - float2(1.0, 0.0));
                float vc = dot(gc, f - float2(0.0, 1.0));
                float vd = dot(gd, f - float2(1.0, 1.0));

                return lerp(lerp(va, vb, u.x),
                  lerp(vc, vd, u.x), u.y) * 0.5 + 0.5;
            }


            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                float2 view = TransformWorldToView(OUT.positionWS);
                float noise = perlin2D(view * _NoiseScale) * _NoiseStrength;
                float3 posOS = IN.positionOS.xyz + IN.normalOS * noise;
                OUT.positionHCS = TransformObjectToHClip(posOS);
                return OUT;
            }


            half4 frag(Varyings IN) : SV_Target
            {
                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                float3 viewDir = normalize(GetWorldSpaceViewDir(IN.positionWS));
                float3 halfDir = normalize(lightDir + viewDir);

                float3 normal = normalize(IN.normalWS);
                float NdotL = saturate(dot(normal, lightDir)) * 0.8 + 0.5;
                float NdotH = saturate(dot(normal, halfDir));

                float specular = 1 - step(pow(NdotH, _Smoothness * 100.0) * _Smoothness, 0.1);
                float3 specColor = _SpecColor.rgb * specular * mainLight.color;

                return half4(_BaseColor.rgb * NdotL + specColor, 1);
            }
            ENDHLSL
        }

        // アウトラインパス
        Pass
        {
            Name "Outline"
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _OutlineWidth;
                float _OutlineOffset;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 posOS = IN.positionOS.xyz + IN.normalOS * (_OutlineWidth * 0.001);

                // オフセット方向に更に移動
                float3 viewPos = TransformWorldToView(TransformObjectToWorld(posOS));
                viewPos.xy += float2(1, 1) * (_OutlineOffset * 0.01);
                float3 worldPos = TransformViewToWorld(viewPos);

                OUT.positionHCS = TransformWorldToHClip(worldPos);

                return OUT;
            }

            half4 frag() : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }


    }
}