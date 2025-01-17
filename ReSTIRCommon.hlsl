// NaiveMC technique, shader RISRayGen
/*$(ShaderResources)*/
static const uint RaytracingInstanceMaskAll			 = 0xFF;
static const float c_pi = 3.14159265359f;
static const float c_twopi = 2.0f * c_pi;
static uint2 s_pixelPos;
static uint g_randomSeed = 0;
static float3 g_lightPower = float3(1.0f, 1.0f, 1.0f);
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

struct Sample
{
	float3 path1;
	float3 path2;
	float3 surfaceNormal;
	float W;
	float3 rayDir;
	float V12;
};

struct Reservoir
{
	Sample y;
	float W_sum;
	uint M;

    float p_hat_s_x;
    float W;
};
Reservoir CreateReservoir(){
	Reservoir r = (Reservoir)0;
	r.W_sum = 0.0f;
	r.M = 0;
	return r;
}
uint Rand() {
	uint temp = Hash(g_randomSeed);
	g_randomSeed = Hash(temp);
	return temp;
}
int2 RandPixelOffset(uint size)
{
    return int2(Rand() % size, Rand() % size) - int2(size / 2, size / 2);
}
float FRand01(){
	return float(Rand() % 10000) / 10000.0f;
}
void UpdateReservoir(inout Reservoir r, Sample x, float px_hat, float w)
{
	r.W_sum += w;
	r.M = r.M + 1;
	if(FRand01() < (w / r.W_sum))
	{
		r.y = x;
        r.p_hat_s_x = px_hat;
	}
}
void UpdateReservoir(inout Reservoir r, float px_hat, float w)
{
	r.W_sum += w;
	r.M = r.M + 1;
	if(FRand01() < (w / r.W_sum))
	{
        r.p_hat_s_x = px_hat;
	}
}

void WriteToTexture(RWTexture2D<float4> texture, uint2 pos, Reservoir value)
{
    texture[pos] = float4(value.W_sum, (float)value.M, value.p_hat_s_x, value.W);
}
Reservoir GetReservoirFromTexture(RWTexture2D<float4> texture, uint2 pos)
{
    Reservoir value;
    value.W_sum = texture[pos].x;
    value.M = (uint)texture[pos].y;
    value.p_hat_s_x = texture[pos].z;
    value.W = texture[pos].w;
    return value;
}
void WriteToDebugTexture(float3 value)
{
	g_debugTexture[s_pixelPos].xyz = value;
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


float G(Sample s)
{
	float3 vec = s.path2.xyz - s.path1.xyz;
	float3 l = normalize(vec);
	float3 n = s.surfaceNormal;
	float dist = 1.0f;//length(vec);
	float cosTheta_i = max(0.0f, dot(l,n));
	
	return cosTheta_i / (dist * dist);
}
float BRDF(Sample s, uint2 px)
{
	return 1.0f / c_pi;
}
float3 Le(Sample s)
{
	return float3(1.0f, 1.0f, 1.0f) * g_lightPower;
}
float V(Sample s)
{
	return s.V12;
}

float TargetFunction(Sample s)
{
	return BRDF(s, s_pixelPos) * length(Le(s)) * G(s) * V(s);
}

