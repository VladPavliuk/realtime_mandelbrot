cbuffer solidColorCB : register(b0)
{
    float4 color;
}

struct PSInput
{
    float4 positionSV : SV_POSITION;
    float2 texcoord : TEXCOORD;
};

struct PSOutput
{
    float4 pixelColor : SV_TARGET0;
};

PSOutput main(PSInput input)
{
    PSOutput output;

    output.pixelColor = color;
    
    return output;
}