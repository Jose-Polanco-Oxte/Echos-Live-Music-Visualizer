// Fase V / RS-SOL-D: la altura ya representa E_i normalizada en el vértice.
cbuffer MeshTransformConstants : register(b0)
{
    row_major float4x4 ModelViewProjection;
    float4 BandEnergies[32]; // Fase V: 128 E_i normalizadas, empacadas en float4.
    float Time;
    float RMS;
    float2 Padding;
};

struct VertexInput
{
    float3 Position : POSITION;
    float4 Color : COLOR;
    float BandIndex : TEXCOORD0;
};

struct PixelInput
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR;
};

PixelInput main(VertexInput input)
{
    PixelInput output;
    uint band = min(127u, (uint)input.BandIndex);
    float energy = BandEnergies[band >> 2][band & 3u];
    output.Position = mul(float4(input.Position, 1.0f), ModelViewProjection);
    output.Color = float4(input.Color.rgb, saturate(max(input.Color.a, energy)));
    return output;
}
