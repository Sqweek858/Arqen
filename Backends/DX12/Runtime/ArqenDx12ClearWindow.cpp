#include "ArqenDx12ClearWindow.h"

#include <d3d12.h>
#include <d3dcompiler.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstring>
#include <climits>
#include <limits>
#include <cmath>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

namespace
{
    constexpr UINT FrameCount = 2;

    void SetResult(ArqenDx12ClearWindowResult* result, HRESULT hr, const char* stage, const char* message)
    {
        if (!result)
            return;

        result->hr = hr;
        std::snprintf(result->stage, sizeof(result->stage), "%s", stage ? stage : "unknown");
        std::snprintf(result->message, sizeof(result->message), "%s", message ? message : "");
    }

    bool Fail(ArqenDx12ClearWindowResult* result, HRESULT hr, const char* stage, const char* call)
    {
        char buffer[320] = {};
        std::snprintf(buffer, sizeof(buffer), "%s failed with HRESULT 0x%08X", call, static_cast<unsigned>(hr));
        SetResult(result, hr, stage, buffer);
        return false;
    }

    bool FailMessage(ArqenDx12ClearWindowResult* result, HRESULT hr, const char* stage, const char* message)
    {
        SetResult(result, hr, stage, message);
        return false;
    }

    bool Failed(HRESULT hr)
    {
        return FAILED(hr);
    }

    UINT EffectiveFrameCount(UINT frameCount)
    {
        return frameCount == 0 ? 1u : frameCount;
    }

    bool IsInfiniteFrameCount(UINT frameCount)
    {
        return frameCount == 0;
    }

    UINT EffectiveTargetFps(UINT targetFps)
    {
        return targetFps == 0 ? 60u : targetFps;
    }

    float ClampFloat(float value, float minValue, float maxValue)
    {
        return value < minValue ? minValue : (value > maxValue ? maxValue : value);
    }

    bool PumpWindowMessages(bool* quit)
    {
        MSG msg = {};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE))
        {
            if (msg.message == WM_QUIT)
            {
                if (quit)
                    *quit = true;
                return true;
            }

            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        return true;
    }

    void SleepToTargetFrame(DWORD frameStart, UINT targetFps)
    {
        const UINT fps = EffectiveTargetFps(targetFps);
        const DWORD targetMs = fps > 0 ? static_cast<DWORD>(1000u / fps) : 0u;
        if (targetMs == 0)
            return;

        const DWORD elapsed = GetTickCount() - frameStart;
        if (elapsed < targetMs)
            Sleep(targetMs - elapsed);
    }

    D3D12_RESOURCE_DESC BufferResourceDesc(UINT64 byteSize)
    {
        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Alignment = 0;
        desc.Width = byteSize;
        desc.Height = 1;
        desc.DepthOrArraySize = 1;
        desc.MipLevels = 1;
        desc.Format = DXGI_FORMAT_UNKNOWN;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        desc.Flags = D3D12_RESOURCE_FLAG_NONE;
        return desc;
    }

    D3D12_HEAP_PROPERTIES UploadHeapProperties()
    {
        D3D12_HEAP_PROPERTIES props = {};
        props.Type = D3D12_HEAP_TYPE_UPLOAD;
        props.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        props.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
        props.CreationNodeMask = 1;
        props.VisibleNodeMask = 1;
        return props;
    }

    D3D12_HEAP_PROPERTIES DefaultHeapProperties()
    {
        D3D12_HEAP_PROPERTIES props = {};
        props.Type = D3D12_HEAP_TYPE_DEFAULT;
        props.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        props.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
        props.CreationNodeMask = 1;
        props.VisibleNodeMask = 1;
        return props;
    }

    D3D12_RESOURCE_DESC DepthResourceDesc(UINT width, UINT height)
    {
        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Alignment = 0;
        desc.Width = width;
        desc.Height = height;
        desc.DepthOrArraySize = 1;
        desc.MipLevels = 1;
        desc.Format = DXGI_FORMAT_D32_FLOAT;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
        desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL;
        return desc;
    }

    class Dx12ClearContext
    {
    public:
        bool Initialize(HWND hwnd, UINT width, UINT height, bool enableDebugLayer, ArqenDx12ClearWindowResult* result)
        {
            if (!hwnd)
            {
                SetResult(result, E_INVALIDARG, "validate", "HWND handoff is required for DX12 clear/triangle smoke.");
                return false;
            }

            if (width == 0 || height == 0)
            {
                SetResult(result, E_INVALIDARG, "validate", "DX12 window width and height must be non-zero.");
                return false;
            }

            hwnd_ = hwnd;
            width_ = width;
            height_ = height;

            UINT factoryFlags = 0;
            if (enableDebugLayer)
            {
                ComPtr<ID3D12Debug> debug;
                if (SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(&debug))))
                {
                    debug->EnableDebugLayer();
                    factoryFlags |= DXGI_CREATE_FACTORY_DEBUG;
                }
            }

            HRESULT hr = CreateDXGIFactory2(factoryFlags, IID_PPV_ARGS(&factory_));
            if (Failed(hr))
                return Fail(result, hr, "factory", "CreateDXGIFactory2");

            hr = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device_));
            if (Failed(hr))
                return Fail(result, hr, "device", "D3D12CreateDevice");

            D3D12_COMMAND_QUEUE_DESC queueDesc = {};
            queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
            queueDesc.Priority = D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
            queueDesc.Flags = D3D12_COMMAND_QUEUE_FLAG_NONE;
            queueDesc.NodeMask = 0;

            hr = device_->CreateCommandQueue(&queueDesc, IID_PPV_ARGS(&queue_));
            if (Failed(hr))
                return Fail(result, hr, "command_queue", "ID3D12Device::CreateCommandQueue");

            DXGI_SWAP_CHAIN_DESC1 swapDesc = {};
            swapDesc.Width = width;
            swapDesc.Height = height;
            swapDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
            swapDesc.Stereo = FALSE;
            swapDesc.SampleDesc.Count = 1;
            swapDesc.SampleDesc.Quality = 0;
            swapDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
            swapDesc.BufferCount = FrameCount;
            swapDesc.Scaling = DXGI_SCALING_STRETCH;
            swapDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
            swapDesc.AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
            swapDesc.Flags = 0;

            ComPtr<IDXGISwapChain1> swapChain1;
            hr = factory_->CreateSwapChainForHwnd(queue_.Get(), hwnd, &swapDesc, nullptr, nullptr, &swapChain1);
            if (Failed(hr))
                return Fail(result, hr, "swapchain", "IDXGIFactory::CreateSwapChainForHwnd");

            factory_->MakeWindowAssociation(hwnd, DXGI_MWA_NO_ALT_ENTER);

            hr = swapChain1.As(&swapChain_);
            if (Failed(hr))
                return Fail(result, hr, "swapchain", "IDXGISwapChain1::QueryInterface IDXGISwapChain3");

            frameIndex_ = swapChain_->GetCurrentBackBufferIndex();

            D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc = {};
            rtvHeapDesc.NumDescriptors = FrameCount;
            rtvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
            rtvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;

            hr = device_->CreateDescriptorHeap(&rtvHeapDesc, IID_PPV_ARGS(&rtvHeap_));
            if (Failed(hr))
                return Fail(result, hr, "rtv_heap", "ID3D12Device::CreateDescriptorHeap");

            rtvDescriptorSize_ = device_->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

            D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = rtvHeap_->GetCPUDescriptorHandleForHeapStart();
            for (UINT i = 0; i < FrameCount; ++i)
            {
                hr = swapChain_->GetBuffer(i, IID_PPV_ARGS(&renderTargets_[i]));
                if (Failed(hr))
                    return Fail(result, hr, "backbuffer", "IDXGISwapChain::GetBuffer");

                device_->CreateRenderTargetView(renderTargets_[i].Get(), nullptr, rtvHandle);
                rtvHandle.ptr += rtvDescriptorSize_;
            }

            hr = device_->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator_));
            if (Failed(hr))
                return Fail(result, hr, "command_allocator", "ID3D12Device::CreateCommandAllocator");

            hr = device_->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator_.Get(), nullptr, IID_PPV_ARGS(&commandList_));
            if (Failed(hr))
                return Fail(result, hr, "command_list", "ID3D12Device::CreateCommandList");

            hr = commandList_->Close();
            if (Failed(hr))
                return Fail(result, hr, "command_list", "ID3D12GraphicsCommandList::Close initial");

            hr = device_->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence_));
            if (Failed(hr))
                return Fail(result, hr, "fence", "ID3D12Device::CreateFence");

            fenceValue_ = 1;
            fenceEvent_ = CreateEventW(nullptr, FALSE, FALSE, nullptr);
            if (!fenceEvent_)
            {
                SetResult(result, HRESULT_FROM_WIN32(GetLastError()), "fence", "CreateEventW failed.");
                return false;
            }

            return true;
        }

        bool CreateTriangleResources(const ArqenDx12TriangleWindowDesc& desc, ArqenDx12ClearWindowResult* result)
        {
            if (!desc.vertexShaderPath || !desc.pixelShaderPath)
                return FailMessage(result, E_INVALIDARG, "validate", "M21D triangle smoke requires vertex and pixel shader paths.");
            if (!desc.vertices || desc.vertexCount < 3)
                return FailMessage(result, E_INVALIDARG, "validate", "M21D triangle smoke requires at least three generated vertices.");
            const bool hasDrawCalls = desc.drawCalls != nullptr && desc.drawCallCount > 0;
            if (!hasDrawCalls && (desc.drawVertexCount < 3 || desc.drawVertexCount > desc.vertexCount))
                return FailMessage(result, E_INVALIDARG, "validate", "M21D draw vertex count must be between 3 and generated vertex count.");
            depthEnabled_ = desc.enableDepth;
            perspectiveCameraEnabled_ = desc.enablePerspectiveCamera;
            perspectiveCamera_ = desc.perspectiveCamera;
            initialPerspectiveCamera_ = desc.perspectiveCamera;

            if (hasDrawCalls)
            {
                for (uint32_t i = 0; i < desc.drawCallCount; ++i)
                {
                    const ArqenDx12DrawCall& drawCall = desc.drawCalls[i];
                    if (drawCall.vertexCount < 3)
                        return FailMessage(result, E_INVALIDARG, "validate", "M23C draw call vertex count must be at least 3.");
                    if (drawCall.firstVertex >= desc.vertexCount || drawCall.vertexCount > desc.vertexCount - drawCall.firstVertex)
                        return FailMessage(result, E_INVALIDARG, "validate", "M23C draw call range exceeds generated vertex buffer.");
                    if (desc.enableSceneTransforms && desc.objectTransforms && desc.objectTransformCount > 0 && drawCall.transformIndex >= desc.objectTransformCount)
                        return FailMessage(result, E_INVALIDARG, "validate", "M24 draw call transform index exceeds generated transform table.");
                }
            }

            UINT shaderFlags = D3DCOMPILE_ENABLE_STRICTNESS;
#if defined(_DEBUG)
            shaderFlags |= D3DCOMPILE_DEBUG;
#endif

            ComPtr<ID3DBlob> errorBlob;
            HRESULT hr = D3DCompileFromFile(desc.vertexShaderPath, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE, "VSMain", "vs_5_0", shaderFlags, 0, &vertexShader_, &errorBlob);
            if (Failed(hr))
                return ShaderFail(result, hr, "vertex_shader", "D3DCompileFromFile vertex", errorBlob.Get());

            errorBlob.Reset();
            hr = D3DCompileFromFile(desc.pixelShaderPath, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE, "PSMain", "ps_5_0", shaderFlags, 0, &pixelShader_, &errorBlob);
            if (Failed(hr))
                return ShaderFail(result, hr, "pixel_shader", "D3DCompileFromFile pixel", errorBlob.Get());

            D3D12_ROOT_PARAMETER rootParameters[1] = {};
            D3D12_ROOT_SIGNATURE_DESC rootDesc = {};
            if (desc.enableTint)
            {
                rootParameters[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
                rootParameters[0].Descriptor.ShaderRegister = 0;
                rootParameters[0].Descriptor.RegisterSpace = 0;
                rootParameters[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
                rootDesc.NumParameters = 1;
                rootDesc.pParameters = rootParameters;
            }
            else
            {
                rootDesc.NumParameters = 0;
                rootDesc.pParameters = nullptr;
            }
            rootDesc.NumStaticSamplers = 0;
            rootDesc.pStaticSamplers = nullptr;
            rootDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;

            ComPtr<ID3DBlob> signature;
            errorBlob.Reset();
            hr = D3D12SerializeRootSignature(&rootDesc, D3D_ROOT_SIGNATURE_VERSION_1, &signature, &errorBlob);
            if (Failed(hr))
                return ShaderFail(result, hr, "root_signature", "D3D12SerializeRootSignature", errorBlob.Get());

            hr = device_->CreateRootSignature(0, signature->GetBufferPointer(), signature->GetBufferSize(), IID_PPV_ARGS(&rootSignature_));
            if (Failed(hr))
                return Fail(result, hr, "root_signature", "ID3D12Device::CreateRootSignature");

            D3D12_INPUT_ELEMENT_DESC inputElements[] =
            {
                { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
                { "COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 12, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            };

            D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = {};
            psoDesc.InputLayout = { inputElements, static_cast<UINT>(sizeof(inputElements) / sizeof(inputElements[0])) };
            psoDesc.pRootSignature = rootSignature_.Get();
            psoDesc.VS = { vertexShader_->GetBufferPointer(), vertexShader_->GetBufferSize() };
            psoDesc.PS = { pixelShader_->GetBufferPointer(), pixelShader_->GetBufferSize() };
            psoDesc.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
            psoDesc.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
            psoDesc.RasterizerState.FrontCounterClockwise = FALSE;
            psoDesc.RasterizerState.DepthBias = D3D12_DEFAULT_DEPTH_BIAS;
            psoDesc.RasterizerState.DepthBiasClamp = D3D12_DEFAULT_DEPTH_BIAS_CLAMP;
            psoDesc.RasterizerState.SlopeScaledDepthBias = D3D12_DEFAULT_SLOPE_SCALED_DEPTH_BIAS;
            psoDesc.RasterizerState.DepthClipEnable = TRUE;
            psoDesc.BlendState.AlphaToCoverageEnable = FALSE;
            psoDesc.BlendState.IndependentBlendEnable = FALSE;
            psoDesc.BlendState.RenderTarget[0].BlendEnable = FALSE;
            psoDesc.BlendState.RenderTarget[0].LogicOpEnable = FALSE;
            psoDesc.BlendState.RenderTarget[0].SrcBlend = D3D12_BLEND_ONE;
            psoDesc.BlendState.RenderTarget[0].DestBlend = D3D12_BLEND_ZERO;
            psoDesc.BlendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
            psoDesc.BlendState.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
            psoDesc.BlendState.RenderTarget[0].DestBlendAlpha = D3D12_BLEND_ZERO;
            psoDesc.BlendState.RenderTarget[0].BlendOpAlpha = D3D12_BLEND_OP_ADD;
            psoDesc.BlendState.RenderTarget[0].LogicOp = D3D12_LOGIC_OP_NOOP;
            psoDesc.BlendState.RenderTarget[0].RenderTargetWriteMask = static_cast<UINT8>(D3D12_COLOR_WRITE_ENABLE_ALL);
            psoDesc.DepthStencilState.DepthEnable = depthEnabled_ ? TRUE : FALSE;
            psoDesc.DepthStencilState.DepthWriteMask = depthEnabled_ ? D3D12_DEPTH_WRITE_MASK_ALL : D3D12_DEPTH_WRITE_MASK_ZERO;
            psoDesc.DepthStencilState.DepthFunc = D3D12_COMPARISON_FUNC_LESS_EQUAL;
            psoDesc.DepthStencilState.StencilEnable = FALSE;
            psoDesc.SampleMask = UINT_MAX;
            psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
            psoDesc.NumRenderTargets = 1;
            psoDesc.RTVFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM;
            psoDesc.DSVFormat = depthEnabled_ ? DXGI_FORMAT_D32_FLOAT : DXGI_FORMAT_UNKNOWN;
            psoDesc.SampleDesc.Count = 1;

            hr = device_->CreateGraphicsPipelineState(&psoDesc, IID_PPV_ARGS(&pipelineState_));
            if (Failed(hr))
                return Fail(result, hr, "pipeline_state", "ID3D12Device::CreateGraphicsPipelineState");

            if (depthEnabled_ && !CreateDepthResources(result))
                return false;

            const UINT64 vertexBufferBytes = static_cast<UINT64>(sizeof(ArqenDx12VertexPositionColor)) * desc.vertexCount;
            if (vertexBufferBytes == 0 || vertexBufferBytes > (std::numeric_limits<UINT>::max)())
                return FailMessage(result, E_INVALIDARG, "vertex_buffer", "Generated vertex buffer size is invalid for M21D triangle smoke.");

            D3D12_HEAP_PROPERTIES heapProps = UploadHeapProperties();
            D3D12_RESOURCE_DESC bufferDesc = BufferResourceDesc(vertexBufferBytes);
            hr = device_->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &bufferDesc, D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&vertexBuffer_));
            if (Failed(hr))
                return Fail(result, hr, "vertex_buffer", "ID3D12Device::CreateCommittedResource vertex buffer");

            D3D12_RANGE readRange = { 0, 0 };
            hr = vertexBuffer_->Map(0, &readRange, &vertexMapped_);
            if (Failed(hr))
                return Fail(result, hr, "vertex_buffer", "ID3D12Resource::Map vertex buffer");

            baseVertices_ = desc.vertices;
            baseVertexCount_ = desc.vertexCount;
            sceneTransformsEnabled_ = desc.enableSceneTransforms && desc.objectTransforms && desc.objectTransformCount > 0;
            objectTransforms_ = desc.objectTransforms;
            objectTransformCount_ = desc.objectTransformCount;
            cameraEnabled_ = desc.enableCamera;
            camera_ = desc.camera;
            initialCamera_ = desc.camera;
            perspectiveCameraEnabled_ = desc.enablePerspectiveCamera;
            perspectiveCamera_ = desc.perspectiveCamera;
            initialPerspectiveCamera_ = desc.perspectiveCamera;
            keyboardInputEnabled_ = desc.enableKeyboardInput && desc.keyBindings && desc.keyBindingCount > 0;
            keyBindings_ = desc.keyBindings;
            keyBindingCount_ = desc.keyBindingCount;
            peripheralInputEnabled_ = desc.enablePeripheralInput;
            mouseCaptureEnabled_ = desc.enableMouseCapture;
            mouseMoveBindings_ = desc.mouseMoveBindings;
            mouseMoveBindingCount_ = desc.mouseMoveBindingCount;
            mouseButtonBindings_ = desc.mouseButtonBindings;
            mouseButtonBindingCount_ = desc.mouseButtonBindingCount;
            mouseWheelBindings_ = desc.mouseWheelBindings;
            mouseWheelBindingCount_ = desc.mouseWheelBindingCount;
            mouseWheelDelta_ = desc.mouseWheelDelta;
            if (mouseCaptureEnabled_ && hwnd_)
            {
                SetCapture(hwnd_);
                RECT client = {};
                if (GetClientRect(hwnd_, &client))
                {
                    mouseCenter_.x = (client.left + client.right) / 2;
                    mouseCenter_.y = (client.top + client.bottom) / 2;
                    POINT screenCenter = mouseCenter_;
                    ClientToScreen(hwnd_, &screenCenter);
                    SetCursorPos(screenCenter.x, screenCenter.y);
                    lastMouse_ = mouseCenter_;
                    mousePositionValid_ = true;
                }
            }
            sceneDynamicVertexBuffer_ = sceneTransformsEnabled_ || cameraEnabled_ || perspectiveCameraEnabled_ || keyboardInputEnabled_ || peripheralInputEnabled_;
            UpdateSceneVertexBuffer();

            vertexBufferView_.BufferLocation = vertexBuffer_->GetGPUVirtualAddress();
            vertexBufferView_.SizeInBytes = static_cast<UINT>(vertexBufferBytes);
            vertexBufferView_.StrideInBytes = sizeof(ArqenDx12VertexPositionColor);
            drawVertexCount_ = desc.drawVertexCount;
            drawCalls_ = desc.drawCalls;
            drawCallCount_ = hasDrawCalls ? desc.drawCallCount : 0;

            tintEnabled_ = desc.enableTint;
            tintBaseColor_ = desc.tintColor;
            animationColors_ = desc.animationColors;
            animationColorCount_ = desc.animationColorCount;
            animationEveryFrames_ = desc.animationEveryFrames == 0 ? 1u : desc.animationEveryFrames;

            if (tintEnabled_)
            {
                D3D12_RESOURCE_DESC tintDesc = BufferResourceDesc(256);
                hr = device_->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &tintDesc, D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&tintBuffer_));
                if (Failed(hr))
                    return Fail(result, hr, "constant_buffer", "ID3D12Device::CreateCommittedResource tint constant buffer");

                D3D12_RANGE tintReadRange = { 0, 0 };
                hr = tintBuffer_->Map(0, &tintReadRange, &tintMapped_);
                if (Failed(hr))
                    return Fail(result, hr, "constant_buffer", "ID3D12Resource::Map tint constant buffer");

                UpdateTintBuffer(0);
            }
            return true;
        }

        bool RenderClearOnce(const ArqenDx12ClearColor& clear, bool waitForVSync, ArqenDx12ClearWindowResult* result)
        {
            return RenderOnce(clear, waitForVSync, false, result);
        }

        bool RenderTriangleOnce(const ArqenDx12ClearColor& clear, bool waitForVSync, ArqenDx12ClearWindowResult* result, UINT frameNumber = 0, UINT targetFps = 60)
        {
            if (!pipelineState_ || !rootSignature_ || !vertexBuffer_ || drawVertexCount_ == 0)
                return FailMessage(result, E_FAIL, "triangle", "Triangle resources were not initialized before draw.");
            UpdateInput(targetFps);
            UpdateSceneVertexBuffer();
            if (!animationPaused_)
                UpdateTintBuffer(frameNumber);
            return RenderOnce(clear, waitForVSync, true, result);
        }

        void UpdateInput(UINT targetFps)
        {
            const float dt = 1.0f / static_cast<float>(EffectiveTargetFps(targetFps));

            if (keyboardInputEnabled_ && keyBindings_ && keyBindingCount_ > 0)
            {
            for (UINT i = 0; i < keyBindingCount_; ++i)
            {
                const ArqenDx12KeyBinding& binding = keyBindings_[i];
                if (binding.virtualKey >= 256)
                    continue;

                const bool down = (GetAsyncKeyState(static_cast<int>(binding.virtualKey)) & 0x8000) != 0;
                const bool pressed = down && !previousKeyDown_[binding.virtualKey];
                previousKeyDown_[binding.virtualKey] = down;

                switch (binding.action)
                {
                case ARQEN_DX12_KEY_ACTION_MOVE_CAMERA_HELD:
                    if (down && cameraEnabled_)
                    {
                        camera_.x += binding.x * dt;
                        camera_.y += binding.y * dt;
                        camera_.z += binding.z * dt;
                    }
                    if (down && perspectiveCameraEnabled_)
                    {
                        perspectiveCamera_.x += binding.x * dt;
                        perspectiveCamera_.y += binding.y * dt;
                        perspectiveCamera_.z += binding.z * dt;
                    }
                    break;
                case ARQEN_DX12_KEY_ACTION_RESET_CAMERA_PRESSED:
                    if (pressed && cameraEnabled_)
                        camera_ = initialCamera_;
                    if (pressed && perspectiveCameraEnabled_)
                        perspectiveCamera_ = initialPerspectiveCamera_;
                    break;
                case ARQEN_DX12_KEY_ACTION_TOGGLE_ANIMATION_PRESSED:
                    if (pressed)
                        animationPaused_ = !animationPaused_;
                    break;
                default:
                    break;
                }
            }
            }

            UpdateMouseInput(dt);
        }

        UINT MouseButtonVirtualKey(UINT button) const
        {
            switch (button)
            {
            case ARQEN_DX12_MOUSE_BUTTON_LEFT: return VK_LBUTTON;
            case ARQEN_DX12_MOUSE_BUTTON_RIGHT: return VK_RBUTTON;
            case ARQEN_DX12_MOUSE_BUTTON_MIDDLE: return VK_MBUTTON;
            default: return 0;
            }
        }

        void MoveActiveCamera(float dx, float dy, float dz, float scale)
        {
            if (cameraEnabled_)
            {
                camera_.x += dx * scale;
                camera_.y += dy * scale;
                camera_.z += dz * scale;
            }
            if (perspectiveCameraEnabled_)
            {
                perspectiveCamera_.x += dx * scale;
                perspectiveCamera_.y += dy * scale;
                perspectiveCamera_.z += dz * scale;
            }
        }

        void ResetActiveCamera()
        {
            if (cameraEnabled_)
                camera_ = initialCamera_;
            if (perspectiveCameraEnabled_)
                perspectiveCamera_ = initialPerspectiveCamera_;
        }

        void UpdateMouseInput(float dt)
        {
            if (!peripheralInputEnabled_)
                return;

            if (perspectiveCameraEnabled_ && mouseMoveBindings_ && mouseMoveBindingCount_ > 0 && hwnd_)
            {
                POINT clientPos = {};
                if (mouseCaptureEnabled_)
                {
                    clientPos = mouseCenter_;
                    POINT screenPos = {};
                    GetCursorPos(&screenPos);
                    POINT local = screenPos;
                    ScreenToClient(hwnd_, &local);
                    const LONG dx = local.x - mouseCenter_.x;
                    const LONG dy = local.y - mouseCenter_.y;
                    if (dx != 0 || dy != 0)
                    {
                        for (UINT i = 0; i < mouseMoveBindingCount_; ++i)
                        {
                            perspectiveCamera_.yawDegrees += static_cast<float>(dx) * mouseMoveBindings_[i].sensitivityX;
                            perspectiveCamera_.pitchDegrees += static_cast<float>(dy) * mouseMoveBindings_[i].sensitivityY;
                            perspectiveCamera_.pitchDegrees = ClampFloat(perspectiveCamera_.pitchDegrees, -89.0f, 89.0f);
                        }
                        POINT centerScreen = mouseCenter_;
                        ClientToScreen(hwnd_, &centerScreen);
                        SetCursorPos(centerScreen.x, centerScreen.y);
                    }
                }
                else
                {
                    POINT screenPos = {};
                    GetCursorPos(&screenPos);
                    clientPos = screenPos;
                    ScreenToClient(hwnd_, &clientPos);
                    if (mousePositionValid_)
                    {
                        const LONG dx = clientPos.x - lastMouse_.x;
                        const LONG dy = clientPos.y - lastMouse_.y;
                        if (dx != 0 || dy != 0)
                        {
                            for (UINT i = 0; i < mouseMoveBindingCount_; ++i)
                            {
                                perspectiveCamera_.yawDegrees += static_cast<float>(dx) * mouseMoveBindings_[i].sensitivityX;
                                perspectiveCamera_.pitchDegrees += static_cast<float>(dy) * mouseMoveBindings_[i].sensitivityY;
                                perspectiveCamera_.pitchDegrees = ClampFloat(perspectiveCamera_.pitchDegrees, -89.0f, 89.0f);
                            }
                        }
                    }
                    lastMouse_ = clientPos;
                    mousePositionValid_ = true;
                }
            }

            if (mouseButtonBindings_ && mouseButtonBindingCount_ > 0)
            {
                for (UINT i = 0; i < mouseButtonBindingCount_; ++i)
                {
                    const ArqenDx12MouseButtonBinding& binding = mouseButtonBindings_[i];
                    const UINT vk = MouseButtonVirtualKey(binding.button);
                    if (vk == 0 || binding.button >= 8)
                        continue;
                    const bool down = (GetAsyncKeyState(static_cast<int>(vk)) & 0x8000) != 0;
                    const bool pressed = down && !previousMouseButtonDown_[binding.button];
                    previousMouseButtonDown_[binding.button] = down;
                    switch (binding.action)
                    {
                    case ARQEN_DX12_MOUSE_BUTTON_ACTION_MOVE_CAMERA_HELD:
                        if (down)
                            MoveActiveCamera(binding.x, binding.y, binding.z, dt);
                        break;
                    case ARQEN_DX12_MOUSE_BUTTON_ACTION_RESET_CAMERA_PRESSED:
                        if (pressed)
                            ResetActiveCamera();
                        break;
                    case ARQEN_DX12_MOUSE_BUTTON_ACTION_TOGGLE_ANIMATION_PRESSED:
                        if (pressed)
                            animationPaused_ = !animationPaused_;
                        break;
                    default:
                        break;
                    }
                }
            }

            if (mouseWheelBindings_ && mouseWheelBindingCount_ > 0 && mouseWheelDelta_)
            {
                const LONG raw = InterlockedExchange(mouseWheelDelta_, 0);
                if (raw != 0)
                {
                    const float wheelUnits = static_cast<float>(raw) / static_cast<float>(WHEEL_DELTA);
                    for (UINT i = 0; i < mouseWheelBindingCount_; ++i)
                    {
                        const ArqenDx12MouseWheelBinding& binding = mouseWheelBindings_[i];
                        if (binding.action == ARQEN_DX12_MOUSE_WHEEL_ACTION_MOVE_CAMERA)
                            MoveActiveCamera(binding.x, binding.y, binding.z, wheelUnits);
                    }
                }
            }
        }

        void UpdateSceneVertexBuffer()
        {
            if (!vertexMapped_ || !baseVertices_ || baseVertexCount_ == 0)
                return;

            auto* out = static_cast<ArqenDx12VertexPositionColor*>(vertexMapped_);
            if (!sceneDynamicVertexBuffer_)
            {
                std::memcpy(out, baseVertices_, static_cast<size_t>(sizeof(ArqenDx12VertexPositionColor)) * baseVertexCount_);
                return;
            }

            std::memcpy(out, baseVertices_, static_cast<size_t>(sizeof(ArqenDx12VertexPositionColor)) * baseVertexCount_);
            if (drawCallCount_ > 0 && drawCalls_)
            {
                for (UINT i = 0; i < drawCallCount_; ++i)
                {
                    const ArqenDx12DrawCall& drawCall = drawCalls_[i];
                    const ArqenDx12ObjectTransform transform = ResolveTransform(drawCall.transformIndex);
                    for (UINT v = 0; v < drawCall.vertexCount; ++v)
                    {
                        const UINT index = drawCall.firstVertex + v;
                        if (index < baseVertexCount_)
                            out[index] = TransformVertex(baseVertices_[index], transform);
                    }
                }
            }
            else
            {
                const ArqenDx12ObjectTransform transform = ResolveTransform(0);
                for (UINT i = 0; i < baseVertexCount_; ++i)
                    out[i] = TransformVertex(baseVertices_[i], transform);
            }
        }

        ArqenDx12ObjectTransform ResolveTransform(UINT index) const
        {
            if (sceneTransformsEnabled_ && objectTransforms_ && objectTransformCount_ > 0 && index < objectTransformCount_)
                return objectTransforms_[index];
            return { 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f };
        }

        ArqenDx12VertexPositionColor TransformVertex(const ArqenDx12VertexPositionColor& src, const ArqenDx12ObjectTransform& transform) const
        {
            constexpr float Pi = 3.14159265358979323846f;
            const float radians = transform.rotationZDegrees * (Pi / 180.0f);
            const float c = std::cos(radians);
            const float s = std::sin(radians);

            const float sx = src.x * transform.sx;
            const float sy = src.y * transform.sy;
            const float sz = src.z * transform.sz;
            float x = sx * c - sy * s + transform.x;
            float y = sx * s + sy * c + transform.y;
            float z = sz + transform.z;

            if (perspectiveCameraEnabled_)
                return ProjectPerspectiveVertex(x, y, z, src);

            if (cameraEnabled_)
            {
                const float zoom = camera_.zoom <= 0.0001f ? 1.0f : camera_.zoom;
                x = (x - camera_.x) * zoom;
                y = (y - camera_.y) * zoom;
                z = z - camera_.z;
            }

            return { x, y, z, src.r, src.g, src.b, src.a };
        }

        ArqenDx12VertexPositionColor ProjectPerspectiveVertex(float worldX, float worldY, float worldZ, const ArqenDx12VertexPositionColor& src) const
        {
            constexpr float Pi = 3.14159265358979323846f;
            auto degToRad = [](float degrees) { return degrees * (Pi / 180.0f); };

            float x = worldX - perspectiveCamera_.x;
            float y = worldY - perspectiveCamera_.y;
            float z = worldZ - perspectiveCamera_.z;

            auto rotateX = [](float radians, float& yy, float& zz)
            {
                const float c = std::cos(radians);
                const float s = std::sin(radians);
                const float ny = yy * c - zz * s;
                const float nz = yy * s + zz * c;
                yy = ny;
                zz = nz;
            };
            auto rotateY = [](float radians, float& xx, float& zz)
            {
                const float c = std::cos(radians);
                const float s = std::sin(radians);
                const float nx = xx * c + zz * s;
                const float nz = -xx * s + zz * c;
                xx = nx;
                zz = nz;
            };
            auto rotateZ = [](float radians, float& xx, float& yy)
            {
                const float c = std::cos(radians);
                const float s = std::sin(radians);
                const float nx = xx * c - yy * s;
                const float ny = xx * s + yy * c;
                xx = nx;
                yy = ny;
            };

            rotateZ(-degToRad(perspectiveCamera_.rollDegrees), x, y);
            rotateY(-degToRad(perspectiveCamera_.yawDegrees), x, z);
            rotateX(-degToRad(perspectiveCamera_.pitchDegrees), y, z);

            const float nearPlane = perspectiveCamera_.nearPlane > 0.0001f ? perspectiveCamera_.nearPlane : 0.1f;
            const float farPlane = perspectiveCamera_.farPlane > nearPlane + 0.0001f ? perspectiveCamera_.farPlane : 100.0f;
            const float fov = (perspectiveCamera_.fovYDegrees > 1.0f && perspectiveCamera_.fovYDegrees < 179.0f) ? perspectiveCamera_.fovYDegrees : 70.0f;
            const float safeZ = z < nearPlane ? nearPlane : z;
            const float aspect = height_ == 0 ? 1.0f : static_cast<float>(width_) / static_cast<float>(height_);
            const float f = 1.0f / std::tan(degToRad(fov) * 0.5f);
            const float clipX = (x * f / aspect) / safeZ;
            const float clipY = (y * f) / safeZ;
            float clipZ = farPlane / (farPlane - nearPlane) - (nearPlane * farPlane) / ((farPlane - nearPlane) * safeZ);
            if (clipZ < 0.0f) clipZ = 0.0f;
            if (clipZ > 1.0f) clipZ = 1.0f;
            return { clipX, clipY, clipZ, src.r, src.g, src.b, src.a };
        }

        void UpdateTintBuffer(UINT frameNumber)
        {
            if (!tintEnabled_ || !tintMapped_)
                return;

            ArqenDx12ClearColor color = tintBaseColor_;
            if (animationColors_ && animationColorCount_ > 0)
            {
                const UINT every = animationEveryFrames_ == 0 ? 1u : animationEveryFrames_;
                const UINT index = (frameNumber / every) % animationColorCount_;
                color = animationColors_[index];
            }

            float values[4] = { color.r, color.g, color.b, color.a };
            std::memcpy(tintMapped_, values, sizeof(values));
        }

        ~Dx12ClearContext()
        {
            if (vertexBuffer_ && vertexMapped_)
                vertexBuffer_->Unmap(0, nullptr);
            vertexMapped_ = nullptr;
            if (tintBuffer_ && tintMapped_)
                tintBuffer_->Unmap(0, nullptr);
            tintMapped_ = nullptr;
            if (fenceEvent_)
                CloseHandle(fenceEvent_);
        }

    private:
        bool CreateDepthResources(ArqenDx12ClearWindowResult* result)
        {
            D3D12_DESCRIPTOR_HEAP_DESC dsvHeapDesc = {};
            dsvHeapDesc.NumDescriptors = 1;
            dsvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_DSV;
            dsvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
            HRESULT hr = device_->CreateDescriptorHeap(&dsvHeapDesc, IID_PPV_ARGS(&dsvHeap_));
            if (Failed(hr))
                return Fail(result, hr, "dsv_heap", "ID3D12Device::CreateDescriptorHeap DSV");

            D3D12_CLEAR_VALUE depthClear = {};
            depthClear.Format = DXGI_FORMAT_D32_FLOAT;
            depthClear.DepthStencil.Depth = 1.0f;
            depthClear.DepthStencil.Stencil = 0;
            D3D12_HEAP_PROPERTIES heapProps = DefaultHeapProperties();
            D3D12_RESOURCE_DESC depthDesc = DepthResourceDesc(width_, height_);
            hr = device_->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &depthDesc, D3D12_RESOURCE_STATE_DEPTH_WRITE, &depthClear, IID_PPV_ARGS(&depthStencil_));
            if (Failed(hr))
                return Fail(result, hr, "depth_buffer", "ID3D12Device::CreateCommittedResource depth buffer");

            D3D12_DEPTH_STENCIL_VIEW_DESC dsvDesc = {};
            dsvDesc.Format = DXGI_FORMAT_D32_FLOAT;
            dsvDesc.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2D;
            dsvDesc.Flags = D3D12_DSV_FLAG_NONE;
            device_->CreateDepthStencilView(depthStencil_.Get(), &dsvDesc, dsvHeap_->GetCPUDescriptorHandleForHeapStart());
            dsvDescriptorSize_ = device_->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_DSV);
            return true;
        }

        bool RenderOnce(const ArqenDx12ClearColor& clear, bool waitForVSync, bool drawTriangle, ArqenDx12ClearWindowResult* result)
        {
            HRESULT hr = allocator_->Reset();
            if (Failed(hr))
                return Fail(result, hr, "record", "ID3D12CommandAllocator::Reset");

            hr = commandList_->Reset(allocator_.Get(), drawTriangle ? pipelineState_.Get() : nullptr);
            if (Failed(hr))
                return Fail(result, hr, "record", "ID3D12GraphicsCommandList::Reset");

            D3D12_RESOURCE_BARRIER before = {};
            before.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
            before.Transition.pResource = renderTargets_[frameIndex_].Get();
            before.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
            before.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
            before.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
            commandList_->ResourceBarrier(1, &before);

            D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = rtvHeap_->GetCPUDescriptorHandleForHeapStart();
            rtvHandle.ptr += static_cast<SIZE_T>(frameIndex_) * rtvDescriptorSize_;

            D3D12_CPU_DESCRIPTOR_HANDLE dsvHandle = {};
            D3D12_CPU_DESCRIPTOR_HANDLE* dsvHandlePtr = nullptr;
            if (depthEnabled_ && dsvHeap_.Get())
            {
                dsvHandle = dsvHeap_->GetCPUDescriptorHandleForHeapStart();
                dsvHandlePtr = &dsvHandle;
            }

            const float clearColor[4] = { clear.r, clear.g, clear.b, clear.a };
            commandList_->OMSetRenderTargets(1, &rtvHandle, FALSE, dsvHandlePtr);
            commandList_->ClearRenderTargetView(rtvHandle, clearColor, 0, nullptr);
            if (dsvHandlePtr)
                commandList_->ClearDepthStencilView(dsvHandle, D3D12_CLEAR_FLAG_DEPTH, 1.0f, 0, 0, nullptr);

            if (drawTriangle)
            {
                D3D12_VIEWPORT viewport = {};
                viewport.TopLeftX = 0.0f;
                viewport.TopLeftY = 0.0f;
                viewport.Width = static_cast<float>(width_);
                viewport.Height = static_cast<float>(height_);
                viewport.MinDepth = 0.0f;
                viewport.MaxDepth = 1.0f;

                D3D12_RECT scissor = {};
                scissor.left = 0;
                scissor.top = 0;
                scissor.right = static_cast<LONG>(width_);
                scissor.bottom = static_cast<LONG>(height_);

                commandList_->SetGraphicsRootSignature(rootSignature_.Get());
                if (tintEnabled_ && tintBuffer_)
                    commandList_->SetGraphicsRootConstantBufferView(0, tintBuffer_->GetGPUVirtualAddress());
                commandList_->RSSetViewports(1, &viewport);
                commandList_->RSSetScissorRects(1, &scissor);
                commandList_->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
                commandList_->IASetVertexBuffers(0, 1, &vertexBufferView_);
                if (drawCallCount_ > 0 && drawCalls_)
                {
                    for (UINT i = 0; i < drawCallCount_; ++i)
                    {
                        commandList_->DrawInstanced(drawCalls_[i].vertexCount, 1, drawCalls_[i].firstVertex, 0);
                    }
                }
                else
                {
                    commandList_->DrawInstanced(drawVertexCount_, 1, 0, 0);
                }
            }

            D3D12_RESOURCE_BARRIER after = before;
            after.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
            after.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
            commandList_->ResourceBarrier(1, &after);

            hr = commandList_->Close();
            if (Failed(hr))
                return Fail(result, hr, "record", "ID3D12GraphicsCommandList::Close");

            ID3D12CommandList* lists[] = { commandList_.Get() };
            queue_->ExecuteCommandLists(1, lists);

            hr = swapChain_->Present(waitForVSync ? 1u : 0u, 0);
            if (Failed(hr))
                return Fail(result, hr, "present", "IDXGISwapChain::Present");

            if (!WaitForGpu(result))
                return false;

            frameIndex_ = swapChain_->GetCurrentBackBufferIndex();
            return true;
        }

        bool ShaderFail(ArqenDx12ClearWindowResult* result, HRESULT hr, const char* stage, const char* call, ID3DBlob* errorBlob)
        {
            char buffer[360] = {};
            if (errorBlob && errorBlob->GetBufferPointer() && errorBlob->GetBufferSize() > 0)
            {
                std::snprintf(buffer, sizeof(buffer), "%s failed with HRESULT 0x%08X: %.220s", call, static_cast<unsigned>(hr), static_cast<const char*>(errorBlob->GetBufferPointer()));
            }
            else
            {
                std::snprintf(buffer, sizeof(buffer), "%s failed with HRESULT 0x%08X", call, static_cast<unsigned>(hr));
            }
            SetResult(result, hr, stage, buffer);
            return false;
        }

        bool WaitForGpu(ArqenDx12ClearWindowResult* result)
        {
            const UINT64 signalValue = fenceValue_;
            HRESULT hr = queue_->Signal(fence_.Get(), signalValue);
            if (Failed(hr))
                return Fail(result, hr, "fence", "ID3D12CommandQueue::Signal");

            fenceValue_++;

            if (fence_->GetCompletedValue() < signalValue)
            {
                hr = fence_->SetEventOnCompletion(signalValue, fenceEvent_);
                if (Failed(hr))
                    return Fail(result, hr, "fence", "ID3D12Fence::SetEventOnCompletion");

                WaitForSingleObject(fenceEvent_, INFINITE);
            }

            return true;
        }

        HWND hwnd_ = nullptr;
        UINT width_ = 0;
        UINT height_ = 0;
        ComPtr<IDXGIFactory6> factory_;
        ComPtr<ID3D12Device> device_;
        ComPtr<ID3D12CommandQueue> queue_;
        ComPtr<IDXGISwapChain3> swapChain_;
        ComPtr<ID3D12DescriptorHeap> rtvHeap_;
        ComPtr<ID3D12DescriptorHeap> dsvHeap_;
        ComPtr<ID3D12Resource> renderTargets_[FrameCount];
        ComPtr<ID3D12Resource> depthStencil_;
        ComPtr<ID3D12CommandAllocator> allocator_;
        ComPtr<ID3D12GraphicsCommandList> commandList_;
        ComPtr<ID3D12Fence> fence_;
        ComPtr<ID3D12RootSignature> rootSignature_;
        ComPtr<ID3D12PipelineState> pipelineState_;
        ComPtr<ID3D12Resource> vertexBuffer_;
        ComPtr<ID3D12Resource> tintBuffer_;
        void* tintMapped_ = nullptr;
        void* vertexMapped_ = nullptr;
        const ArqenDx12VertexPositionColor* baseVertices_ = nullptr;
        UINT baseVertexCount_ = 0;
        const ArqenDx12ObjectTransform* objectTransforms_ = nullptr;
        UINT objectTransformCount_ = 0;
        bool sceneTransformsEnabled_ = false;
        bool sceneDynamicVertexBuffer_ = false;
        bool cameraEnabled_ = false;
        ArqenDx12OrthographicCamera camera_ = { 0.0f, 0.0f, 0.0f, 1.0f };
        ArqenDx12OrthographicCamera initialCamera_ = { 0.0f, 0.0f, 0.0f, 1.0f };
        bool perspectiveCameraEnabled_ = false;
        bool depthEnabled_ = false;
        ArqenDx12PerspectiveCamera perspectiveCamera_ = { 0.0f, 0.0f, -3.0f, 0.0f, 0.0f, 0.0f, 70.0f, 0.1f, 100.0f };
        ArqenDx12PerspectiveCamera initialPerspectiveCamera_ = { 0.0f, 0.0f, -3.0f, 0.0f, 0.0f, 0.0f, 70.0f, 0.1f, 100.0f };
        const ArqenDx12KeyBinding* keyBindings_ = nullptr;
        UINT keyBindingCount_ = 0;
        bool keyboardInputEnabled_ = false;
        bool previousKeyDown_[256] = {};
        bool peripheralInputEnabled_ = false;
        bool mouseCaptureEnabled_ = false;
        const ArqenDx12MouseMoveBinding* mouseMoveBindings_ = nullptr;
        UINT mouseMoveBindingCount_ = 0;
        const ArqenDx12MouseButtonBinding* mouseButtonBindings_ = nullptr;
        UINT mouseButtonBindingCount_ = 0;
        const ArqenDx12MouseWheelBinding* mouseWheelBindings_ = nullptr;
        UINT mouseWheelBindingCount_ = 0;
        volatile LONG* mouseWheelDelta_ = nullptr;
        bool previousMouseButtonDown_[8] = {};
        POINT lastMouse_ = { 0, 0 };
        POINT mouseCenter_ = { 0, 0 };
        bool mousePositionValid_ = false;
        bool animationPaused_ = false;
        bool tintEnabled_ = false;
        ArqenDx12ClearColor tintBaseColor_ = { 1.0f, 1.0f, 1.0f, 1.0f };
        const ArqenDx12ClearColor* animationColors_ = nullptr;
        UINT animationColorCount_ = 0;
        UINT animationEveryFrames_ = 1;
        ComPtr<ID3DBlob> vertexShader_;
        ComPtr<ID3DBlob> pixelShader_;
        D3D12_VERTEX_BUFFER_VIEW vertexBufferView_ = {};
        HANDLE fenceEvent_ = nullptr;
        UINT rtvDescriptorSize_ = 0;
        UINT dsvDescriptorSize_ = 0;
        UINT frameIndex_ = 0;
        UINT64 fenceValue_ = 0;
        UINT drawVertexCount_ = 0;
        const ArqenDx12DrawCall* drawCalls_ = nullptr;
        UINT drawCallCount_ = 0;
    };
}

extern "C" __declspec(dllexport)
bool ArqenDx12ClearWindowOnce(const ArqenDx12ClearWindowDesc* desc, ArqenDx12ClearWindowResult* result)
{
    if (!desc)
    {
        SetResult(result, E_INVALIDARG, "validate", "ArqenDx12ClearWindowDesc pointer is null.");
        return false;
    }

    Dx12ClearContext context;
    if (!context.Initialize(desc->hwnd, desc->width, desc->height, desc->enableDebugLayer, result))
        return false;

    if (!context.RenderClearOnce(desc->clearColor, desc->waitForVSync, result))
        return false;

    SetResult(result, S_OK, "ok", "DX12 clear-color frame completed.");
    return true;
}

extern "C" __declspec(dllexport)
bool ArqenDx12ClearWindowRunFrames(const ArqenDx12ClearWindowDesc* desc, ArqenDx12ClearWindowResult* result)
{
    if (!desc)
    {
        SetResult(result, E_INVALIDARG, "validate", "ArqenDx12ClearWindowDesc pointer is null.");
        return false;
    }

    Dx12ClearContext context;
    if (!context.Initialize(desc->hwnd, desc->width, desc->height, desc->enableDebugLayer, result))
        return false;

    const UINT frameCount = EffectiveFrameCount(desc->frameCount);
    const UINT targetFps = EffectiveTargetFps(desc->targetFps);
    const bool infinite = IsInfiniteFrameCount(desc->frameCount);
    for (UINT frame = 0; infinite || frame < frameCount; ++frame)
    {
        bool quit = false;
        PumpWindowMessages(&quit);
        if (quit)
        {
            SetResult(result, S_OK, "ok", "DX12 clear frame loop stopped by window quit.");
            return true;
        }

        const DWORD frameStart = GetTickCount();
        if (!context.RenderClearOnce(desc->clearColor, desc->waitForVSync, result))
            return false;

        PumpWindowMessages(&quit);
        if (quit)
        {
            SetResult(result, S_OK, "ok", "DX12 clear frame loop stopped by window quit.");
            return true;
        }

        SleepToTargetFrame(frameStart, targetFps);
    }

    SetResult(result, S_OK, "ok", infinite ? "DX12 clear keep-open loop stopped." : "DX12 clear frame loop completed.");
    return true;
}

extern "C" __declspec(dllexport)
bool ArqenDx12TriangleWindowOnce(const ArqenDx12TriangleWindowDesc* desc, ArqenDx12ClearWindowResult* result)
{
    if (!desc)
    {
        SetResult(result, E_INVALIDARG, "validate", "ArqenDx12TriangleWindowDesc pointer is null.");
        return false;
    }

    Dx12ClearContext context;
    if (!context.Initialize(desc->hwnd, desc->width, desc->height, desc->enableDebugLayer, result))
        return false;

    if (!context.CreateTriangleResources(*desc, result))
        return false;

    if (!context.RenderTriangleOnce(desc->clearColor, desc->waitForVSync, result, 0, desc->targetFps))
        return false;

    SetResult(result, S_OK, "ok", "DX12 triangle frame completed.");
    return true;
}

extern "C" __declspec(dllexport)
bool ArqenDx12TriangleWindowRunFrames(const ArqenDx12TriangleWindowDesc* desc, ArqenDx12ClearWindowResult* result)
{
    if (!desc)
    {
        SetResult(result, E_INVALIDARG, "validate", "ArqenDx12TriangleWindowDesc pointer is null.");
        return false;
    }

    Dx12ClearContext context;
    if (!context.Initialize(desc->hwnd, desc->width, desc->height, desc->enableDebugLayer, result))
        return false;

    if (!context.CreateTriangleResources(*desc, result))
        return false;

    const UINT frameCount = EffectiveFrameCount(desc->frameCount);
    const UINT targetFps = EffectiveTargetFps(desc->targetFps);
    const bool infinite = IsInfiniteFrameCount(desc->frameCount);
    for (UINT frame = 0; infinite || frame < frameCount; ++frame)
    {
        bool quit = false;
        PumpWindowMessages(&quit);
        if (quit)
        {
            SetResult(result, S_OK, "ok", "DX12 triangle frame loop stopped by window quit.");
            return true;
        }

        const DWORD frameStart = GetTickCount();
        if (!context.RenderTriangleOnce(desc->clearColor, desc->waitForVSync, result, frame, targetFps))
            return false;

        PumpWindowMessages(&quit);
        if (quit)
        {
            SetResult(result, S_OK, "ok", "DX12 triangle frame loop stopped by window quit.");
            return true;
        }

        SleepToTargetFrame(frameStart, targetFps);
    }

    SetResult(result, S_OK, "ok", infinite ? "DX12 triangle keep-open loop stopped." : "DX12 triangle frame loop completed.");
    return true;
}
