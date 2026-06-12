cbuffer TriangleParams : register(b0)
{
    float4 Tint;
};

struct PSInput
{
    float4 position : SV_POSITION;
    float4 color : COLOR0;
};

float4 PSMain(PSInput input) : SV_TARGET
{
    return input.color * Tint;
}
