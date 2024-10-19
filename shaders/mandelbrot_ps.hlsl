cbuffer mousePositionCB : register(b1)
{
    float2 mousePosition;
}

cbuffer screenSizeCB : register(b2)
{
    float2 screenSize;
}

cbuffer offsetCB : register(b3)
{
    float2 offset;
}

cbuffer zoomCB : register(b4)
{
    float zoom;
}

struct PSInput
{
    float4 positionSV : SV_POSITION;
    float2 texcoord : TEXCOORD;
};

float4 main(PSInput input) : SV_TARGET0
{
    // float2 offset = float2(0.0, 0.0);
    // float fromX = 4.0;
    // float toX = 4.0;

    float2 coords = float2(
        offset.x + 4.0 / zoom * input.positionSV.x / screenSize.x - 2.0 / zoom, 
        offset.y + 4.0 / zoom * -input.positionSV.y / screenSize.y + 2.0 / zoom
    );

    coords.x *= screenSize.x / screenSize.y;

    // float2 coords = float2(input.positionSV.x - screenSize.x / 2, -input.positionSV.y + screenSize.y / 2);
    // coords /= 20;

    float y = mousePosition.y, x = mousePosition.x;
    float yTemp = 0.0, xTemp = 0.0;
    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    for (int i = 0; i < 100; i++) {
        coords = float2(coords.x * coords.x - coords.y * coords.y, coords.x * coords.y + coords.y * coords.x);

        coords.x += x;
        coords.y += y;

        if (coords.x + coords.y >= 4) {
            return float4(1.0 - float(i) / 100.0, float(i) / 100.0, 1.0, 1.0);
        }

        // if (xTemp + yTemp >= 4) {
        //     return float4(0.0, float(i) / 100.0, 1.0, 1.0);
        // }
        // y = 2 * x * y + coords.y;
        // x = xTemp - yTemp + coords.x;
        // xTemp = x * x;
        // yTemp = y * y;
    }

    return color;
}