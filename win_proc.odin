package main

import "base:runtime"
import "core:text/edit"
import "vendor:directx/d3d11"

import win32 "core:sys/windows"

default_context: runtime.Context

winProc :: proc "system" (hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    // NOTE: it's a hack to override some context data like allocators, that might be redefined in other code 
    context = default_context
    
    switch msg {
    case win32.WM_MOUSEMOVE:
        // TODO: Is it efficient to call TrackMouseEvent all the time?
        track := win32.TRACKMOUSEEVENT{
            cbSize = size_of(win32.TRACKMOUSEEVENT),
            dwFlags = win32.TME_LEAVE,
            hwndTrack = hwnd,
        }
        win32.TrackMouseEvent(&track)

        xMouse := win32.GET_X_LPARAM(lParam)
        yMouse := win32.GET_Y_LPARAM(lParam)
        
        prevMousePosition := inputState.mousePosition
        inputState.mousePosition = { xMouse, yMouse }

        inputState.deltaMousePosition = inputState.mousePosition - prevMousePosition

    case win32.WM_LBUTTONDOWN:
        inputState.mouse += { .LEFT_IS_DOWN, .LEFT_WAS_DOWN }

        win32.SetCapture(hwnd)
    case win32.WM_LBUTTONUP:
        inputState.mouse += { .LEFT_WAS_UP }
        inputState.mouse -= { .LEFT_IS_DOWN }

        win32.ReleaseCapture()
    case win32.WM_MOUSEWHEEL:
        yoffset := win32.GET_WHEEL_DELTA_WPARAM(wParam)

        if yoffset > 1 {
            windowData.zoom /= 1.1
        } else if yoffset < -1 {
            windowData.zoom *= 1.1
        }

        windowData.zoom = max(1.0, windowData.zoom)
    case win32.WM_SIZE:
        if !windowData.windowCreated { break }

        if wParam == win32.SIZE_MINIMIZED { break }

        clientRect: win32.RECT
        win32.GetClientRect(hwnd, &clientRect)

        windowSizeChangedHandler(clientRect.right - clientRect.left, clientRect.bottom - clientRect.top)
    case win32.WM_KEYDOWN:
        handle_WM_KEYDOWN(lParam, wParam)
    case win32.WM_DESTROY:
        win32.PostQuitMessage(0)
    }

    return win32.DefWindowProcA(hwnd, msg, wParam, lParam)
}

handle_WM_KEYDOWN :: proc(lParam: win32.LPARAM, wParam: win32.WPARAM) {
    delta: f32 = 0.1 / windowData.zoom
    
    switch wParam {
    case win32.VK_LEFT: windowData.clickedPoint.x -= delta
    case win32.VK_RIGHT: windowData.clickedPoint.x += delta
    case win32.VK_UP: windowData.clickedPoint.y -= delta
    case win32.VK_DOWN: windowData.clickedPoint.y += delta

    case win32.VK_Q: windowData.zoom /= 1.01
    case win32.VK_W: windowData.zoom *= 1.01
    }
}

isCtrlPressed :: proc() -> bool {
    return uint(win32.GetKeyState(win32.VK_LCONTROL)) & 0x8000 == 0x8000
}

windowSizeChangedHandler :: proc "c" (width, height: i32) {
    context = runtime.default_context()

    windowData.size = { width, height }

    pos: float2= { f32(windowData.size.x), f32(windowData.size.y) }
    updateGpuBuffer(&pos, directXState.constantBuffers[.SCREEN_SIZE])

    directXState.ctx->OMSetRenderTargets(0, nil, nil)
    directXState.backBufferView->Release()
    directXState.backBuffer->Release()
    directXState.depthBufferView->Release()
    directXState.depthBuffer->Release()

    directXState.ctx->Flush()
    directXState.swapchain->ResizeBuffers(2, u32(width), u32(height), .R8G8B8A8_UNORM, {})

	res := directXState.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&directXState.backBuffer))
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

    viewport := d3d11.VIEWPORT{
        0, 0,
        f32(depthBufferDesc.Width), f32(depthBufferDesc.Height),
        0, 1,
    }

    directXState.ctx->RSSetViewports(1, &viewport)

    viewMatrix := getOrthoraphicsMatrix(f32(width), f32(height), 0.1, windowData.maxZIndex + 1.0)

    updateGpuBuffer(&viewMatrix, directXState.constantBuffers[.PROJECTION])
}
