#include "ArqenDx12ClearWindow.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <cstdio>

namespace
{
    LRESULT CALLBACK SmokeWndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
    {
        switch (msg)
        {
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        }
    }
}

int main()
{
    HINSTANCE hInstance = GetModuleHandleW(nullptr);
    const wchar_t* className = L"ArqenM20ADx12SmokeWindow";

    WNDCLASSW wc = {};
    wc.lpfnWndProc = SmokeWndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = className;

    if (!RegisterClassW(&wc))
        return 10;

    const UINT width = 960;
    const UINT height = 540;
    HWND hwnd = CreateWindowExW(
        0,
        className,
        L"Arqen M20A DX12 Clear Smoke",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        static_cast<int>(width),
        static_cast<int>(height),
        nullptr,
        nullptr,
        hInstance,
        nullptr);

    if (!hwnd)
        return 11;

    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);

    ArqenDx12ClearWindowDesc desc = {};
    desc.hwnd = hwnd;
    desc.width = width;
    desc.height = height;
    desc.clearColor = { 0.02f, 0.08f, 0.07f, 1.0f };
    desc.enableDebugLayer = true;
    desc.waitForVSync = true;

    ArqenDx12ClearWindowResult result = {};
    if (!ArqenDx12ClearWindowOnce(&desc, &result))
    {
        char buffer[512] = {};
        std::snprintf(buffer, sizeof(buffer), "DX12 clear failed at %s\n%s\nHRESULT=0x%08X", result.stage, result.message, static_cast<unsigned>(result.hr));
        MessageBoxA(hwnd, buffer, "Arqen M20A DX12 Smoke", MB_ICONERROR | MB_OK);
        return 12;
    }

    const DWORD start = GetTickCount();
    MSG msg = {};
    while (GetTickCount() - start < 1600)
    {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT)
                return 0;
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        Sleep(16);
    }

    DestroyWindow(hwnd);
    return 0;
}
