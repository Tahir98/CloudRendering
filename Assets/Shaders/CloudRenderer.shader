Shader "Unlit/CloudRenderer"
{
    Properties
    {

    } 

    SubShader
    {
        Tags { "Queue" = "Geometry" "RenderType" = "Tranparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Front
        LOD 200
        ZWrite On
        ZTest Off

        Pass
        {
            CGPROGRAM
            #pragma vertex VS_Main
            #pragma fragment FS_Main
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct VSInput //Vertex shader input
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct FSInput //Fragment shader input
            {
                float4 screenPos : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float2 uv : TEXCOORD0;
            };

            float4 _MainTex_ST;

            sampler3D _DensityTex;
            sampler2D _NoiseTex;

            float _StepSize;
            float _Opacity;
            float _OpacityThreshold;

            float3 _LightDir;

            float _MinDensity;
            float _MaxDensity;

            float3 _BoundMin;
            float3 _BoundMax;

            float3 _TextureFitSize;
            float3 _TextureOffset;

            float3 _LightDirection;
            float _LightMarchStepSize;
            float _LightBaseIntensity;
            float _LightAbsorptionCoefficient;

            float _Exposure;

            float2 SampleDensity(float3 texCoord) {
                return tex3D(_DensityTex, texCoord).rg;
            }

            float3 GetTextureCoordinate(float3 position) {
                float3 texCoord = (position + _TextureOffset) / _TextureFitSize;;
                texCoord.y = (position.y - _BoundMin.y) / (_BoundMax.y - _BoundMin.y);

                return texCoord;
            }

            bool InRange(float d, float minDensity, float maxDensity) {
                return (d >= minDensity) && (d <= maxDensity);
            }

            //It controls given ray intersects with box (x: distance to box, y: distance inside box)
            float2 RayIntersectAABB(float3 rayOrigin, float3 rayDir, float3 boundsMin, float3 boundsMax) {

                float3 invRayDir = 1.0f / rayDir;

                float3 t0 = (boundsMin - rayOrigin) * invRayDir;
                float3 t1 = (boundsMax - rayOrigin) * invRayDir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);

                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);

                return float2(dstToBox, dstInsideBox);
            }

            //Color blending (front-to-back)
            float4 BlendFTB(float4 color, float4 newColor)
            {
                color.rgb += (1.0 - color.a) * newColor.a * newColor.rgb;
                color.a += (1.0 - color.a) * newColor.a;
                return color;
            }

            //Color blending (back-to-front)
            float4 BlendBTF(float4 color, float4 newColor)
            {
                return (1 - newColor.a) * color + newColor.a * newColor;
            }

            float CalculateLightIntensity(float3 position, float3 direction, float noise) {
                float intensity = 1;

                float2 hit = RayIntersectAABB(position, direction, _BoundMin, _BoundMax);

                if(hit.y > 0) {
                    float stepSize = max(_LightMarchStepSize, 0.1f);
                    float offset = 0;// + stepSize * noise * -1.0f;  

                    [loop]
                    while(offset < hit.y) {
                        float3 pos = position + direction * offset;

                        float3 texCoord = GetTextureCoordinate(pos);
                        float density = SampleDensity(texCoord);

                        if(InRange(density, _MinDensity, _MaxDensity)) {
                            intensity = intensity * exp(stepSize * _LightAbsorptionCoefficient * -1.0f);

                            if(intensity < 0.001f)
                                break;
                        }
                        offset += stepSize;
                    }
                }

                return intensity;
            }

            float3 uncharted2_tonemap_partial(float3 x)
            {
                float A = 0.15f;
                float B = 0.50f;
                float C = 0.10f;
                float D = 0.20f;
                float E = 0.02f;
                float F = 0.30f;
                return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
            }

            float3 tonemap_filmic(float3 color, float exposure)
            {
                float3 curr = uncharted2_tonemap_partial(color * exposure);
            
                float3 W = float3(11.2f, 11.2f, 11.2f);
                float3 white_scale = float3(1.0f, 1.0f, 1.0f) / uncharted2_tonemap_partial(W);
                return curr * white_scale;
            }

            FSInput VS_Main (VSInput input) //Vertex shader main
            {
                FSInput output;
                output.screenPos = UnityObjectToClipPos(input.vertex);
                output.worldPos = mul(unity_ObjectToWorld, input.vertex);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            float4 FS_Main(FSInput input) : SV_Target //Fragment shader main
            {
                float4 outputColor = float4(0, 0, 0, 0);

                float3 cameraPos = _WorldSpaceCameraPos;
                float3 viewDir = normalize(input.worldPos - cameraPos);

                float2 hit = RayIntersectAABB(cameraPos, viewDir, _BoundMin, _BoundMax);
                float stepSize = max(_StepSize, 0.1f);

                float opacity = pow(stepSize * _Opacity / 2.0f, 0.9f);

                float offset = 0;
                
                float noise = tex2D(_NoiseTex, input.screenPos.xy / _ScreenParams.xy * 128).r;
                offset += noise * stepSize * -1.0f;

                if (hit.y > 0) {

                    [loop]
                    while (offset < hit.y) {
                        float3 position = cameraPos + viewDir * (hit.x + offset);
                        float3 texcoord = GetTextureCoordinate(position);
                    
                        float2 data  = SampleDensity(texcoord);
                        float density = data.x;
                        float lightIntensity = data.y;

                        if (InRange(density, _MinDensity, _MaxDensity)) {
                        
                            float3 color = float3(1, 1, 1) * lightIntensity;
                            outputColor = BlendFTB(outputColor, float4(color, density * opacity));

                            if (outputColor.a >= _OpacityThreshold)
                                break;
                        }             

                        offset += stepSize;
                    }
                }

                outputColor.a = clamp(outputColor.a / _OpacityThreshold, 0, 1);
                
                if (outputColor.a < 0.01f)
                    clip(-1);
                
                outputColor.rgb /= outputColor.a;

                //outputColor.rgb = tonemap_filmic(outputColor.rgb, _Exposure);  
                
                outputColor = clamp(outputColor, 0, 1);

                return outputColor;
            }
            ENDCG
        }
    }
}