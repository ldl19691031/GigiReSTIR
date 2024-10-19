// NaiveMC technique, shader ReuseSpatially
/*$(ShaderResources)*/
#include "ReSTIRCommon.hlsl"

/*$(_compute:csmain)*/(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    uint2 size ;
    s_pixelPos = px;
    g_randomSeed = Hash(Hash(px.x) + Hash(px.y));
    g_texture.GetDimensions(size.x, size.y);
    if (px.x >= size.x || px.y >= size.y)
        return;
    float depth = g_depth[px];
	if (depth == /*$(Variable:depthClearValue)*/)
    {
        return;
    }
	float3 dir;
	float3 skyLightDirHint = normalize(-1.0f *  /*$(Variable:directLightDir)*/);
	// Calculate screen position of this pixel
	float2 screenPos = (float2(px)+0.5f) / DispatchRaysDimensions().xy * 2.0 - 1.0;
	screenPos.y = -screenPos.y;

	// Calculate world position of the pixel, at the depth location in the depth buffer
	float4 world = mul(float4(screenPos, depth, 1), /*$(Variable:InvViewProjMtx)*/);
	world.xyz /= world.w;
	// Get tangent frame
	float3 wsnormal = normalize(2.0f * (float3(g_gbuffer[uint3(px,0)].xyz) / 255.0f) - 1.0f);
    {
        Reservoir s = CreateReservoir();
        int spatialReuseNum = /*$(Variable:SpatialReuseNum)*/;
        uint M = 0;
        uint sampleCount = 0;
        for (int i = 0; i < spatialReuseNum; i++)
        {
            sampleCount ++;
            if (sampleCount > 100)
                break;
            uint2 px2 = px;
            int2 offset = RandPixelOffset(/*$(Variable:SpatialReuseRadius)*/);
            px2 = clamp(px2 + offset, 0, size - 1);
            float depth2 = g_depth[px2];
            float3 wsnormal2 = normalize(2.0f * (float3(g_gbuffer[uint3(px2,0)].xyz) / 255.0f) - 1.0f);
            //WriteToDebugTexture(depth2 - depth);
            if (abs(depth2 - depth) > 0.1f * depth)
            {
                i--;
                continue;
            }

            float d = abs(dot(wsnormal, wsnormal2));
            WriteToDebugTexture(d);
            if (abs(d) < 0.9397f) /*cos(20 degree)*/
                continue;
            
            
            Reservoir neighbor = GetReservoirFromTexture(g_ReservoirInfoTexture, px2);
            UpdateReservoir(s, neighbor.p_hat_s_x, neighbor.p_hat_s_x * neighbor.W * neighbor.M);
            s.M += neighbor.M;
        }
        
        float py_hat = s.p_hat_s_x;
        s.W = (1.0f / max(py_hat, 0.0001f)) * ( 1.0f / max(s.M, 0.0001f) * s.W_sum);

        //WriteToTexture(g_ReservoirInfoTexture, px, s);

        float3 finalColor = (py_hat * 1.0f) * s.W;
	    finalColor = LinearToSRGB(finalColor);
        g_texture[px] = float4(finalColor, 1.0f);
    }
}
