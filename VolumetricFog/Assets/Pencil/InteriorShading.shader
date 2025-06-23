// ファイル名: InteriorShading.shader
Shader "PencilRendering/InteriorShading"
{
    Properties
    {
        [Header(Interior Shading)]
        _PencilTextures ("Pencil Tonal Map (Tex3D)", 3D) = "" {}
        _PaperNormalMap ("Paper Normal Map", 2D) = "bump" {}
        _TextureScale ("Texture Scale", Float) = 1.0
        _PaperEffectWeight ("Paper Effect Weight", Range(0.0, 0.1)) = 0.05
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float3 minCurvatureDirOS : TEXCOORD1; // Object space curvature direction
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 normalWS     : NORMAL;
                float3 lightDirWS   : TEXCOORD0;
                float2 minCurvatureDirSS : TEXCOORD1; // Screen space curvature direction
                float2 screenPos    : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
                float _TextureScale;
                float _PaperEffectWeight;
            CBUFFER_END
            
            TEXTURE3D(_PencilTextures);
            SAMPLER(sampler_PencilTextures);
            TEXTURE2D(_PaperNormalMap);
            SAMPLER(sampler_PaperNormalMap);

            float2 rotate(float2 uv, float angle)
            {
                float s = sin(angle);
                float c = cos(angle);
                float2x2 rotationMatrix = float2x2(c, -s, s, c);
                return mul(uv, rotationMatrix);
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS = positionInputs.positionCS;
                OUT.normalWS = normalInputs.normalWS;
                
                Light mainLight = GetMainLight();
                OUT.lightDirWS = mainLight.direction;

                float4 curDirOS = float4(IN.positionOS.xyz + IN.minCurvatureDirOS, 1.0);
                float4 curDirCS = mul(UNITY_MATRIX_VP, mul(UNITY_MATRIX_M, curDirOS));
                float2 curDirSS = curDirCS.xy / curDirCS.w;
                float2 posSS = positionInputs.positionCS.xy / positionInputs.positionCS.w;
                OUT.minCurvatureDirSS = normalize(curDirSS - posSS);

                OUT.screenPos = positionInputs.positionCS.xy;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                half diffuse = saturate(dot(IN.normalWS, IN.lightDirWS));
                half brightness = sqrt(diffuse);

                float angle = atan2(IN.minCurvatureDirSS.y, IN.minCurvatureDirSS.x);
                float2 rotatedUV = rotate(IN.screenPos * _TextureScale * 0.01, angle);

                half pencilColor = SAMPLE_TEXTURE3D(_PencilTextures, sampler_PencilTextures, float3(rotatedUV, brightness)).r;

                half3 paperNormal = SAMPLE_TEXTURE2D(_PaperNormalMap, sampler_PaperNormalMap, IN.screenPos * _TextureScale * 0.01).xyz * 2.0 - 1.0;
                half paperDot = dot(paperNormal.xy, IN.minCurvatureDirSS);
                half paperEffect = _PaperEffectWeight * paperDot;
                half finalColor = pencilColor - paperEffect;
                
                if (brightness < 0.4)
                {
                    float2 crossHatchUV = rotate(IN.screenPos * _TextureScale * 0.01, angle + 1.5708);
                    half crossHatchColor = SAMPLE_TEXTURE3D(_PencilTextures, sampler_PencilTextures, float3(crossHatchUV, brightness)).r;
                    finalColor = min(finalColor, crossHatchColor);
                }

                return half4(saturate(finalColor).xxx, 1.0);
            }
            ENDHLSL
        }
    }
}