package main

import "vendor:directx/dxgi"
import "vendor:directx/d3d11"

DirectXState :: struct {
    device: ^d3d11.IDevice,
    ctx: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,
    backBuffer: ^d3d11.ITexture2D,
    backBufferView: ^d3d11.IRenderTargetView,
    depthBuffer: ^d3d11.ITexture2D,
    depthBufferView: ^d3d11.IDepthStencilView,
    rasterizerState: ^d3d11.IRasterizerState,
    depthStencilState: ^d3d11.IDepthStencilState,
    blendState: ^d3d11.IBlendState,
	samplerState: ^d3d11.ISamplerState,

    vertexBuffers: [GpuBufferType]GpuBuffer,
    indexBuffers: [GpuBufferType]GpuBuffer,
    constantBuffers: [GpuConstantBufferType]GpuBuffer,
    structuredBuffers: [GpuStructuredBufferType]GpuBuffer,

    inputLayouts: [InputLayoutType]^d3d11.IInputLayout,

    vertexShaders: [VertexShaderType]^d3d11.IVertexShader,
    pixelShaders: [PixelShaderType]^d3d11.IPixelShader,
}

directXState: DirectXState

initDirectX :: proc() {
    baseDevice: ^d3d11.IDevice
	baseDeviceContext: ^d3d11.IDeviceContext

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0,._11_1}
    deviceFlags: d3d11.CREATE_DEVICE_FLAGS

    when ODIN_DEBUG {
        deviceFlags += {.DEBUG}
    }

    tmpFactory: ^dxgi.IFactory6
    res := dxgi.CreateDXGIFactory(dxgi.IFactory_UUID, (^rawptr)(&tmpFactory))
    assert(res == 0)

    tmpAdapter: ^dxgi.IAdapter
    res = tmpFactory->EnumAdapterByGpuPreference(0, .HIGH_PERFORMANCE, dxgi.IAdapter_UUID, (^rawptr)(&tmpAdapter))

    adapterDesc: dxgi.ADAPTER_DESC
    tmpAdapter->GetDesc(&adapterDesc); // 134217728

	// res = d3d11.CreateDevice(tmpAdapter, .UNKNOWN, nil, deviceFlags, &featureLevels[0], len(featureLevels), d3d11.SDK_VERSION, &baseDevice, nil, &baseDeviceContext)
	res = d3d11.CreateDevice(nil, .HARDWARE, nil, deviceFlags, &featureLevels[0], len(featureLevels), d3d11.SDK_VERSION, &baseDevice, nil, &baseDeviceContext)
    assert(res == 0)
    defer baseDevice->Release()
    defer baseDeviceContext->Release()

    test2: d3d11.FEATURE_DATA_DOUBLES
    test := baseDevice->CheckFeatureSupport(.DOUBLES, &test2, size_of(d3d11.FEATURE_DATA_DOUBLES))

	res = baseDevice->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&directXState.device))
    assert(res == 0)

	res = baseDeviceContext->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&directXState.ctx))
    assert(res == 0)

	dxgiDevice: ^dxgi.IDevice
	res = directXState.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))
    assert(res == 0)
    defer dxgiDevice->Release()

    // dxgiAdapter: ^dxgi.IAdapter
	// res = dxgiDevice->GetAdapter(&dxgiAdapter)
    // assert(res == 0)
    // defer dxgiAdapter->Release()

	// dxgiFactory: ^dxgi.IFactory2
	// res = tmpAdapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgiFactory))
    // assert(res == 0)
    // defer tmpFactory->Release()

    swapchainDesc := dxgi.SWAP_CHAIN_DESC1{
		Width  = 0,
		Height = 0,
		Format = .R8G8B8A8_UNORM,
		Stereo = false,
		SampleDesc = {
			Count = 2,
			Quality = 0,
		},
		BufferUsage = { .RENDER_TARGET_OUTPUT },
		BufferCount = 1,
		Scaling = .STRETCH,
		SwapEffect = .DISCARD,
		// AlphaMode = .UNSPECIFIED,
		Flags = { .ALLOW_MODE_SWITCH },
	}

    fullscreenSwapchainDesc := dxgi.SWAP_CHAIN_FULLSCREEN_DESC{
        Windowed = true,
    }

    // d3d11.CreateDeviceAndSwapChain()

    assert(windowData.parentHwnd != nil)
	res = tmpFactory->CreateSwapChainForHwnd(directXState.device, windowData.parentHwnd, &swapchainDesc, &fullscreenSwapchainDesc, nil, &directXState.swapchain)
    assert(res == 0)

	res = directXState.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&directXState.backBuffer))
    assert(res == 0)

	res = directXState.device->CreateRenderTargetView(directXState.backBuffer, nil, &directXState.backBufferView)
    assert(res == 0)

    depthBufferDesc: d3d11.TEXTURE2D_DESC
	directXState.backBuffer->GetDesc(&depthBufferDesc)
    depthBufferDesc.Format = .D24_UNORM_S8_UINT
	depthBufferDesc.BindFlags = {.DEPTH_STENCIL}

	res = directXState.device->CreateTexture2D(&depthBufferDesc, nil, &directXState.depthBuffer)
    assert(res == 0)

	res = directXState.device->CreateDepthStencilView(directXState.depthBuffer, nil, &directXState.depthBufferView)
    assert(res == 0)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
        ScissorEnable = true,
	}
	res = directXState.device->CreateRasterizerState(&rasterizerDesc, &directXState.rasterizerState)
    assert(res == 0)

    samplerDesc := d3d11.SAMPLER_DESC{
        Filter = .MIN_POINT_MAG_LINEAR_MIP_POINT, // originally it was MIN_MAG_MIP_LINEAR, but for some reasons, it crops image???
        AddressU = .WRAP,
        AddressV = .WRAP,
        AddressW = .WRAP,
        ComparisonFunc = .NEVER,
        MinLOD = 0,
        MaxLOD = d3d11.FLOAT32_MAX,
    }
    res = directXState.device->CreateSamplerState(&samplerDesc, &directXState.samplerState)
    assert(res == 0)

    viewport := d3d11.VIEWPORT{
        0, 0,
        f32(depthBufferDesc.Width), f32(depthBufferDesc.Height),
        0, 1,
    }

    directXState.ctx->RSSetViewports(1, &viewport)

    depthStencilDesc := d3d11.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	directXState.device->CreateDepthStencilState(&depthStencilDesc, &directXState.depthStencilState)

    // blending
    blendTargetDesc := d3d11.RENDER_TARGET_BLEND_DESC{
        BlendEnable = true,
        SrcBlend = d3d11.BLEND.SRC_ALPHA,
        DestBlend = d3d11.BLEND.INV_SRC_ALPHA,
        BlendOp = d3d11.BLEND_OP.ADD,
        SrcBlendAlpha = d3d11.BLEND.SRC_ALPHA,
        DestBlendAlpha = d3d11.BLEND.INV_SRC_ALPHA,
        BlendOpAlpha = d3d11.BLEND_OP.ADD,
        RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
    }

    blendDesc := d3d11.BLEND_DESC{
        IndependentBlendEnable = true,
    }
    blendDesc.RenderTarget[0] = blendTargetDesc

	res = directXState->device->CreateBlendState(&blendDesc, &directXState.blendState)
    assert(res == 0)

    // directXState.swapchain->SetFullscreenState(true, nil)
}

clearDirectX :: proc() {
	directXState.swapchain->SetFullscreenState(false, nil)

    directXState.device->Release()
    directXState.ctx->Release()
    directXState.swapchain->Release()
    directXState.backBuffer->Release()
    directXState.backBufferView->Release()
    directXState.depthBuffer->Release()
    directXState.depthBufferView->Release()
    directXState.rasterizerState->Release()
    directXState.depthStencilState->Release()
    directXState.samplerState->Release()
    directXState.blendState->Release()

    for buffer in directXState.vertexBuffers {
        buffer.gpuBuffer->Release()
        free(buffer.cpuBuffer)
    }

    for buffer in directXState.indexBuffers {
        buffer.gpuBuffer->Release()
        free(buffer.cpuBuffer)
    }

    for buffer in directXState.constantBuffers {
        buffer.gpuBuffer->Release()
        if buffer.cpuBuffer != nil { free(buffer.cpuBuffer) }
    }

    for buffer in directXState.structuredBuffers {
        buffer.gpuBuffer->Release()
        buffer.srv->Release()
        if buffer.cpuBuffer != nil { free(buffer.cpuBuffer) }
    }

    for inputLayout in directXState.inputLayouts {
        inputLayout->Release()
    }

    for vertexShader in directXState.vertexShaders {
        vertexShader->Release()
    }

    for pixelShader in directXState.pixelShaders {
        pixelShader->Release()
    }

    directXState = {}
}