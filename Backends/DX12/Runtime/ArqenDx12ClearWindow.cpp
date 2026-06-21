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
#include <vector>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

namespace
{
    constexpr UINT FrameCount = 2;
    constexpr UINT ArqenDx12UiNoTransformIndex = 0xFFFFFFFFu;
    constexpr UINT ArqenDx12UiControlIndexBase = 0x80000000u;
    constexpr UINT ArqenDx12UiControlRoleMask = 0x70000000u;
    constexpr UINT ArqenDx12UiControlIndexMask = 0x0FFFFFFFu;
    constexpr UINT ArqenDx12UiControlRoleSliderFill = 0x10000000u;
    constexpr UINT ArqenDx12UiControlRoleSliderKnob = 0x20000000u;

    bool IsArqenDx12UiDrawCall(UINT transformIndex)
    {
        return transformIndex == ArqenDx12UiNoTransformIndex || (transformIndex & ArqenDx12UiControlIndexBase) != 0;
    }

    bool IsArqenDx12UiControlDrawCall(UINT transformIndex)
    {
        return transformIndex != ArqenDx12UiNoTransformIndex && (transformIndex & ArqenDx12UiControlIndexBase) != 0;
    }

    UINT ArqenDx12UiControlIndex(UINT transformIndex)
    {
        return transformIndex & ArqenDx12UiControlIndexMask;
    }

    UINT ArqenDx12UiControlRole(UINT transformIndex)
    {
        return transformIndex & ArqenDx12UiControlRoleMask;
    }

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

            backBufferWidth_ = width_;
            backBufferHeight_ = height_;
            if (!CreateRenderTargetViews(result))
                return false;

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
            fakeLightingEnabled_ = desc.enableFakeLighting;
            directionalLight_ = desc.directionalLight;
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
                    if (desc.enableSceneTransforms && desc.objectTransforms && desc.objectTransformCount > 0 && !IsArqenDx12UiDrawCall(drawCall.transformIndex) && drawCall.transformIndex >= desc.objectTransformCount)
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
            psoDesc.BlendState.RenderTarget[0].BlendEnable = TRUE;
            psoDesc.BlendState.RenderTarget[0].LogicOpEnable = FALSE;
            psoDesc.BlendState.RenderTarget[0].SrcBlend = D3D12_BLEND_SRC_ALPHA;
            psoDesc.BlendState.RenderTarget[0].DestBlend = D3D12_BLEND_INV_SRC_ALPHA;
            psoDesc.BlendState.RenderTarget[0].BlendOp = D3D12_BLEND_OP_ADD;
            psoDesc.BlendState.RenderTarget[0].SrcBlendAlpha = D3D12_BLEND_ONE;
            psoDesc.BlendState.RenderTarget[0].DestBlendAlpha = D3D12_BLEND_INV_SRC_ALPHA;
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
            dynamicObjectTransforms_.clear();
            if (desc.objectTransforms && desc.objectTransformCount > 0)
            {
                dynamicObjectTransforms_.assign(desc.objectTransforms, desc.objectTransforms + desc.objectTransformCount);
                objectTransforms_ = dynamicObjectTransforms_.data();
            }
            else
            {
                objectTransforms_ = nullptr;
            }
            objectTransformCount_ = static_cast<UINT>(dynamicObjectTransforms_.size());
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
            objectSelectorEnabled_ = desc.enableObjectSelector;
            objectSelectButton_ = desc.objectSelectButton;
            selectedObjectRotateBindings_ = desc.selectedObjectRotateBindings;
            selectedObjectRotateBindingCount_ = desc.selectedObjectRotateBindingCount;
            uiOverlayEnabled_ = desc.enableUiOverlay && desc.uiControls && desc.uiControlCount > 0;
            uiControls_.clear();
            if (desc.uiControls && desc.uiControlCount > 0)
                uiControls_.assign(desc.uiControls, desc.uiControls + desc.uiControlCount);
            previousUiLeftDown_ = false;
            // M29B: capture mouse now means UE-style soft viewport navigation.
            // The cursor remains free until RMB is held, avoiding startup cursor lock/warp.
            viewportNavigationActive_ = false;
            mousePositionValid_ = false;
            sceneDynamicVertexBuffer_ = sceneTransformsEnabled_ || cameraEnabled_ || perspectiveCameraEnabled_ || keyboardInputEnabled_ || peripheralInputEnabled_ || fakeLightingEnabled_ || objectSelectorEnabled_ || uiOverlayEnabled_;
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

            if (!HasInputForeground())
            {
                if (viewportNavigationActive_)
                    SetViewportNavigationActive(false);
                ResetInputTransientState();
                return;
            }

            if (peripheralInputEnabled_ && RequiresViewportNavigationHold())
                SetViewportNavigationActive(IsRightMouseDown());

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
                    if (down && (!RequiresViewportNavigationHold() || viewportNavigationActive_))
                        MoveActiveCamera(binding.x, binding.y, binding.z, dt);
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

        bool RequiresViewportNavigationHold() const
        {
            return mouseCaptureEnabled_ && peripheralInputEnabled_ && perspectiveCameraEnabled_;
        }

        bool IsRightMouseDown() const
        {
            return (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;
        }

        bool HasInputForeground() const
        {
            if (!hwnd_)
                return false;
            const HWND foreground = GetForegroundWindow();
            return foreground == hwnd_ || GetCapture() == hwnd_;
        }

        void ResetInputTransientState()
        {
            std::memset(previousKeyDown_, 0, sizeof(previousKeyDown_));
            std::memset(previousMouseButtonDown_, 0, sizeof(previousMouseButtonDown_));
            previousObjectSelectButtonDown_ = false;
            previousUiLeftDown_ = false;
            hoveredUiControlIndex_ = -1;
            pressedUiControlIndex_ = -1;
            focusedUiControlIndex_ = -1;
            mousePositionValid_ = false;
            rotateMousePositionValid_ = false;
            if (mouseWheelDelta_)
                InterlockedExchange(mouseWheelDelta_, 0);
        }

        void UpdateMouseCenter()
        {
            if (!hwnd_)
                return;
            RECT client = {};
            if (GetClientRect(hwnd_, &client))
            {
                mouseCenter_.x = (client.left + client.right) / 2;
                mouseCenter_.y = (client.top + client.bottom) / 2;
            }
        }

        void SetCursorVisible(bool visible)
        {
            if (cursorVisible_ == visible)
                return;
            cursorVisible_ = visible;
            ShowCursor(visible ? TRUE : FALSE);
        }

        void SetViewportNavigationActive(bool active)
        {
            if (viewportNavigationActive_ == active)
                return;

            viewportNavigationActive_ = active;
            mousePositionValid_ = false;

            if (!hwnd_)
                return;

            if (active)
            {
                SetCapture(hwnd_);
                UpdateMouseCenter();
                POINT centerScreen = mouseCenter_;
                ClientToScreen(hwnd_, &centerScreen);
                SetCursorPos(centerScreen.x, centerScreen.y);
                SetCursorVisible(false);
            }
            else
            {
                if (GetCapture() == hwnd_)
                    ReleaseCapture();
                SetCursorVisible(true);
                SetCursor(LoadCursorW(nullptr, IDC_ARROW));
            }
        }

        void RotatePerspectiveLocalToWorld(float localX, float localY, float localZ, float& worldX, float& worldY, float& worldZ) const
        {
            worldX = localX;
            worldY = localY;
            worldZ = localZ;

            // Inverse of the view-space camera rotations used by ProjectPerspectiveVertex.
            RotateX(DegToRad(perspectiveCamera_.pitchDegrees), worldY, worldZ);
            RotateY(DegToRad(perspectiveCamera_.yawDegrees), worldX, worldZ);
            RotateZ(DegToRad(perspectiveCamera_.rollDegrees), worldX, worldY);
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
                float worldX = dx;
                float worldY = 0.0f;
                float worldZ = dz;
                RotatePerspectiveLocalToWorld(dx, 0.0f, dz, worldX, worldY, worldZ);
                perspectiveCamera_.x += worldX * scale;
                perspectiveCamera_.y += (worldY + dy) * scale;
                perspectiveCamera_.z += worldZ * scale;
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

            if (RequiresViewportNavigationHold())
                SetViewportNavigationActive(IsRightMouseDown());

            if (perspectiveCameraEnabled_ && mouseMoveBindings_ && mouseMoveBindingCount_ > 0 && hwnd_ && (!RequiresViewportNavigationHold() || viewportNavigationActive_))
            {
                POINT clientPos = {};
                if (mouseCaptureEnabled_)
                {
                    UpdateMouseCenter();
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
                        if (down && (!RequiresViewportNavigationHold() || viewportNavigationActive_))
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
                        if (binding.action == ARQEN_DX12_MOUSE_WHEEL_ACTION_MOVE_CAMERA && (!RequiresViewportNavigationHold() || viewportNavigationActive_))
                            MoveActiveCamera(binding.x, binding.y, binding.z, wheelUnits);
                    }
                }
            }

            const bool uiConsumed = UpdateUiOverlayInput();
            if (!uiConsumed)
                UpdateObjectSelectorInput();
        }

        struct LogicalViewport
        {
            float x = 0.0f;
            float y = 0.0f;
            float width = 1.0f;
            float height = 1.0f;
            float scale = 1.0f;
        };

        LogicalViewport BuildLogicalViewport(float surfaceWidth, float surfaceHeight) const
        {
            LogicalViewport viewport = {};
            const float authoredWidth = width_ == 0 ? 1.0f : static_cast<float>(width_);
            const float authoredHeight = height_ == 0 ? 1.0f : static_cast<float>(height_);
            if (surfaceWidth <= 1.0f || surfaceHeight <= 1.0f)
            {
                viewport.width = authoredWidth;
                viewport.height = authoredHeight;
                viewport.scale = 1.0f;
                return viewport;
            }

            const float scaleX = surfaceWidth / authoredWidth;
            const float scaleY = surfaceHeight / authoredHeight;
            const float scale = scaleX < scaleY ? scaleX : scaleY;
            viewport.scale = scale <= 0.0f ? 1.0f : scale;
            viewport.width = authoredWidth * viewport.scale;
            viewport.height = authoredHeight * viewport.scale;
            viewport.x = (surfaceWidth - viewport.width) * 0.5f;
            viewport.y = (surfaceHeight - viewport.height) * 0.5f;
            return viewport;
        }

        POINT ClientCursorToLogicalUiPoint(const POINT& cursor) const
        {
            POINT logical = cursor;
            if (!hwnd_)
                return logical;

            RECT client = {};
            if (!GetClientRect(hwnd_, &client))
                return logical;

            const float clientWidth = static_cast<float>(client.right - client.left);
            const float clientHeight = static_cast<float>(client.bottom - client.top);
            if (clientWidth <= 1.0f || clientHeight <= 1.0f)
                return logical;

            // M31D_UI_LETTERBOX_CLIENT_SPACE: UI controls are lowered in
            // authored logical pixels. When the window is resized or maximized,
            // render into an aspect-preserving viewport and map mouse input back
            // through that same viewport. The previous fixed-client lock proved
            // the bug; this keeps the fix without forbidding resize like a tiny
            // bureaucrat guarding a 1280x720 rectangle.
            const LogicalViewport viewport = BuildLogicalViewport(clientWidth, clientHeight);
            logical.x = static_cast<LONG>(((static_cast<float>(cursor.x) - viewport.x) / viewport.scale) + 0.5f);
            logical.y = static_cast<LONG>(((static_cast<float>(cursor.y) - viewport.y) / viewport.scale) + 0.5f);
            return logical;
        }

        bool UiControlContains(const ArqenDx12UiControl& control, const POINT& cursor) const
        {
            return cursor.x >= control.x && cursor.y >= control.y &&
                cursor.x <= control.x + control.width && cursor.y <= control.y + control.height;
        }

        void InvokeUiAction(const ArqenDx12UiControl& control)
        {
            switch (control.action)
            {
            case ARQEN_DX12_UI_ACTION_TOGGLE_ANIMATION:
                animationPaused_ = control.checked == 0u;
                break;
            case ARQEN_DX12_UI_ACTION_TOGGLE_FAKE_LIGHT:
                fakeLightingEnabled_ = control.checked != 0u;
                break;
            default:
                break;
            }
        }

        void UpdateSliderValueFromCursor(ArqenDx12UiControl& control, const POINT& cursor)
        {
            const float trackX = control.trackWidth > 1.0f ? control.trackX : control.x;
            const float usableWidth = control.trackWidth > 1.0f ? control.trackWidth : (control.width <= 1.0f ? 1.0f : control.width);
            float ratio = (static_cast<float>(cursor.x) - trackX) / usableWidth;
            ratio = ClampFloat(ratio, 0.0f, 1.0f);
            const float range = control.maxValue > control.minValue ? (control.maxValue - control.minValue) : 1.0f;
            control.value = control.minValue + ratio * range;
            control.checked = control.value > control.minValue ? 1u : 0u;
        }

        bool UpdateUiOverlayInput()
        {
            if (!uiOverlayEnabled_ || uiControls_.empty() || !hwnd_)
                return false;

            POINT cursor = {};
            if (!GetCursorPos(&cursor))
                return false;
            ScreenToClient(hwnd_, &cursor);
            cursor = ClientCursorToLogicalUiPoint(cursor);

            hoveredUiControlIndex_ = -1;
            for (size_t i = 0; i < uiControls_.size(); ++i)
            {
                ArqenDx12UiControl& control = uiControls_[i];
                if (control.enabled == 0u)
                    continue;
                if (UiControlContains(control, cursor))
                    hoveredUiControlIndex_ = static_cast<int>(i);
            }

            const bool down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
            const bool pressed = down && !previousUiLeftDown_;
            const bool released = !down && previousUiLeftDown_;
            previousUiLeftDown_ = down;

            if (viewportNavigationActive_)
                return hoveredUiControlIndex_ >= 0;

            if (pressed)
            {
                pressedUiControlIndex_ = hoveredUiControlIndex_;
                if (pressedUiControlIndex_ >= 0)
                {
                    ArqenDx12UiControl& control = uiControls_[static_cast<size_t>(pressedUiControlIndex_)];
                    if (control.type == ARQEN_DX12_UI_CONTROL_SLIDER)
                        UpdateSliderValueFromCursor(control, cursor);
                    if (control.type == ARQEN_DX12_UI_CONTROL_INPUT_FIELD || control.type == ARQEN_DX12_UI_CONTROL_DROPDOWN)
                        focusedUiControlIndex_ = pressedUiControlIndex_;
                    return true;
                }
                focusedUiControlIndex_ = -1;
            }

            if (down && pressedUiControlIndex_ >= 0 && static_cast<size_t>(pressedUiControlIndex_) < uiControls_.size())
            {
                ArqenDx12UiControl& control = uiControls_[static_cast<size_t>(pressedUiControlIndex_)];
                if (control.type == ARQEN_DX12_UI_CONTROL_SLIDER && control.enabled != 0u)
                {
                    UpdateSliderValueFromCursor(control, cursor);
                    return true;
                }
            }

            if (released)
            {
                const int releasedIndex = pressedUiControlIndex_;
                pressedUiControlIndex_ = -1;
                if (releasedIndex >= 0 && releasedIndex == hoveredUiControlIndex_ && static_cast<size_t>(releasedIndex) < uiControls_.size())
                {
                    ArqenDx12UiControl& control = uiControls_[static_cast<size_t>(releasedIndex)];
                    if (control.enabled == 0u)
                        return true;
                    if (control.type == ARQEN_DX12_UI_CONTROL_BUTTON || control.type == ARQEN_DX12_UI_CONTROL_CHECKBOX || control.type == ARQEN_DX12_UI_CONTROL_DROPDOWN)
                        control.checked = control.checked ? 0u : 1u;
                    if (control.type == ARQEN_DX12_UI_CONTROL_BUTTON || control.type == ARQEN_DX12_UI_CONTROL_CHECKBOX || control.type == ARQEN_DX12_UI_CONTROL_DROPDOWN)
                        InvokeUiAction(control);
                    if (control.type == ARQEN_DX12_UI_CONTROL_INPUT_FIELD)
                        focusedUiControlIndex_ = releasedIndex;
                    return true;
                }
            }

            return hoveredUiControlIndex_ >= 0 || pressedUiControlIndex_ >= 0 || focusedUiControlIndex_ >= 0;
        }

        void UpdateObjectSelectorInput()
        {
            if (!objectSelectorEnabled_ || !drawCalls_ || drawCallCount_ == 0 || dynamicObjectTransforms_.empty())
                return;

            const UINT selectVk = MouseButtonVirtualKey(objectSelectButton_);
            if (selectVk != 0 && objectSelectButton_ < 8)
            {
                const bool down = (GetAsyncKeyState(static_cast<int>(selectVk)) & 0x8000) != 0;
                const bool pressed = down && !previousObjectSelectButtonDown_;
                previousObjectSelectButtonDown_ = down;
                if (pressed && !viewportNavigationActive_)
                    SelectObjectAtCursor();
            }

            if (!selectedObjectRotateBindings_ || selectedObjectRotateBindingCount_ == 0 || selectedObjectIndex_ < 0)
            {
                rotateMousePositionValid_ = false;
                return;
            }

            bool anyRotateDown = false;
            for (UINT i = 0; i < selectedObjectRotateBindingCount_; ++i)
            {
                const ArqenDx12SelectedObjectRotateBinding& binding = selectedObjectRotateBindings_[i];
                if (binding.virtualKey >= 256)
                    continue;
                const bool down = (GetAsyncKeyState(static_cast<int>(binding.virtualKey)) & 0x8000) != 0;
                anyRotateDown = anyRotateDown || down;
                if (!down || viewportNavigationActive_)
                    continue;

                POINT cursor = {};
                if (!GetCursorPos(&cursor))
                    continue;
                if (hwnd_)
                {
                    ScreenToClient(hwnd_, &cursor);
                    cursor = ClientCursorToLogicalUiPoint(cursor);
                }
                if (!rotateMousePositionValid_)
                {
                    lastRotateMouse_ = cursor;
                    rotateMousePositionValid_ = true;
                    continue;
                }

                const LONG dx = cursor.x - lastRotateMouse_.x;
                const LONG dy = cursor.y - lastRotateMouse_.y;
                lastRotateMouse_ = cursor;
                const float delta = binding.mouseAxis == ARQEN_DX12_SELECTOR_MOUSE_AXIS_X ? static_cast<float>(dx) : static_cast<float>(dy);
                RotateSelectedObject(binding.axis, delta * binding.sensitivity);
            }

            if (!anyRotateDown || viewportNavigationActive_)
                rotateMousePositionValid_ = false;
        }

        bool ProjectDrawCallBounds(const ArqenDx12DrawCall& drawCall, float& minX, float& minY, float& maxX, float& maxY, float& centerDepth) const
        {
            if (!baseVertices_ || drawCall.firstVertex >= baseVertexCount_ || IsArqenDx12UiDrawCall(drawCall.transformIndex) || drawCall.transformIndex >= objectTransformCount_)
                return false;

            const ArqenDx12ObjectTransform transform = ResolveTransform(drawCall.transformIndex);
            const UINT endVertex = drawCall.firstVertex + drawCall.vertexCount;
            bool any = false;
            minX = static_cast<float>(width_);
            minY = static_cast<float>(height_);
            maxX = 0.0f;
            maxY = 0.0f;
            float depthSum = 0.0f;
            UINT depthCount = 0;

            for (UINT v = drawCall.firstVertex; v < endVertex && v < baseVertexCount_; ++v)
            {
                const ArqenDx12VertexPositionColor projected = TransformVertex(baseVertices_[v], transform);
                if (!std::isfinite(projected.x) || !std::isfinite(projected.y))
                    continue;

                const float screenX = (projected.x * 0.5f + 0.5f) * static_cast<float>(width_);
                const float screenY = (0.5f - projected.y * 0.5f) * static_cast<float>(height_);
                if (screenX < minX) minX = screenX;
                if (screenY < minY) minY = screenY;
                if (screenX > maxX) maxX = screenX;
                if (screenY > maxY) maxY = screenY;
                depthSum += projected.z;
                depthCount++;
                any = true;
            }

            if (!any || depthCount == 0)
                return false;

            constexpr float Padding = 10.0f;
            constexpr float MinPickSize = 24.0f;
            minX -= Padding;
            minY -= Padding;
            maxX += Padding;
            maxY += Padding;
            const float width = maxX - minX;
            const float height = maxY - minY;
            if (width < MinPickSize)
            {
                const float mid = (minX + maxX) * 0.5f;
                minX = mid - MinPickSize * 0.5f;
                maxX = mid + MinPickSize * 0.5f;
            }
            if (height < MinPickSize)
            {
                const float mid = (minY + maxY) * 0.5f;
                minY = mid - MinPickSize * 0.5f;
                maxY = mid + MinPickSize * 0.5f;
            }
            centerDepth = depthSum / static_cast<float>(depthCount);
            return true;
        }

        void SelectObjectAtCursor()
        {
            if (!hwnd_ || !perspectiveCameraEnabled_)
                return;

            POINT cursor = {};
            if (!GetCursorPos(&cursor))
                return;
            ScreenToClient(hwnd_, &cursor);
            cursor = ClientCursorToLogicalUiPoint(cursor);

            float bestDepth = (std::numeric_limits<float>::max)();
            int bestIndex = -1;
            for (UINT i = 0; i < drawCallCount_; ++i)
            {
                float minX = 0.0f;
                float minY = 0.0f;
                float maxX = 0.0f;
                float maxY = 0.0f;
                float depth = 0.0f;
                if (!ProjectDrawCallBounds(drawCalls_[i], minX, minY, maxX, maxY, depth))
                    continue;

                const float cx = static_cast<float>(cursor.x);
                const float cy = static_cast<float>(cursor.y);
                if (cx >= minX && cx <= maxX && cy >= minY && cy <= maxY && depth < bestDepth)
                {
                    bestDepth = depth;
                    bestIndex = static_cast<int>(drawCalls_[i].transformIndex);
                }
            }

            selectedObjectIndex_ = bestIndex;
            rotateMousePositionValid_ = false;
        }

        void RotateSelectedObject(UINT axis, float deltaDegrees)
        {
            if (selectedObjectIndex_ < 0 || static_cast<UINT>(selectedObjectIndex_) >= dynamicObjectTransforms_.size())
                return;
            ArqenDx12ObjectTransform& transform = dynamicObjectTransforms_[static_cast<size_t>(selectedObjectIndex_)];
            if (axis == ARQEN_DX12_SELECTOR_ROTATE_AXIS_Y)
                transform.rotationYDegrees += deltaDegrees;
        }

        ArqenDx12VertexPositionColor ApplySelectedObjectFeedback(const ArqenDx12VertexPositionColor& vertex, UINT transformIndex) const
        {
            if (selectedObjectIndex_ < 0 || static_cast<UINT>(selectedObjectIndex_) != transformIndex)
                return vertex;

            return {
                vertex.x,
                vertex.y,
                vertex.z,
                ClampFloat(vertex.r * 0.82f + 0.10f, 0.0f, 1.0f),
                ClampFloat(vertex.g * 1.12f + 0.22f, 0.0f, 1.0f),
                ClampFloat(vertex.b * 1.22f + 0.30f, 0.0f, 1.0f),
                vertex.a
            };
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
                    if (IsArqenDx12UiDrawCall(drawCall.transformIndex))
                    {
                        for (UINT v = 0; v < drawCall.vertexCount; ++v)
                        {
                            const UINT index = drawCall.firstVertex + v;
                            if (index < baseVertexCount_)
                                out[index] = ApplyUiOverlayFeedback(baseVertices_[index], drawCall);
                        }
                        continue;
                    }
                    const ArqenDx12ObjectTransform transform = ResolveTransform(drawCall.transformIndex);
                    for (UINT v = 0; v < drawCall.vertexCount; ++v)
                    {
                        const UINT index = drawCall.firstVertex + v;
                        if (index < baseVertexCount_)
                            out[index] = ApplySelectedObjectFeedback(TransformVertex(baseVertices_[index], transform), drawCall.transformIndex);
                    }
                }
            }
            else
            {
                const ArqenDx12ObjectTransform transform = ResolveTransform(0);
                for (UINT i = 0; i < baseVertexCount_; ++i)
                    out[i] = ApplySelectedObjectFeedback(TransformVertex(baseVertices_[i], transform), 0);
            }
        }

        float PixelXToNdc(float x) const
        {
            const float w = width_ == 0 ? 1.0f : static_cast<float>(width_);
            return (x / w) * 2.0f - 1.0f;
        }

        ArqenDx12VertexPositionColor ApplyUiSliderDynamicGeometry(const ArqenDx12VertexPositionColor& vertex, const ArqenDx12DrawCall& drawCall, const ArqenDx12UiControl& control) const
        {
            if (control.type != ARQEN_DX12_UI_CONTROL_SLIDER || !baseVertices_ || drawCall.vertexCount == 0)
                return vertex;

            float oldMinX = (std::numeric_limits<float>::max)();
            float oldMaxX = -(std::numeric_limits<float>::max)();
            for (UINT v = 0; v < drawCall.vertexCount; ++v)
            {
                const UINT sourceIndex = drawCall.firstVertex + v;
                if (sourceIndex >= baseVertexCount_)
                    continue;
                oldMinX = oldMinX < baseVertices_[sourceIndex].x ? oldMinX : baseVertices_[sourceIndex].x;
                oldMaxX = oldMaxX > baseVertices_[sourceIndex].x ? oldMaxX : baseVertices_[sourceIndex].x;
            }
            if (oldMinX > oldMaxX)
                return vertex;

            const float range = control.maxValue > control.minValue ? (control.maxValue - control.minValue) : 1.0f;
            const float ratio = ClampFloat((control.value - control.minValue) / range, 0.0f, 1.0f);
            const UINT role = ArqenDx12UiControlRole(drawCall.transformIndex);
            const float oldMidX = (oldMinX + oldMaxX) * 0.5f;
            const bool rightSideVertex = vertex.x > oldMidX;

            float newLeft = oldMinX;
            float newRight = oldMaxX;
            if (role == ArqenDx12UiControlRoleSliderFill)
            {
                const float fillPixels = control.trackWidth > 1.0f ? (control.trackWidth * ratio) : ((control.width <= 1.0f ? 1.0f : control.width) * ratio);
                newLeft = PixelXToNdc(control.trackX);
                newRight = PixelXToNdc(control.trackX + (fillPixels < 2.0f ? 2.0f : fillPixels));
            }
            else if (role == ArqenDx12UiControlRoleSliderKnob)
            {
                const float knobHalfWidth = (oldMaxX - oldMinX) * 0.5f;
                const float center = PixelXToNdc(control.trackX + control.trackWidth * ratio);
                newLeft = center - knobHalfWidth;
                newRight = center + knobHalfWidth;
            }
            else
            {
                return vertex;
            }

            ArqenDx12VertexPositionColor out = vertex;
            out.x = rightSideVertex ? newRight : newLeft;
            return out;
        }

        ArqenDx12VertexPositionColor ApplyUiOverlayFeedback(const ArqenDx12VertexPositionColor& vertex, const ArqenDx12DrawCall& drawCall) const
        {
            if (!IsArqenDx12UiControlDrawCall(drawCall.transformIndex))
                return vertex;
            const UINT index = ArqenDx12UiControlIndex(drawCall.transformIndex);
            if (index >= uiControls_.size())
                return vertex;

            const ArqenDx12UiControl& control = uiControls_[index];
            ArqenDx12VertexPositionColor adjusted = ApplyUiSliderDynamicGeometry(vertex, drawCall, control);
            float r = adjusted.r;
            float g = adjusted.g;
            float b = adjusted.b;
            float a = adjusted.a;

            if (control.enabled == 0u)
            {
                r *= 0.38f; g *= 0.38f; b *= 0.42f; a *= 0.72f;
            }
            if (static_cast<int>(index) == hoveredUiControlIndex_ && control.enabled != 0u)
            {
                r = r * 1.10f + 0.05f;
                g = g * 1.15f + 0.07f;
                b = b * 1.20f + 0.10f;
            }
            if (static_cast<int>(index) == pressedUiControlIndex_ && control.enabled != 0u)
            {
                r = r * 0.72f;
                g = g * 0.78f;
                b = b * 0.92f + 0.08f;
            }
            if ((control.checked != 0u || static_cast<int>(index) == focusedUiControlIndex_) && control.enabled != 0u)
            {
                r = r * 0.84f + 0.08f;
                g = g * 1.13f + 0.14f;
                b = b * 1.22f + 0.22f;
            }

            return { adjusted.x, adjusted.y, adjusted.z, ClampFloat(r, 0.0f, 1.0f), ClampFloat(g, 0.0f, 1.0f), ClampFloat(b, 0.0f, 1.0f), ClampFloat(a, 0.0f, 1.0f) };
        }

        ArqenDx12ObjectTransform ResolveTransform(UINT index) const
        {
            if (sceneTransformsEnabled_ && objectTransforms_ && objectTransformCount_ > 0 && index < objectTransformCount_)
                return objectTransforms_[index];
            return { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f };
        }

        ArqenDx12VertexPositionColor TransformVertex(const ArqenDx12VertexPositionColor& src, const ArqenDx12ObjectTransform& transform) const
        {
            float x = src.x * transform.sx;
            float y = src.y * transform.sy;
            float z = src.z * transform.sz;

            float nx = src.x;
            float ny = src.y;
            float nz = src.z;
            Normalize3(nx, ny, nz);

            ApplyObjectRotation(transform, x, y, z);
            ApplyObjectRotation(transform, nx, ny, nz);

            x += transform.x;
            y += transform.y;
            z += transform.z;

            const ArqenDx12VertexPositionColor shaded = ShadeVertex(src, nx, ny, nz);

            if (perspectiveCameraEnabled_)
                return ProjectPerspectiveVertex(x, y, z, shaded);

            if (cameraEnabled_)
            {
                const float zoom = camera_.zoom <= 0.0001f ? 1.0f : camera_.zoom;
                x = (x - camera_.x) * zoom;
                y = (y - camera_.y) * zoom;
                z = z - camera_.z;
            }

            return { x, y, z, shaded.r, shaded.g, shaded.b, shaded.a };
        }

        static float ClampFloat(float value, float lo, float hi)
        {
            return value < lo ? lo : (value > hi ? hi : value);
        }

        static void Normalize3(float& x, float& y, float& z)
        {
            const float length = std::sqrt(x * x + y * y + z * z);
            if (length <= 0.000001f)
            {
                x = 0.0f;
                y = 0.0f;
                z = 1.0f;
                return;
            }
            x /= length;
            y /= length;
            z /= length;
        }

        static void RotateX(float radians, float& yy, float& zz)
        {
            const float c = std::cos(radians);
            const float s = std::sin(radians);
            const float ny = yy * c - zz * s;
            const float nz = yy * s + zz * c;
            yy = ny;
            zz = nz;
        }

        static void RotateY(float radians, float& xx, float& zz)
        {
            const float c = std::cos(radians);
            const float s = std::sin(radians);
            const float nx = xx * c + zz * s;
            const float nz = -xx * s + zz * c;
            xx = nx;
            zz = nz;
        }

        static void RotateZ(float radians, float& xx, float& yy)
        {
            const float c = std::cos(radians);
            const float s = std::sin(radians);
            const float nx = xx * c - yy * s;
            const float ny = xx * s + yy * c;
            xx = nx;
            yy = ny;
        }

        static float DegToRad(float degrees)
        {
            constexpr float Pi = 3.14159265358979323846f;
            return degrees * (Pi / 180.0f);
        }

        void ApplyObjectRotation(const ArqenDx12ObjectTransform& transform, float& x, float& y, float& z) const
        {
            RotateX(DegToRad(transform.rotationXDegrees), y, z);
            RotateY(DegToRad(transform.rotationYDegrees), x, z);
            RotateZ(DegToRad(transform.rotationZDegrees), x, y);
        }

        ArqenDx12VertexPositionColor ShadeVertex(const ArqenDx12VertexPositionColor& src, float nx, float ny, float nz) const
        {
            if (!fakeLightingEnabled_)
                return src;

            float lx = directionalLight_.x;
            float ly = directionalLight_.y;
            float lz = directionalLight_.z;
            Normalize3(lx, ly, lz);
            Normalize3(nx, ny, nz);
            const float ndotl = ClampFloat(-(nx * lx + ny * ly + nz * lz), 0.0f, 1.0f);
            const float ambient = ClampFloat(directionalLight_.ambient, 0.0f, 1.0f);
            const float intensity = ClampFloat(directionalLight_.intensity, 0.0f, 4.0f);
            const float factor = ClampFloat(ambient + ndotl * intensity, 0.0f, 1.35f);
            return { src.x, src.y, src.z, ClampFloat(src.r * factor, 0.0f, 1.0f), ClampFloat(src.g * factor, 0.0f, 1.0f), ClampFloat(src.b * factor, 0.0f, 1.0f), src.a };
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
            if (animationColors_ && animationColorCount_ > 0 && !animationPaused_)
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
        bool CreateRenderTargetViews(ArqenDx12ClearWindowResult* result)
        {
            D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = rtvHeap_->GetCPUDescriptorHandleForHeapStart();
            for (UINT i = 0; i < FrameCount; ++i)
            {
                renderTargets_[i].Reset();
                HRESULT hr = swapChain_->GetBuffer(i, IID_PPV_ARGS(&renderTargets_[i]));
                if (Failed(hr))
                    return Fail(result, hr, "backbuffer", "IDXGISwapChain::GetBuffer");

                device_->CreateRenderTargetView(renderTargets_[i].Get(), nullptr, rtvHandle);
                rtvHandle.ptr += rtvDescriptorSize_;
            }
            return true;
        }

        bool ResizeBackBufferToClientIfNeeded(ArqenDx12ClearWindowResult* result)
        {
            if (!hwnd_ || !swapChain_)
                return true;

            RECT client = {};
            if (!GetClientRect(hwnd_, &client))
                return true;

            const UINT newWidth = client.right > client.left ? static_cast<UINT>(client.right - client.left) : 0u;
            const UINT newHeight = client.bottom > client.top ? static_cast<UINT>(client.bottom - client.top) : 0u;
            if (newWidth < 1u || newHeight < 1u)
                return true;
            if (newWidth == backBufferWidth_ && newHeight == backBufferHeight_)
                return true;

            if (!WaitForGpu(result))
                return false;

            for (UINT i = 0; i < FrameCount; ++i)
                renderTargets_[i].Reset();
            depthStencil_.Reset();
            dsvHeap_.Reset();

            HRESULT hr = swapChain_->ResizeBuffers(FrameCount, newWidth, newHeight, DXGI_FORMAT_R8G8B8A8_UNORM, 0);
            if (Failed(hr))
                return Fail(result, hr, "resize", "IDXGISwapChain::ResizeBuffers");

            backBufferWidth_ = newWidth;
            backBufferHeight_ = newHeight;
            frameIndex_ = swapChain_->GetCurrentBackBufferIndex();

            if (!CreateRenderTargetViews(result))
                return false;
            if (depthEnabled_ && !CreateDepthResources(result))
                return false;
            return true;
        }

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
            D3D12_RESOURCE_DESC depthDesc = DepthResourceDesc(backBufferWidth_, backBufferHeight_);
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
            if (!ResizeBackBufferToClientIfNeeded(result))
                return false;

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
                const LogicalViewport logicalViewport = BuildLogicalViewport(static_cast<float>(backBufferWidth_), static_cast<float>(backBufferHeight_));

                D3D12_VIEWPORT viewport = {};
                viewport.TopLeftX = logicalViewport.x;
                viewport.TopLeftY = logicalViewport.y;
                viewport.Width = logicalViewport.width;
                viewport.Height = logicalViewport.height;
                viewport.MinDepth = 0.0f;
                viewport.MaxDepth = 1.0f;

                D3D12_RECT scissor = {};
                scissor.left = static_cast<LONG>(logicalViewport.x);
                scissor.top = static_cast<LONG>(logicalViewport.y);
                scissor.right = static_cast<LONG>(logicalViewport.x + logicalViewport.width + 0.5f);
                scissor.bottom = static_cast<LONG>(logicalViewport.y + logicalViewport.height + 0.5f);

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
        UINT backBufferWidth_ = 0;
        UINT backBufferHeight_ = 0;
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
        bool fakeLightingEnabled_ = false;
        ArqenDx12DirectionalLight directionalLight_ = { -0.35f, -0.70f, -0.60f, 0.85f, 0.18f };
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
        bool objectSelectorEnabled_ = false;
        UINT objectSelectButton_ = 0;
        const ArqenDx12SelectedObjectRotateBinding* selectedObjectRotateBindings_ = nullptr;
        UINT selectedObjectRotateBindingCount_ = 0;
        int selectedObjectIndex_ = -1;
        bool uiOverlayEnabled_ = false;
        std::vector<ArqenDx12UiControl> uiControls_;
        int hoveredUiControlIndex_ = -1;
        int pressedUiControlIndex_ = -1;
        int focusedUiControlIndex_ = -1;
        bool previousUiLeftDown_ = false;
        bool previousObjectSelectButtonDown_ = false;
        bool rotateMousePositionValid_ = false;
        POINT lastRotateMouse_ = { 0, 0 };
        std::vector<ArqenDx12ObjectTransform> dynamicObjectTransforms_;
        bool previousMouseButtonDown_[8] = {};
        POINT lastMouse_ = { 0, 0 };
        POINT mouseCenter_ = { 0, 0 };
        bool mousePositionValid_ = false;
        bool viewportNavigationActive_ = false;
        bool cursorVisible_ = true;
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
