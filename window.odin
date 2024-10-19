package main

import "core:strings"
import "core:text/edit"

import win32 "core:sys/windows"

MouseStates :: bit_set[MouseState]

MouseState :: enum {
    LEFT_IS_DOWN,
    LEFT_WAS_DOWN,
    LEFT_WAS_UP,
}

InputState :: struct {
    mousePosition: int2,
    deltaMousePosition: int2,
    mouse: MouseStates,
}

inputState: InputState

WindowData :: struct {
    windowCreated: bool,
    parentHwnd: win32.HWND,

    delta: f64,
    size: int2,

    maxZIndex: f32,

    clickedPoint: float2,
    offset: float2,
    zoom: f32,
}

windowData: WindowData

createWindow :: proc(size: int2) {
    hInstance := win32.HINSTANCE(win32.GetModuleHandleA(nil))
    
    wndClassName := win32.utf8_to_wstring("class")
    
    resourceIcon := win32.LoadImageW(hInstance, win32.MAKEINTRESOURCEW(IDI_ICON), 
        win32.IMAGE_ICON, 256, 256, win32.LR_DEFAULTCOLOR)
    
    wndClass: win32.WNDCLASSEXW = {
        cbSize = size_of(win32.WNDCLASSEXW),
        hInstance = hInstance,
        lpszClassName = wndClassName,
        lpfnWndProc = winProc,
        hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
        hIcon = (win32.HICON)(resourceIcon),
    }
    res := win32.RegisterClassExW(&wndClass)
   
    assert(res != 0, fmt.tprintfln("Error: %i", win32.GetLastError()))
    // defer win32.UnregisterClassW(wndClassName, hInstance)

    // TODO: is it good approach?
    win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_SYSTEM_AWARE)
    
    // TODO: it won't work with utf-16 symbols in the title
    windowTitle := "Mandelwrot"
    
    hwnd := win32.CreateWindowExW(
        0,
        wndClassName,
        cast([^]u16)raw_data(windowTitle),
        win32.WS_OVERLAPPEDWINDOW | win32.CS_DBLCLKS,
        win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 
        size.x, size.y,
        nil, nil,
        hInstance,
        nil,
    )

    assert(hwnd != nil)

    //> set instance window show without fade in transition
    attrib: u32 = 1
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_TRANSITIONS_FORCEDISABLED), &attrib, size_of(u32))
    //<

    //> set window dark mode
    attrib = 1
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE), &attrib, size_of(u32))
    darkColor: win32.COLORREF = 0x00505050
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_BORDER_COLOR), &darkColor, size_of(win32.COLORREF))
    //<

    win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT)

    clientRect: win32.RECT
    win32.GetClientRect(hwnd, &clientRect)

    windowData.size = { clientRect.right - clientRect.left, clientRect.bottom - clientRect.top }

    windowData.zoom = 1.0
    windowData.offset = { 0.0, 0.0 }

    windowData.parentHwnd = hwnd

    windowData.maxZIndex = 100.0

    windowData.windowCreated = true
}

removeWindowData :: proc() {
    // TODO: investigate, is this code block is needed
    //>
    win32.DestroyWindow(windowData.parentHwnd)

    res := win32.UnregisterClassW(win32.utf8_to_wstring("class"), win32.HINSTANCE(win32.GetModuleHandleA(nil)))
    assert(bool(res), fmt.tprintfln("Error: %i", win32.GetLastError()))
    //<

    windowData = {}
}

setCurrentConstPosition :: proc() {
    pos: float2 = { 4 * windowData.clickedPoint.x / f32(windowData.size.x) - 2, 4 * windowData.clickedPoint.y / f32(windowData.size.y) - 2 }

    updateGpuBuffer(&pos, directXState.constantBuffers[.MOUSE_POSITION])
}

