Shader "Example/Outline"
{
    Properties
    {
        [MainTexture] _MainTex ("Main Texture", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _SpecColor ("Specular Color", Color) = (1, 1, 1, 1)
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width", Range(0, 100)) = 1
        _OutlineOffset ("Outline Offset", Range(-10, 10)) = 1
        _ZOffset ("Z Offset", Float) = 1
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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
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
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 viewDirWS : TEXCOORD2;
                float2 uv : TEXCOORD3;
            };


            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);

                float3 wpos = TransformObjectToWorld(IN.positionOS);

                // カメラの正面ベクトルを取得
                OUT.viewDirWS = normalize(_WorldSpaceCameraPos - wpos);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                Light mainLight = GetMainLight();
                float3 lightDir = mainLight.direction;
                float3 normal = normalize(IN.normalWS);
                float NdotL = saturate(dot(normal, lightDir)) + 0.3 > 0.5 ? 1 : 0.6;

                // フレネル反射の計算
                float fresnel = 1.0 - saturate(dot(normal, IN.viewDirWS));
                float ndot = saturate(dot(normal, lightDir)) * 1.8;
                fresnel = pow(fresnel * ndot, 6.0); // べき乗で効果を調整

                return half4(_BaseColor.rgb * texColor.rgb * NdotL + fresnel, 1);
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
                float _ZOffset;
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
                float3 wpos = TransformObjectToWorld(posOS);

                // カメラの正面ベクトルを取得
                float3 viewDir = normalize(_WorldSpaceCameraPos - wpos);

                // オフセット方向に更に移動
                float3 viewPos = TransformWorldToView(TransformObjectToWorld(posOS));
                viewPos.xy += float2(1, 1) * (_OutlineOffset * 0.01);
                float3 worldPos = TransformViewToWorld(viewPos);

                worldPos -= viewDir * _ZOffset;

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