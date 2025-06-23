// ファイル名: Standalone_PencilInterior_NoPaper.shader
Shader "PencilRendering/Standalone_PencilInterior_NoPaper"
{
    Properties
    {
        // _PaperNormalMap と _PaperEffectWeight を削除
        [Header(Interior Shading)]
        _PencilTexture1 ("Pencil Tonal Map 1", 2D) = "" {}
        _PencilTexture2 ("Pencil Tonal Map 2", 2D) = "" {}
        _PencilTexture3 ("Pencil Tonal Map 3", 2D) = "" {}
        _TextureScale ("Texture Scale", Float) = 1.0
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "LightMode"="UniversalForward"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

                 struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                // ▼▼▼ 修正点 ▼▼▼
                float2 uv           : TEXCOORD0; // モデルのUV座標を受け取る
                float3 minCurvatureDirOS : TEXCOORD1; 
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 normalWS     : NORMAL;
                float3 lightDirWS   : TEXCOORD0;
                float2 minCurvatureDirSS : TEXCOORD1; 
                // ▼▼▼ 修正点 ▼▼▼
                float2 uv           : TEXCOORD2; // UVをピクセルシェーダーに渡す
            };

            CBUFFER_START(UnityPerMaterial)
                float _TextureScale;
            CBUFFER_END

       TEXTURE2D(_PencilTexture1);
            SAMPLER(sampler_PencilTexture1);
            TEXTURE2D(_PencilTexture2);
            SAMPLER(sampler_PencilTexture2);
            TEXTURE2D(_PencilTexture3);
            SAMPLER(sampler_PencilTexture3);
            // PaperNormalMapのテクスチャ宣言を削除

            
            float SamplePencilTexture(float2 uv, float brightness)
            {
                if (brightness > 0.66)
                {
                    return SAMPLE_TEXTURE2D(_PencilTexture1, sampler_PencilTexture1, brightness).r;
                }
                else if (brightness > 0.33)
                {
                    return SAMPLE_TEXTURE2D(_PencilTexture2, sampler_PencilTexture2, brightness).r;
                }
                else
                {
                    return SAMPLE_TEXTURE2D(_PencilTexture3, sampler_PencilTexture3, brightness).r;
                }
            }
            float2 rotate(float2 uv, float angle)
            {
                float s = sin(angle);
                float c = cos(angle);
                float2x2 rotationMatrix = float2x2(c, -s, s, c);
                return mul(uv, rotationMatrix);
            }

            Varyings vert(Attributes IN)
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

                
  // ▼▼▼ 修正点 ▼▼▼
                OUT.uv = IN.uv; // 受け取ったUVをVaryingsに格納
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half diffuse = saturate(dot(IN.normalWS, IN.lightDirWS));
                half brightness = sqrt(diffuse);

                float angle = atan2(IN.minCurvatureDirSS.y, IN.minCurvatureDirSS.x);
  // screenPosの代わりにモデルのUVを使う
                float2 rotatedUV = rotate(IN.uv * _TextureScale, angle);
                half pencilColor = SamplePencilTexture(rotatedUV,brightness);

                // ▼▼▼ 紙の法線マップに関する処理をすべて削除 ▼▼▼
                half finalColor = pencilColor;

                if (brightness < 0.4)
                {
                    float2 crossHatchUV = rotate(IN.uv * _TextureScale, angle + 1.5708);
                    half crossHatchColor = SamplePencilTexture(crossHatchUV,brightness);
                    finalColor = min(finalColor, crossHatchColor);
                }
                // ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

                return half4(saturate(finalColor).xxx, 1.0);
            }
            ENDHLSL
        }
    }
}