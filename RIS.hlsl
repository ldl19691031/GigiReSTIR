// NaiveMC technique, shader RISRayGen
/*$(ShaderResources)*/
#include "ReSTIRCommon.hlsl"


Sample AreaSampleLights(uint2 px, uint seed)
{
	Sample s = (Sample)(0);
	
	float depth = g_depth[px];
	float3 dir;
	float3 skyLightDirHint = normalize(-1.0f *  /*$(Variable:directLightDir)*/);
	// Calculate screen position of this pixel
	float2 screenPos = (float2(px)+0.5f) / DispatchRaysDimensions().xy * 2.0 - 1.0;
	screenPos.y = -screenPos.y;

	// Calculate world position of the pixel, at the depth location in the depth buffer
	float4 world = mul(float4(screenPos, depth, 1), /*$(Variable:InvViewProjMtx)*/);
	world.xyz /= world.w;
	s.path1 = world.xyz;
	
	// Get tangent frame
	float3 wsnormal = normalize(2.0f * (float3(g_gbuffer[uint3(px,0)].xyz) / 255.0f) - 1.0f);
	float4 tan = g_gbuffer[uint3(px,2)];
	float3 wstangent = 2.0f * (float3(tan.xyz) / 255.0f) - 1.0f;
	wstangent = normalize(wstangent - wsnormal * dot(wsnormal, wstangent));
	float3 wsbitangent = normalize(cross(wsnormal, wstangent));
	if (tan.w == 0.0f)
		wsbitangent *= -1.0f;

	s.surfaceNormal = wsnormal;
	s.W = 1.0f;//only shoot one ray
	
	[branch]
	if(/*$(Variable:enableRandomSample)*/)
	{
		
		uint2 noiseDims;
		g_noiseTexture.GetDimensions(noiseDims.x, noiseDims.y);

		uint2 randomOffset;
		randomOffset.x = Hash(seed + px.x);
		randomOffset.y = Hash(randomOffset.x + px.y);

		float3 dir_noise = g_noiseTexture[(px + randomOffset) % noiseDims].rgb;
		dir_noise = dir_noise * 2.0f - 1.0f;

		dir_noise = normalize(dir_noise);
		{
			float3x3 TBN = float3x3(
				wstangent,
				wsbitangent,
				wsnormal
			);

			dir_noise = mul(dir_noise, TBN);
		}
		dir = dir_noise;
	}

	if (dot(dir, wsnormal) < 0.0f)
		dir *= -1.0f;
	dir = normalize(dir);


	s.rayDir = dir;

	// make ray desc
	RayDesc ray;
	ray.Origin = world.xyz + wsnormal * 0.1f;
	ray.TMin = /*$(Variable:rayMin)*/;
	ray.TMax = /*$(Variable:rayMax)*/;
	ray.Direction = dir;

	Sample payload = s;

	// Shoot the ray and get the result in payload
	TraceRay(g_scene,
		RAY_FLAG_FORCE_OPAQUE,
		RaytracingInstanceMaskAll,
		/*$(RTHitGroupIndex:HitGroup0)*/,
		0,
		/*$(RTMissIndex:RISMiss)*/,
		ray,
		payload);
	
	return payload;
}
float3 ResampledImportanceSampling(uint M, uint2 px)
{
	// Sample samples[500];
	// float w[500];
	Reservoir r = CreateReservoir();
	float3 wsnormal = normalize(2.0f * (float3(g_gbuffer[uint3(px,0)].xyz) / 255.0f) - 1.0f);
	[loop]
	for(uint i = 0; i < M; i++)
	{
		uint seed = Hash(i);
		Sample s = AreaSampleLights(px, seed); // we force trace one ray to world Z+ direction, for better results
		
		
		float px = TargetFunction(s);
		float Wxi = 1.0f;
		float wi = (1.0f / M) * px * (1.0f);
		UpdateReservoir(r, s, wi);
		//w_total += wi;
	}
	//uint s = (Hash(px.x) + Hash(px.y)) % M;
	
	Sample Y = r.y;//samples[s];
	float w_total = r.W_sum;
	float py =  TargetFunction(Y);
	
	float Wy = w_total / py;
	
	float3 finalColor = (py * Y.W) * Wy;
	finalColor = LinearToSRGB(finalColor);
	return finalColor;
}

void ShadePixel(uint2 px)
{
	
	float depth = g_depth[px];
	if (depth == /*$(Variable:depthClearValue)*/)
	{
		g_texture[px] = 1.0f;
		return;
	}
	
	//Sample s = AreaSampleLights(px, directLightDir);
	g_texture[px] = ResampledImportanceSampling(/*$(Variable:RandomSampleNum)*/, px);
}


[shader("raygeneration")]
void RISRayGen()
{
	uint2 px = DispatchRaysIndex().xy;
	s_pixelPos = px;
	g_randomSeed = Hash(Hash(px.x) + Hash(px.y));
	float depth = g_depth[px];
	if (depth == /*$(Variable:depthClearValue)*/)
	{
		g_texture[px] = 1.0f;
		return;
	}
	ShadePixel(px);
	return;
}

[shader("miss")]
void RISMiss(inout Sample payload : SV_RayPayload)
{
	payload.path2 = payload.path1 + payload.rayDir * /*$(Variable:rayMax)*/;
	payload.V12 = 1.0f; // Can see the sky light
}

[shader("closesthit")]
void RISClosestHit(inout Sample payload : SV_RayPayload,
				 BuiltInTriangleIntersectionAttributes intersection : SV_IntersectionAttributes)
{
	payload.path2 = RayTCurrent() * payload.rayDir + payload.path1;
	payload.V12 = 0.0f;
}