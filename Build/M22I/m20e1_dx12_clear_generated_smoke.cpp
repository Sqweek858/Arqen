#include "ArqenDx12ClearWindow.h"
#include "dx12_clear_config.generated.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <cstdio>
#include <cwchar>
#include <string>

namespace
{
    LRESULT CALLBACK M20E1WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
    {
        switch (msg)
        {
        case WM_ERASEBKGND:
            return 1;
        case WM_KEYDOWN:
            if (wparam == VK_ESCAPE || wparam == 'Q')
            {
                DestroyWindow(hwnd);
                return 0;
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        }
    }

    std::wstring GetExeDirectory()
    {
        wchar_t path[MAX_PATH] = {};
        DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
        if (length == 0 || length >= MAX_PATH)
            return L".";

        wchar_t* lastSlash = std::wcsrchr(path, L'\\');
        if (!lastSlash)
            return L".";
        *lastSlash = L'\0';
        return std::wstring(path);
    }

    std::wstring JoinPath(const std::wstring& dir, const std::wstring& leaf)
    {
        if (dir.empty())
            return leaf;
        if (dir.back() == L'\\' || dir.back() == L'/')
            return dir + leaf;
        return dir + L"\\" + leaf;
    }

    bool FileExists(const std::wstring& path)
    {
        const DWORD attr = GetFileAttributesW(path.c_str());
        return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
    }

    std::wstring FileNameOf(const wchar_t* path)
    {
        if (!path || path[0] == L'\0')
            return L"";
        const wchar_t* slash = std::wcsrchr(path, L'\\');
        const wchar_t* fslash = std::wcsrchr(path, L'/');
        const wchar_t* last = slash && fslash ? (slash > fslash ? slash : fslash) : (slash ? slash : fslash);
        return last ? std::wstring(last + 1) : std::wstring(path);
    }

    std::wstring ResolveShaderPath(const wchar_t* configuredPath)
    {
        if (configuredPath && configuredPath[0] != L'\0' && FileExists(configuredPath))
            return std::wstring(configuredPath);

        const std::wstring exeDir = GetExeDirectory();
        const std::wstring fallback = JoinPath(JoinPath(exeDir, L"Shaders"), FileNameOf(configuredPath));
        if (FileExists(fallback))
            return fallback;

        return configuredPath ? std::wstring(configuredPath) : std::wstring();
    }

    std::wstring LogPath()
    {
        return JoinPath(GetExeDirectory(), L"arqen_dx12_runtime.log");
    }

    void AppendLog(const char* line)
    {
        FILE* file = nullptr;
        if (_wfopen_s(&file, LogPath().c_str(), L"ab") != 0 || !file)
            return;
        std::fprintf(file, "%s\n", line ? line : "");
        std::fclose(file);
    }

    void AppendResultLog(const char* prefix, const ArqenDx12ClearWindowResult& result)
    {
        char buffer[720] = {};
        std::snprintf(buffer, sizeof(buffer), "%s stage=%s hr=0x%08X message=%s", prefix, result.stage, static_cast<unsigned>(result.hr), result.message);
        AppendLog(buffer);
    }

    int FailWithMessage(HWND hwnd, const char* title, const char* prefix, const ArqenDx12ClearWindowResult& result, int exitCode)
    {
        AppendResultLog(prefix, result);
        char buffer[760] = {};
        std::snprintf(buffer, sizeof(buffer), "%s failed at %s\n%s\nHRESULT=0x%08X\n\nLog: arqen_dx12_runtime.log", prefix, result.stage, result.message, static_cast<unsigned>(result.hr));
        MessageBoxA(hwnd, buffer, title, MB_ICONERROR | MB_OK);
        return exitCode;
    }
}

int main()
{
    AppendLog("START Arqen generated DX12 smoke executable");
    HINSTANCE hInstance = GetModuleHandleW(nullptr);
    const wchar_t* className = L"ArqenM20E1Dx12GeneratedClearWindow";

    WNDCLASSW wc = {};
    wc.lpfnWndProc = M20E1WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = className;
    wc.hbrBackground = nullptr;

    if (!RegisterClassW(&wc))
    {
        AppendLog("FAIL RegisterClassW");
        return 20;
    }

    HWND hwnd = CreateWindowExW(
        0,
        className,
        ARQEN_M20E1_WINDOW_TITLE,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        static_cast<int>(ARQEN_M20E1_WINDOW_WIDTH),
        static_cast<int>(ARQEN_M20E1_WINDOW_HEIGHT),
        nullptr,
        nullptr,
        hInstance,
        nullptr);

    if (!hwnd)
    {
        AppendLog("FAIL CreateWindowExW");
        return 21;
    }

    ShowWindow(hwnd, SW_SHOWNORMAL);
    UpdateWindow(hwnd);

    MSG warmup = {};
    while (PeekMessageW(&warmup, nullptr, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&warmup);
        DispatchMessageW(&warmup);
    }

    ArqenDx12ClearWindowResult result = {};

#if ARQEN_M21D_TRIANGLE_ENABLED
    const ArqenDx12VertexPositionColor vertices[] = ARQEN_M21C_VERTEX_DATA;
    const ArqenDx12ClearColor tintColor = ARQEN_M21G_TINT_COLOR;
    const ArqenDx12ClearColor animationColors[] = ARQEN_M21H_COLOR_DATA;
    const std::wstring vertexShaderPath = ResolveShaderPath(ARQEN_M21B_VERTEX_SHADER_PATH);
    const std::wstring pixelShaderPath = ResolveShaderPath(ARQEN_M21B_PIXEL_SHADER_PATH);

    if (!FileExists(vertexShaderPath) || !FileExists(pixelShaderPath))
    {
        AppendLog("FAIL shader path fallback");
        MessageBoxA(hwnd, "M21D shader source file was not found. Check arqen_dx12_runtime.log and Build/EXE/Shaders.", "Arqen M21D DX12 Triangle", MB_ICONERROR | MB_OK);
        return 24;
    }

    ArqenDx12TriangleWindowDesc triangleDesc = {};
    triangleDesc.hwnd = hwnd;
    triangleDesc.width = ARQEN_M20E1_WINDOW_WIDTH;
    triangleDesc.height = ARQEN_M20E1_WINDOW_HEIGHT;
    triangleDesc.clearColor = { ARQEN_M20E1_CLEAR_R, ARQEN_M20E1_CLEAR_G, ARQEN_M20E1_CLEAR_B, ARQEN_M20E1_CLEAR_A };
    triangleDesc.enableDebugLayer = true;
    triangleDesc.waitForVSync = true;
    triangleDesc.vertexShaderPath = vertexShaderPath.c_str();
    triangleDesc.pixelShaderPath = pixelShaderPath.c_str();
    triangleDesc.vertices = vertices;
    triangleDesc.vertexCount = ARQEN_M21C_VERTEX_COUNT;
    triangleDesc.drawVertexCount = ARQEN_M21C_DRAW_VERTEX_COUNT;
    triangleDesc.enableTint = ARQEN_M21G_TINT_ENABLED != 0;
    triangleDesc.tintColor = tintColor;
    triangleDesc.animationColors = ARQEN_M21H_COLOR_ANIMATION_ENABLED ? animationColors : nullptr;
    triangleDesc.animationColorCount = ARQEN_M21H_COLOR_ANIMATION_ENABLED ? ARQEN_M21H_COLOR_COUNT : 0;
    triangleDesc.animationEveryFrames = ARQEN_M21H_COLOR_EVERY_FRAMES;
    triangleDesc.frameCount = ARQEN_M21F_FRAME_COUNT;
    triangleDesc.targetFps = ARQEN_M21F_TARGET_FPS;

#if ARQEN_M21F_FRAME_LOOP_ENABLED
    if (!ArqenDx12TriangleWindowRunFrames(&triangleDesc, &result))
#else
    if (!ArqenDx12TriangleWindowOnce(&triangleDesc, &result))
#endif
    {
        return FailWithMessage(hwnd, "Arqen M21D DX12 Triangle", "M21D DX12 triangle", result, 23);
    }
#else
    ArqenDx12ClearWindowDesc desc = {};
    desc.hwnd = hwnd;
    desc.width = ARQEN_M20E1_WINDOW_WIDTH;
    desc.height = ARQEN_M20E1_WINDOW_HEIGHT;
    desc.clearColor = { ARQEN_M20E1_CLEAR_R, ARQEN_M20E1_CLEAR_G, ARQEN_M20E1_CLEAR_B, ARQEN_M20E1_CLEAR_A };
    desc.enableDebugLayer = true;
    desc.waitForVSync = true;
    desc.frameCount = ARQEN_M21F_FRAME_COUNT;
    desc.targetFps = ARQEN_M21F_TARGET_FPS;

#if ARQEN_M21F_FRAME_LOOP_ENABLED
    if (!ArqenDx12ClearWindowRunFrames(&desc, &result))
#else
    if (!ArqenDx12ClearWindowOnce(&desc, &result))
#endif
    {
        return FailWithMessage(hwnd, "Arqen M20E1 DX12 Clear", "M20E1 DX12 clear", result, 22);
    }
#endif

    AppendResultLog("PASS generated DX12 smoke", result);
    if (IsWindow(hwnd))
        DestroyWindow(hwnd);
    return 0;
}