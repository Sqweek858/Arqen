#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <cstdint>

struct ArqenDx12ClearColor
{
    float r;
    float g;
    float b;
    float a;
};

struct ArqenDx12VertexPositionColor
{
    float x;
    float y;
    float z;
    float r;
    float g;
    float b;
    float a;
};

struct ArqenDx12DrawCall
{
    uint32_t firstVertex;
    uint32_t vertexCount;
    uint32_t transformIndex;
};

struct ArqenDx12ObjectTransform
{
    float x;
    float y;
    float z;
    float rotationZDegrees;
    float sx;
    float sy;
    float sz;
};

struct ArqenDx12OrthographicCamera
{
    float x;
    float y;
    float z;
    float zoom;
};

struct ArqenDx12PerspectiveCamera
{
    float x;
    float y;
    float z;
    float pitchDegrees;
    float yawDegrees;
    float rollDegrees;
    float fovYDegrees;
    float nearPlane;
    float farPlane;
};

enum : uint32_t
{
    ARQEN_DX12_KEY_ACTION_MOVE_CAMERA_HELD = 1,
    ARQEN_DX12_KEY_ACTION_RESET_CAMERA_PRESSED = 2,
    ARQEN_DX12_KEY_ACTION_TOGGLE_ANIMATION_PRESSED = 3,
};

enum : uint32_t
{
    ARQEN_DX12_MOUSE_BUTTON_LEFT = 1,
    ARQEN_DX12_MOUSE_BUTTON_RIGHT = 2,
    ARQEN_DX12_MOUSE_BUTTON_MIDDLE = 3,
};

enum : uint32_t
{
    ARQEN_DX12_MOUSE_BUTTON_ACTION_MOVE_CAMERA_HELD = 1,
    ARQEN_DX12_MOUSE_BUTTON_ACTION_RESET_CAMERA_PRESSED = 2,
    ARQEN_DX12_MOUSE_BUTTON_ACTION_TOGGLE_ANIMATION_PRESSED = 3,
};

enum : uint32_t
{
    ARQEN_DX12_MOUSE_WHEEL_ACTION_MOVE_CAMERA = 1,
};

struct ArqenDx12KeyBinding
{
    uint32_t virtualKey;
    uint32_t action;
    float x;
    float y;
    float z;
};

struct ArqenDx12MouseMoveBinding
{
    float sensitivityX;
    float sensitivityY;
};

struct ArqenDx12MouseButtonBinding
{
    uint32_t button;
    uint32_t action;
    float x;
    float y;
    float z;
};

struct ArqenDx12MouseWheelBinding
{
    uint32_t action;
    float x;
    float y;
    float z;
};

struct ArqenDx12ClearWindowDesc
{
    HWND hwnd;
    uint32_t width;
    uint32_t height;
    ArqenDx12ClearColor clearColor;
    bool enableDebugLayer;
    bool waitForVSync;
    uint32_t frameCount;
    uint32_t targetFps;
};

struct ArqenDx12TriangleWindowDesc
{
    HWND hwnd;
    uint32_t width;
    uint32_t height;
    ArqenDx12ClearColor clearColor;
    bool enableDebugLayer;
    bool waitForVSync;
    const wchar_t* vertexShaderPath;
    const wchar_t* pixelShaderPath;
    const ArqenDx12VertexPositionColor* vertices;
    uint32_t vertexCount;
    uint32_t drawVertexCount;
    const ArqenDx12DrawCall* drawCalls;
    uint32_t drawCallCount;
    const ArqenDx12ObjectTransform* objectTransforms;
    uint32_t objectTransformCount;
    bool enableSceneTransforms;
    ArqenDx12OrthographicCamera camera;
    bool enableCamera;
    ArqenDx12PerspectiveCamera perspectiveCamera;
    bool enablePerspectiveCamera;
    bool enableDepth;
    const ArqenDx12KeyBinding* keyBindings;
    uint32_t keyBindingCount;
    bool enableKeyboardInput;
    bool enablePeripheralInput;
    bool enableMouseCapture;
    const ArqenDx12MouseMoveBinding* mouseMoveBindings;
    uint32_t mouseMoveBindingCount;
    const ArqenDx12MouseButtonBinding* mouseButtonBindings;
    uint32_t mouseButtonBindingCount;
    const ArqenDx12MouseWheelBinding* mouseWheelBindings;
    uint32_t mouseWheelBindingCount;
    volatile LONG* mouseWheelDelta;
    bool enableTint;
    ArqenDx12ClearColor tintColor;
    const ArqenDx12ClearColor* animationColors;
    uint32_t animationColorCount;
    uint32_t animationEveryFrames;
    uint32_t frameCount;
    uint32_t targetFps;
};

struct ArqenDx12ClearWindowResult
{
    HRESULT hr;
    char stage[64];
    char message[384];
};

extern "C" __declspec(dllexport)
bool ArqenDx12ClearWindowOnce(
    const ArqenDx12ClearWindowDesc* desc,
    ArqenDx12ClearWindowResult* result);

extern "C" __declspec(dllexport)
bool ArqenDx12ClearWindowRunFrames(
    const ArqenDx12ClearWindowDesc* desc,
    ArqenDx12ClearWindowResult* result);

extern "C" __declspec(dllexport)
bool ArqenDx12TriangleWindowOnce(
    const ArqenDx12TriangleWindowDesc* desc,
    ArqenDx12ClearWindowResult* result);

extern "C" __declspec(dllexport)
bool ArqenDx12TriangleWindowRunFrames(
    const ArqenDx12TriangleWindowDesc* desc,
    ArqenDx12ClearWindowResult* result);
