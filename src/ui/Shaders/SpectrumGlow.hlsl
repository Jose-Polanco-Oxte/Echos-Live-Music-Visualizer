// RS-SOL-D: saturate(E_i + 0.25 * RMS + onsetFlash) is assembled per vertex.
struct PixelInput
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR;
};

float4 main(PixelInput input) : SV_TARGET
{
    float intensity = saturate(input.Color.a);
    float3 glow = input.Color.rgb * (0.30f + 0.70f * intensity);
    return float4(glow, 1.0f);
}
