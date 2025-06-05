Shader "CooGee/WavingShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        [Normal]_Normal_tex("Normal_tex", 2D) = "bump" {}
        _Metallic("Metallic", Range( 0 , 1)) = 0
		_Smoothness("Smoothness", Range( 0 , 1)) = 0
        _RimColor ("RimColor", Color) = (1,1,1,1)
        _RimPower("Rim Power", Range( 0 , 5)) = 0.0
        
        _ColorSpeed("Color Speed", Range(0.1, 50)) = 1
        _ColorCount("Color Count", Range(0.1, 100)) = 18
        _WavePower("Wave Power", Range(1, 20)) = 10
        _WaveMultiply("Wave Multiply", Range(0.0, 0.1)) = 0.02
        _WaveSpeed("Wave Speed", Range(1, 10)) = 10
    }
        SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        CGPROGRAM
        #pragma surface surf Standard vertex:vert noshadow
        #pragma target 3.0

        sampler2D _MainTex;
        uniform sampler2D _Normal_tex;
		uniform float4 _Normal_tex_ST;
        uniform float _Metallic;
		uniform float _Smoothness;
        
        float _ColorSpeed;
        float _ColorCount;
        float _WavePower;
        float _WaveMultiply;
        float _WaveSpeed;

        struct Input
        {
            float2 uv_MainTex;
            float3 viewDir;
            float3 worldPos;
            float3 worldNormal;
        };

        fixed4 _Color;
        fixed4 _RimColor;
        float _RimPower;

        void vert(inout appdata_full v) {
            //v.vertex.x += sin(v.vertex.x * _WavePower +_Time.y * 1 + 3) * _WaveMultiply;
            v.vertex.x += sin(v.vertex.x * _WavePower + _Time.y * _WaveSpeed) * _WaveMultiply;
            v.vertex.y += sin(v.vertex.y * _WavePower + _Time.y * _WaveSpeed) * _WaveMultiply;
            v.vertex.z += sin(v.vertex.z * _WavePower + _Time.y * _WaveSpeed) * _WaveMultiply;
            //v.vertex.z += sin(v.vertex.z * _WavePower + _Time.y * 1 - 3) * _WaveMultiply;
        }

        float4 LightingNoLight(SurfaceOutput s, float3 lightDir, float atten) {
            return float4(s.Albedo, s.Alpha);
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            float3 col = sin(_Time.y * _ColorSpeed + IN.worldPos * _ColorCount) * 0.3 + 0.7;
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
            float3 maincol = c * col;
            float2 uv_Normal_tex = IN.uv_MainTex * _Normal_tex_ST.xy + _Normal_tex_ST.zw;
			o.Normal = UnpackNormal( tex2D( _Normal_tex, uv_Normal_tex ) );
            o.Albedo = maincol.rgb;
            o.Emission = col * 0.3;
            o.Metallic = _Metallic;
			o.Smoothness = _Smoothness;
            
            float rim = 1 - saturate(dot(IN.viewDir, o.Normal));
            fixed3 rimEmission = _RimColor.rgb * pow(rim, _RimPower) * _RimPower;
     			o.Emission = rimEmission;

            /*
            float alpha = dot(o.Normal, IN.viewDir);

            float alpha1 = pow(1 - alpha, _RimPower);
            float alpha2 = pow(alpha, _RimPower * 5);

            o.Metallic = 1;
            o.Smoothness = 1;
            o.Alpha = saturate(alpha1 + alpha2 * 0.1 + 0.05);
            */
        }
        ENDCG
    }
    FallBack "Diffuse"
}
