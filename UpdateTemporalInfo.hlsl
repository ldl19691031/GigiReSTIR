// NaiveMC technique, shader UpdateTemporalInfo
/*$(ShaderResources)*/

/*$(_compute:csmain)*/(uint3 DTid : SV_DispatchThreadID)
{
	float4x4 ViewProj = /*$(Variable:ViewProjMtx)*/;
	uint2 px = DTid.xy;
	if(/*$(Variable:EnableTemporalReuse)*/ == 0)
	{
		g_temporalInfo[0].TemporalReuse = 0;
		g_temporalInfo[0].ViewProjMatrix = ViewProj;
		return;
	}

	if(any(g_temporalInfo[0].ViewProjMatrix - ViewProj != 0.0f))
	{
		if(px.x == 0 && px.y == 0)
		{
			g_temporalInfo[0].TemporalReuse = 0;
			g_temporalInfo[0].ViewProjMatrix = ViewProj;
		}
	}
	else
	{
		g_temporalInfo[0].TemporalReuse++;
	}
}

/*
Shader Resources:
	Buffer g_temporalInfo (as UAV)
*/
