package main

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

import "base:runtime"

import "core:mem"
import "core:image"

import "core:bytes"

GpuTexture :: struct {
    buffer: ^d3d11.ITexture2D,    
    srv: ^d3d11.IShaderResourceView,
    size: int2,  
}

GpuBufferType :: enum {
    QUAD,
}

RectWithColor :: struct #packed {
    transformation: mat4,
    color: float4,   
}

RectWithImage :: struct #packed {
    transformation: mat4,
    imageIndex: i32,   
}

GpuStructuredBufferType :: enum {
    RECTS_LIST,
    RECTS_WITH_COLOR_LIST,
    RECTS_WITH_IMAGE_LIST,
}

GpuBuffer :: struct {
	gpuBuffer: ^d3d11.IBuffer,
    srv: ^d3d11.IShaderResourceView,
	cpuBuffer: rawptr,
    length: u32,
    strideSize: u32,
	itemType: typeid,
}

VertexShaderType :: enum {
    BASIC,
    MULTIPLE_RECTS,
    RECTS_WITH_COLOR,
    RECTS_WITH_IMAGE,
}

PixelShaderType :: enum {
    SOLID_COLOR,
    MANDELBROT,
    TEXTURE,
    RECTS_WITH_COLOR,
    RECTS_WITH_IMAGE,
}

InputLayoutType :: enum {
    POSITION_AND_TEXCOORD,
}

GpuConstantBufferType :: enum {
    PROJECTION,
    MODEL_TRANSFORMATION,
    COLOR,
    MOUSE_POSITION,
    SCREEN_SIZE,

    ZOOM,
    OFFSET,
}

initGpuResources :: proc() {
    vertexShader, blob := compileVertexShader(#load("./shaders/basic_vs.hlsl"))
    defer blob->Release()

    inputLayoutDesc := [?]d3d11.INPUT_ELEMENT_DESC{
        { "POSITION", 0, dxgi.FORMAT.R32G32B32_FLOAT, 0, 0, d3d11.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
        { "TEXCOORD", 0, dxgi.FORMAT.R32G32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, d3d11.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    }

    inputLayout: ^d3d11.IInputLayout
    hr := directXState.device->CreateInputLayout(raw_data(inputLayoutDesc[:]), len(inputLayoutDesc), blob->GetBufferPointer(), blob->GetBufferSize(), &inputLayout)
    assert(hr == 0)

    directXState.vertexShaders[.BASIC] = vertexShader 
    directXState.vertexShaders[.MULTIPLE_RECTS], _ = compileVertexShader(#load("./shaders/multiple_rects_vs.hlsl"))
    directXState.vertexShaders[.RECTS_WITH_COLOR], _ = compileVertexShader(#load("./shaders/rects_with_color/vs.hlsl"))
    directXState.vertexShaders[.RECTS_WITH_IMAGE], _ = compileVertexShader(#load("./shaders/rects_with_image/vs.hlsl"))
    directXState.pixelShaders[.SOLID_COLOR] = compilePixelShader(#load("./shaders/solid_color_ps.hlsl"))
    directXState.pixelShaders[.MANDELBROT] = compilePixelShader(#load("./shaders/mandelbrot_ps.hlsl"))
    directXState.pixelShaders[.TEXTURE] = compilePixelShader(#load("./shaders/texture_ps.hlsl"))
    directXState.pixelShaders[.RECTS_WITH_COLOR] = compilePixelShader(#load("./shaders/rects_with_color/ps.hlsl"))
    directXState.pixelShaders[.RECTS_WITH_IMAGE] = compilePixelShader(#load("./shaders/rects_with_image/ps.hlsl"))
    directXState.inputLayouts[.POSITION_AND_TEXCOORD] = inputLayout
    
    VertexItem :: struct {
        position: float3,
        texcoord: float2,
    }

    quadVertices := make([]VertexItem, 4)
    quadVertices[0] = VertexItem{ {0.0, 0.0, 0.0}, {0.0, 1.0} } 
    quadVertices[1] = VertexItem{ {0.0, 1.0, 0.0}, {0.0, 0.0} } 
    quadVertices[2] = VertexItem{ {1.0, 1.0, 0.0}, {1.0, 0.0} } 
    quadVertices[3] = VertexItem{ {1.0, 0.0, 0.0}, {1.0, 1.0} }

    directXState.vertexBuffers[.QUAD] = createVertexBuffer(quadVertices[:])
    
    indices := make([]u32, 6)
    indices[0] = 0 
    indices[1] = 1 
    indices[2] = 2
    indices[3] = 0
    indices[4] = 2
    indices[5] = 3
    // indices := []u32{
    //     0,1,2,
    //     0,2,3,
    // }
    directXState.indexBuffers[.QUAD] = createIndexBuffer(indices[:])

    // camera
    viewMatrix := getOrthoraphicsMatrix(f32(windowData.size.x), f32(windowData.size.y), 0.1, windowData.maxZIndex + 1.0)
    directXState.constantBuffers[.PROJECTION] = createConstantBuffer(mat4, &viewMatrix)

    directXState.constantBuffers[.MODEL_TRANSFORMATION] = createConstantBuffer(mat4, nil)
    directXState.constantBuffers[.COLOR] = createConstantBuffer(float4, &float4{ 0.0, 0.0, 0.0, 1.0 })
    directXState.constantBuffers[.MOUSE_POSITION] = createConstantBuffer(float2, &float2{ 0.0, 0.0 })
    directXState.constantBuffers[.SCREEN_SIZE] = createConstantBuffer(float2, &float2{ 0.0, 0.0 })

    directXState.constantBuffers[.OFFSET] = createConstantBuffer(float2, nil)
    directXState.constantBuffers[.ZOOM] = createConstantBuffer(f32, nil)

    rectsList := make([]mat4, 15000)
    directXState.structuredBuffers[.RECTS_LIST] = createStructuredBuffer(rectsList)
    
    rectsWithColorList := make([]RectWithColor, 300)
    directXState.structuredBuffers[.RECTS_WITH_COLOR_LIST] = createStructuredBuffer(rectsWithColorList)
    
    rectsWithImageList := make([]RectWithImage, 300)
    directXState.structuredBuffers[.RECTS_WITH_IMAGE_LIST] = createStructuredBuffer(rectsWithImageList)
}

memoryAsSlice :: proc($T: typeid, pointer: rawptr, #any_int length: int) -> []T {
    return transmute([]T)runtime.Raw_Slice{pointer, length}
}

compileVertexShader :: proc(fileContent: string) -> (^d3d11.IVertexShader, ^d3d11.IBlob) {
    blob: ^d3d11.IBlob
    errMessageBlob: ^d3d11.IBlob = nil
    defer if errMessageBlob != nil { errMessageBlob->Release() }

	hr := d3d_compiler.Compile(raw_data(fileContent), len(fileContent), nil, nil, nil, 
        "main", "vs_5_0", 0, 0, &blob, &errMessageBlob)
    if errMessageBlob != nil {
        panic(string(cstring(errMessageBlob->GetBufferPointer())))
    } 
    assert(hr == 0)

    shader: ^d3d11.IVertexShader
    hr = directXState.device->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &shader)
    assert(hr == 0)
    return shader, blob
}

compilePixelShader :: proc(fileContent: string) -> ^d3d11.IPixelShader {
    blob: ^d3d11.IBlob
    defer blob->Release()

    errMessageBlob: ^d3d11.IBlob = nil
    defer if errMessageBlob != nil { errMessageBlob->Release() }

    // D3DCOMPILE_DEBUG
    hr := d3d_compiler.Compile(raw_data(fileContent), len(fileContent), nil, nil, nil, 
        "main", "ps_5_0", 0, 0, &blob, &errMessageBlob)
    if errMessageBlob != nil {
        panic(string(cstring(errMessageBlob->GetBufferPointer())))
    }
    assert(hr == 0)

    shader: ^d3d11.IPixelShader
    hr = directXState.device->CreatePixelShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &shader)
    assert(hr == 0)
    return shader   
}

createVertexBuffer :: proc(items: []$T) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(items) * size_of(T)),
        Usage = d3d11.USAGE.DEFAULT,
        BindFlags = {d3d11.BIND_FLAG.VERTEX_BUFFER},
        CPUAccessFlags = {},
        MiscFlags = {},
        StructureByteStride = size_of(T),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(items[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(items[:]),
        gpuBuffer = buffer,
        length = u32(len(items)),
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}

createIndexBuffer :: proc(indices: []u32) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(indices) * size_of(u32)),
        Usage = d3d11.USAGE.DEFAULT,
        BindFlags = {d3d11.BIND_FLAG.INDEX_BUFFER},
        CPUAccessFlags = {},
        MiscFlags = {},
        StructureByteStride = size_of(u32),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(indices[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(indices[:]),
        gpuBuffer = buffer,
        length = u32(len(indices)),
        strideSize = size_of(u32),
        itemType = typeid_of(u32),
    }
}

createConstantBuffer :: proc($T: typeid, initialData: ^T) -> GpuBuffer {
    bufferSize: u32 = size_of(T)

    desc := d3d11.BUFFER_DESC{
        ByteWidth = bufferSize + (16 - bufferSize % 16),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.CONSTANT_BUFFER},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {},
    }
    
    data := d3d11.SUBRESOURCE_DATA{}

    hr: d3d11.HRESULT
    buffer: ^d3d11.IBuffer
    if (initialData != nil) {
        data.pSysMem = initialData
        hr = directXState.device->CreateBuffer(&desc, &data, &buffer)
    } else {
        hr = directXState.device->CreateBuffer(&desc, nil, &buffer)
    }
    assert(hr == 0)

    return GpuBuffer {
        gpuBuffer = buffer,
        cpuBuffer = nil,
        length = 1,
        strideSize = desc.ByteWidth,
        itemType = T,
    }
}

updateGpuBuffer :: proc{updateGpuBuffer_SingleItem, updateGpuBuffer_ArrayItems}

updateGpuBuffer_SingleItem :: proc(data: ^$T, buffer: GpuBuffer) {
    sb: d3d11.MAPPED_SUBRESOURCE
    hr := directXState.ctx->Map(buffer.gpuBuffer, 0, d3d11.MAP.WRITE_DISCARD, {}, &sb)
    defer directXState.ctx->Unmap(buffer.gpuBuffer, 0)

    assert(hr == 0)
    mem.copy(sb.pData, data, size_of(data^))
}

updateGpuBuffer_ArrayItems :: proc(data: []$T, buffer: GpuBuffer) {
    sb: d3d11.MAPPED_SUBRESOURCE
    hr := directXState.ctx->Map(buffer.gpuBuffer, 0, d3d11.MAP.WRITE_DISCARD, {}, &sb)
    defer directXState.ctx->Unmap(buffer.gpuBuffer, 0)

    assert(hr == 0)
    mem.copy(sb.pData, raw_data(data[:]), len(data) * size_of(T))
}

createStructuredBuffer :: proc{createStructuredBuffer_InitData, createStructuredBuffer_NoInitData}

createStructuredBuffer_InitData :: proc(items: []$T) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(items) * size_of(T)),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.SHADER_RESOURCE},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(T),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(items[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC{
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
        Buffer = {
            FirstElement = 0,
            NumElements = u32(len(items)),
        },
    }

    srv: ^d3d11.IShaderResourceView
    hr = directXState->device->CreateShaderResourceView(buffer, &srvDesc, &srv)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(items),
        gpuBuffer = buffer,
        srv = srv,
        length = u32(len(items)),
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}

createStructuredBuffer_NoInitData :: proc(length: u32, $T: typeid) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = length * size_of(T),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.SHADER_RESOURCE},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(T),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, nil, &buffer)
    assert(hr == 0)

    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC{
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
        Buffer = {
            FirstElement = 0,
            NumElements = length,
        },
    }

    srv: ^d3d11.IShaderResourceView
    hr = directXState->device->CreateShaderResourceView(buffer, &srvDesc, &srv)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = nil,
        gpuBuffer = buffer,
        srv = srv,
        length = length,
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}
