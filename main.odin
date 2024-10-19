package main

import "core:text/edit"
import "core:time"
import "core:mem"
import win32 "core:sys/windows"

main :: proc() {
    when ODIN_DEBUG {
        tracker: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracker, context.allocator)
        defer mem.tracking_allocator_destroy(&tracker)
        context.allocator = mem.tracking_allocator(&tracker)
        default_context = context
    }
    createWindow({ 1920, 1080 })

    initDirectX()
    
    initGpuResources()

    windowData.clickedPoint = { f32(windowData.size.x) / 2, f32(windowData.size.y) / 2 }
    pos: float2= { f32(windowData.size.x), f32(windowData.size.y) }
    updateGpuBuffer(&pos, directXState.constantBuffers[.SCREEN_SIZE])

    msg: win32.MSG
    for msg.message != win32.WM_QUIT {
        defer free_all(context.temp_allocator)

        beforeFrame := time.tick_now()
        if win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
            win32.TranslateMessage(&msg)
            win32.DispatchMessageW(&msg)
            continue
        }

        if .LEFT_IS_DOWN in inputState.mouse {
            if isCtrlPressed() {
                windowData.clickedPoint = float2 { f32(inputState.mousePosition.x), f32(inputState.mousePosition.y) }
            } else {
                windowData.offset.x -= f32(inputState.deltaMousePosition.x) / (windowData.zoom * 500.0)
                windowData.offset.y += f32(inputState.deltaMousePosition.y) / (windowData.zoom * 500.0)
            }
        }
        setCurrentConstPosition()

        updateGpuBuffer(&windowData.offset, directXState.constantBuffers[.OFFSET])
        updateGpuBuffer(&windowData.zoom, directXState.constantBuffers[.ZOOM])
        
        render()
        windowData.delta = time.duration_seconds(time.tick_diff(beforeFrame, time.tick_now()))

        inputState.mouse -= {.LEFT_WAS_DOWN, .LEFT_WAS_UP }
        inputState.deltaMousePosition = { 0.0, 0.0 }
    }

    removeWindowData()
    clearDirectX()
   
    when ODIN_DEBUG {
        for _, leak in tracker.allocation_map {
            fmt.printf("%v leaked %m\n", leak.location, leak.size)
        }
        for bad_free in tracker.bad_free_array {
            fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
        }

        if tracker.total_memory_allocated - tracker.total_memory_freed > 0 {        
            fmt.println("Total allocated", tracker.total_memory_allocated)
            fmt.println("Total freed", tracker.total_memory_freed)
            fmt.println("Total leaked", tracker.total_memory_allocated - tracker.total_memory_freed)
        }
    }
}