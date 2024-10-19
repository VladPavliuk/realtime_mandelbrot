package main

import "core:strings"

import "base:intrinsics"

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "core:unicode/utf8"

import "core:math"
import "core:strconv"
import "core:slice"

RED_COLOR := float4{ 1.0, 0.0, 0.0, 1.0 }
GREEN_COLOR := float4{ 0.0, 1.0, 0.0, 1.0 }
BLUE_COLOR := float4{ 0.0, 0.0, 1.0, 1.0 }

render :: proc() {
    ctx := directXState.ctx

    ctx->ClearRenderTargetView(directXState.backBufferView, &float4{ 0.0, 0.0, 0.0, 1.0 })
    ctx->ClearDepthStencilView(directXState.depthBufferView, { .DEPTH, .STENCIL }, 1.0, 0)
    
    ctx->OMSetRenderTargets(1, &directXState.backBufferView, directXState.depthBufferView)
    ctx->OMSetDepthStencilState(directXState.depthStencilState, 0)
    ctx->RSSetState(directXState.rasterizerState)
	ctx->PSSetSamplers(0, 1, &directXState->samplerState)

    // ctx->OMSetBlendState(directXState.blendState, nil, 0xFFFFFFFF)

	ctx->IASetPrimitiveTopology(d3d11.PRIMITIVE_TOPOLOGY.TRIANGLELIST)
    ctx->IASetInputLayout(directXState.inputLayouts[.POSITION_AND_TEXCOORD])

    offsets := [?]u32{ 0 }
    strideSize := [?]u32{directXState.vertexBuffers[.QUAD].strideSize}
	ctx->IASetVertexBuffers(0, 1, &directXState.vertexBuffers[.QUAD].gpuBuffer, raw_data(strideSize[:]), raw_data(offsets[:]))
	ctx->IASetIndexBuffer(directXState.indexBuffers[.QUAD].gpuBuffer, dxgi.FORMAT.R32_UINT, 0)
 
    //MANDELBROT
    renderMandelbrot()
    mousePosition := screenToDirectXCoords(int2 { i32(windowData.clickedPoint.x), i32(windowData.clickedPoint.y) })

    size: i32 = 10
    renderRect(int2{ mousePosition.x - size / 2, mousePosition.y - size / 2 },
        int2{ size, size }, 1.0, RED_COLOR)

    hr := directXState.swapchain->Present(1, {})
    assert(hr == 0, fmt.tprintfln("DirectX presentation error: %i", hr))
}

renderMandelbrot :: proc() {
    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.BASIC], nil, 0)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
    ctx->VSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MODEL_TRANSFORMATION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.MANDELBROT], nil, 0)
    ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)
    ctx->PSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MOUSE_POSITION].gpuBuffer)
    ctx->PSSetConstantBuffers(2, 1, &directXState.constantBuffers[.SCREEN_SIZE].gpuBuffer)
    ctx->PSSetConstantBuffers(3, 1, &directXState.constantBuffers[.OFFSET].gpuBuffer)
    ctx->PSSetConstantBuffers(4, 1, &directXState.constantBuffers[.ZOOM].gpuBuffer)

    modelMatrix := getTransformationMatrix(
        { f32(-windowData.size.x) / 2, -f32(windowData.size.y) / 2, 2.0 }, 
        { 0.0, 0.0, 0.0 }, { f32(windowData.size.x), f32(windowData.size.y), 1.0 })

    updateGpuBuffer(&modelMatrix, directXState.constantBuffers[.MODEL_TRANSFORMATION])

    directXState.ctx->DrawIndexed(directXState.indexBuffers[.QUAD].length, 0, 0)
}

screenToDirectXCoords :: proc(coords: int2) -> int2 {
    return {
        coords.x - windowData.size.x / 2,
        -coords.y + windowData.size.y / 2,
    }
}

renderRect :: proc{renderRectVec_Float, renderRectVec_Int, renderRect_Int}

renderRect_Int :: proc(rect: Rect, zValue: f32, color: float4) {
    renderRectVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, zValue, color)
}

renderRectVec_Int :: proc(position, size: int2, zValue: f32, color: float4) {
    renderRectVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, zValue, color)
}

renderRectVec_Float :: proc(position, size: float2, zValue: f32, color: float4) {
    color := color
    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.BASIC], nil, 0)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
    ctx->VSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MODEL_TRANSFORMATION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.SOLID_COLOR], nil, 0)
    ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)

    modelMatrix := getTransformationMatrix(
        { position.x, position.y, zValue }, 
        { 0.0, 0.0, 0.0 }, { size.x, size.y, 1.0 })

    updateGpuBuffer(&modelMatrix, directXState.constantBuffers[.MODEL_TRANSFORMATION])
    updateGpuBuffer(&color, directXState.constantBuffers[.COLOR])

    directXState.ctx->DrawIndexed(directXState.indexBuffers[.QUAD].length, 0, 0)
}

renderImageRect :: proc{renderImageRectVec_Float, renderImageRectVec_Int, renderImageRect_Int}

renderImageRect_Int :: proc(rect: Rect, zValue: f32, texture: TextureId) {
    renderImageRectVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, zValue, texture)
}

renderImageRectVec_Int :: proc(position, size: int2, zValue: f32, texture: TextureId) {
    renderImageRectVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, zValue, texture)
}

renderImageRectVec_Float :: proc(position, size: float2, zValue: f32, texture: TextureId) {
    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.BASIC], nil, 0)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
    ctx->VSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MODEL_TRANSFORMATION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.TEXTURE], nil, 0)
    ctx->PSSetShaderResources(0, 1, &directXState.textures[texture].srv)

    modelMatrix := getTransformationMatrix(
        { position.x, position.y, zValue }, 
        { 0.0, 0.0, 0.0 }, { size.x, size.y, 1.0 })

    updateGpuBuffer(&modelMatrix, directXState.constantBuffers[.MODEL_TRANSFORMATION])

    directXState.ctx->DrawIndexed(directXState.indexBuffers[.QUAD].length, 0, 0)
}

renderRectBorder :: proc{renderRectBorderVec_Float, renderRectBorderVec_Int, renderRectBorder_Int}

renderRectBorder_Int :: proc(rect: Rect, thickness, zValue: f32, color: float4) {
    renderRectBorderVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, thickness, zValue, color)
}

renderRectBorderVec_Int :: proc(position, size: int2, thickness, zValue: f32, color: float4) {
    renderRectBorderVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, thickness, zValue, color)
}

renderRectBorderVec_Float :: proc(position, size: float2, thickness, zValue: f32, color: float4) {
    renderRect(float2{ position.x, position.y + size.y - thickness }, float2{ size.x, thickness }, zValue, color) // top border
    renderRect(position, float2{ size.x, thickness }, zValue, color) // bottom border
    renderRect(position, float2{ thickness, size.y }, zValue, color) // left border
    renderRect(float2{ position.x + size.x - thickness, position.y }, float2{ thickness, size.y }, zValue, color) // right border
}
