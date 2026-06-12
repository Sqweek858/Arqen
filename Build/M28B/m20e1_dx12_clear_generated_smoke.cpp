#include "ArqenDx12ClearWindow.h"
#include "dx12_clear_config.generated.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <dwmapi.h>
#include <cstdio>
#include <cwchar>
#include <cstring>
#include <string>


#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

namespace
{
    bool ParseHexColorRef(const char* hex, COLORREF* out)
    {
        if (!hex || !out || hex[0] != '#' || std::strlen(hex) != 7)
            return false;
        auto nibble = [](char c) -> int
        {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return 10 + c - 'a';
            if (c >= 'A' && c <= 'F') return 10 + c - 'A';
            return -1;
        };
        const int r0 = nibble(hex[1]); const int r1 = nibble(hex[2]);
        const int g0 = nibble(hex[3]); const int g1 = nibble(hex[4]);
        const int b0 = nibble(hex[5]); const int b1 = nibble(hex[6]);
        if (r0 < 0 || r1 < 0 || g0 < 0 || g1 < 0 || b0 < 0 || b1 < 0)
            return false;
        *out = RGB((r0 << 4) | r1, (g0 << 4) | g1, (b0 << 4) | b1);
        return true;
    }

    void ApplyM27DNativeWindowStyle(HWND hwnd)
    {
        if (!hwnd)
            return;
#if ARQEN_M27D_TITLE_BAR_ENABLED || ARQEN_M27D_TITLE_TEXT_ENABLED
        BOOL dark = TRUE;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
#endif
#if ARQEN_M27D_TITLE_BAR_ENABLED
        COLORREF caption = RGB(0, 0, 0);
        if (ParseHexColorRef(ARQEN_M27D_TITLE_BAR_COLOR, &caption))
            DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
#endif
#if ARQEN_M27D_TITLE_TEXT_ENABLED
        COLORREF text = RGB(255, 255, 255);
        if (ParseHexColorRef(ARQEN_M27D_TITLE_TEXT_COLOR, &text))
            DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, &text, sizeof(text));
#endif
    }
}

namespace
{
    volatile LONG gArqenM28BMouseWheelDelta = 0;

    LRESULT CALLBACK M20E1WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
    {
        switch (msg)
        {
        case WM_ERASEBKGND:
            return 1;
        case WM_KEYDOWN:
            if (wparam == VK_ESCAPE || (ARQEN_M28B_PERIPHERAL_INPUT_ENABLED == 0 && wparam == 'Q'))
            {
                DestroyWindow(hwnd);
                return 0;
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam);
        case WM_MOUSEWHEEL:
            InterlockedExchangeAdd(&gArqenM28BMouseWheelDelta, GET_WHEEL_DELTA_WPARAM(wparam));
            return 0;
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

    ApplyM27DNativeWindowStyle(hwnd);
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
    const ArqenDx12DrawCall drawCalls[] = ARQEN_M23_DRAW_CALL_DATA;
    const ArqenDx12ObjectTransform objectTransforms[] = ARQEN_M24_OBJECT_TRANSFORM_DATA;
    const ArqenDx12OrthographicCamera camera = ARQEN_M25_CAMERA_DATA;
    const ArqenDx12PerspectiveCamera perspectiveCamera = ARQEN_M27_PERSPECTIVE_CAMERA_DATA;
    const ArqenDx12KeyBinding keyBindings[] = ARQEN_M26_KEY_BINDING_DATA;
    const ArqenDx12MouseMoveBinding mouseMoveBindings[] = ARQEN_M28B_MOUSE_MOVE_BINDING_DATA;
    const ArqenDx12MouseButtonBinding mouseButtonBindings[] = ARQEN_M28B_MOUSE_BUTTON_BINDING_DATA;
    const ArqenDx12MouseWheelBinding mouseWheelBindings[] = ARQEN_M28B_MOUSE_WHEEL_BINDING_DATA;
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
    triangleDesc.drawCalls = drawCalls;
    triangleDesc.drawCallCount = ARQEN_M23_DRAW_CALL_COUNT;
    triangleDesc.objectTransforms = objectTransforms;
    triangleDesc.objectTransformCount = ARQEN_M24_OBJECT_TRANSFORM_COUNT;
    triangleDesc.enableSceneTransforms = ARQEN_M24_TRANSFORM_RUNTIME_ENABLED != 0;
    triangleDesc.camera = camera;
    triangleDesc.enableCamera = ARQEN_M25_CAMERA_ENABLED != 0;
    triangleDesc.perspectiveCamera = perspectiveCamera;
    triangleDesc.enablePerspectiveCamera = ARQEN_M27_PERSPECTIVE_CAMERA_ENABLED != 0;
    triangleDesc.enableDepth = ARQEN_M27_DEPTH_BUFFER_ENABLED != 0;
    triangleDesc.keyBindings = keyBindings;
    triangleDesc.keyBindingCount = ARQEN_M26_KEY_BINDING_COUNT;
    triangleDesc.enableKeyboardInput = ARQEN_M26_KEYBOARD_INPUT_ENABLED != 0;
    triangleDesc.enablePeripheralInput = ARQEN_M28B_PERIPHERAL_INPUT_ENABLED != 0;
    triangleDesc.enableMouseCapture = ARQEN_M28B_MOUSE_CAPTURE_ENABLED != 0;
    triangleDesc.mouseMoveBindings = mouseMoveBindings;
    triangleDesc.mouseMoveBindingCount = ARQEN_M28B_MOUSE_MOVE_BINDING_COUNT;
    triangleDesc.mouseButtonBindings = mouseButtonBindings;
    triangleDesc.mouseButtonBindingCount = ARQEN_M28B_MOUSE_BUTTON_BINDING_COUNT;
    triangleDesc.mouseWheelBindings = mouseWheelBindings;
    triangleDesc.mouseWheelBindingCount = ARQEN_M28B_MOUSE_WHEEL_BINDING_COUNT;
    triangleDesc.mouseWheelDelta = &gArqenM28BMouseWheelDelta;
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