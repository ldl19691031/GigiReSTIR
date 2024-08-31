/*$(ShaderResources)*/
static const uint RaytracingInstanceMaskAll			 = 0xFF;
static const float c_pi = 3.14159265359f;
static const float c_twopi = 2.0f * c_pi;


struct Sample
{
	float4 path[3];
	float3 surfaceNormal;
	float W;
	float3 rayDir;
	float V12;
};

// Hash function from H. Schechter & R. Bridson, goo.gl/RXiKaH
uint Hash(uint s)
{
    s ^= 2747636419u;
    s *= 2654435769u;
    s ^= s >> 16;
    s *= 2654435769u;
    s ^= s >> 16;
    s *= 2654435769u;
    return s;
}

float3 LinearToSRGB(float3 linearCol)
{
	float3 sRGBLo = linearCol * 12.92;
	float3 sRGBHi = (pow(abs(linearCol), float3(1.0 / 2.4, 1.0 / 2.4, 1.0 / 2.4)) * 1.055) - 0.055;
	float3 sRGB;
	sRGB.r = linearCol.r <= 0.0031308 ? sRGBLo.r : sRGBHi.r;
	sRGB.g = linearCol.g <= 0.0031308 ? sRGBLo.g : sRGBHi.g;
	sRGB.b = linearCol.b <= 0.0031308 ? sRGBLo.b : sRGBHi.b;
	return sRGB;
}

Sample AreaSampleLights(uint2 px, float3 directLightDir)
{
	Sample s = (Sample)(0);
	
	float depth = g_depth[px];
	float3 dir = directLightDir;
	// Calculate screen position of this pixel
	float2 screenPos = (float2(px)+0.5f) / DispatchRaysDimensions().xy * 2.0 - 1.0;
	screenPos.y = -screenPos.y;

	// Calculate world position of the pixel, at the depth location in the depth buffer
	float4 world = mul(float4(screenPos, depth, 1), /*$(Variable:InvViewProjMtx)*/);
	world.xyz /= world.w;
	s.path[1] = world;
	
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
	s.rayDir = dir;
	
	if(/*$(Variable:enableRandomSample)*/)
	{
		uint2 noiseDims;
		g_noiseTexture.GetDimensions(noiseDims.x, noiseDims.y);
		float3 dir_noise = g_noiseTexture[px % noiseDims].rgb;
		dir_noise = dir_noise * 2.0f - 1.0f;

		dir_noise = normalize(dir_noise);

		float3x3 TBN = float3x3(
				wstangent,
				wsbitangent,
				wsnormal
			);

		dir_noise = mul(dir_noise, TBN);
		
		dir += dir_noise;

		if (dot(dir, wsnormal) < 0.0f)
			dir *= -1.0f;
	}
	

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
		/*$(RTMissIndex:MCMiss)*/,
		ray,
		payload);
	
	return payload;
}
float G(Sample s)
{
	float3 vec = s.path[2].xyz - s.path[1].xyz;
	float3 l = normalize(vec);
	float3 n = s.surfaceNormal;
	float dist = 1.0f;//length(vec);
	float cosTheta_i = max(0.0f, dot(l,n));
	return cosTheta_i / (dist * dist);
}
float3 BRDF(Sample s)
{
	float3 kd = float3(1,1,1); // surface color.
	const float pi = 3.14;
	return (kd) / pi;
}
float3 Le(Sample s)
{
	return float3(1.0f, 1.0f, 1.0f);
}
float V(Sample s)
{
	if(s.V12)
	{
		return 1.0f;
	}
	else
	{
		return 0.0f;
	}
}
void ShadePixel(uint2 px, float3 directLightDir)
{
	
	float depth = g_depth[px];
	if (depth == /*$(Variable:depthClearValue)*/)
	{
		g_texture[px] = 1.0f;
		return;
	}
	
	Sample s = AreaSampleLights(px, directLightDir);
	g_debugTexture[px].xyz = s.W;
	g_texture[px] = BRDF(s) * Le(s) * G(s) * V(s) * s.W;
}

[shader("raygeneration")]
void NaiveMCRayGen()
{
	uint2 px = DispatchRaysIndex().xy;
	float3 directLightDir = -1.0f * normalize(/*$(Variable:directLightDir)*/);
	float depth = g_depth[px];
	if (depth == /*$(Variable:depthClearValue)*/)
	{
		g_texture[px] = 1.0f;
		return;
	}
	ShadePixel(px, directLightDir);
	return;
}

[shader("miss")]
void MCMiss(inout Sample payload : SV_RayPayload)
{
	payload.path[2].xyz = payload.path[1] + payload.rayDir * /*$(Variable:rayMax)*/;
	payload.V12 = 1.0f; // Can see the sky light
}

[shader("closesthit")]
void MCClosestHit(inout Sample payload : SV_RayPayload,
				 BuiltInTriangleIntersectionAttributes intersection : SV_IntersectionAttributes)
{
	payload.path[2].xyz = RayTCurrent() * payload.rayDir + payload.path[1];
	payload.V12 = 0.0f ;
}
