# DX12 Backend Contract (M18B Reservation)

DX12 is not implemented yet. This file defines the contract that must exist before the backend is allowed to become `supported` in `Backends/WindowsX64PE/Config/capabilities_v0.txt`.

## Status

```text
backend: DX12
status: reserved / unsupported
current gate: ready to start after runtime foundation
```

## Required backend concepts

A real DX12 backend must own these concepts explicitly:

- window handle ownership or interop with the window backend
- adapter/device creation
- command queue
- command allocator
- command list
- swapchain
- render target views
- descriptor heaps
- root signature
- pipeline state objects
- shader compilation / shader bytecode loading
- resource barriers
- frame synchronization / fences
- resize handling
- artifact diagnostics

## Required IR/action families

The following operations are reserved but unsupported in M18B:

```text
dx12
shader
render_pass
frame_update
```

They must remain `unsupported` until the backend can validate and execute them.

## No fake support rule

Do not mark `dx12`, `shader`, `render_pass`, or `frame_update` as `supported` only because a parser accepts the words. Support means the backend and runtime can execute the action safely and produce diagnostics on failure.

## M20A skeleton entry criteria

The first DX12 skeleton patch is allowed to do only a real clear-color window path after M19A runtime loop rules are in place. It must prove:

- the backend receives a real window handle or documented handoff
- device/swapchain/command queue creation has diagnostics
- clear color is executed by a command list, not a fake message-box path
- `dx12`, `render_pass`, `shader`, and `frame_update` remain unsupported until each action family has IR, runtime, backend, and tests
