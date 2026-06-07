# M18B DX12 Ready Gate

M18B does not implement DX12. It prepares the repository so DX12 can start without lying to the compiler, backend, or tests.

## Green means

```text
DX12 remains unsupported.
The current window/file/command-arg runtime actions are registered.
The backend capability table matches emitted runtime actions.
The wrapper cache key includes backend config, command specs, compiler binaries, and target.
The IR contract rejects reserved DX12 actions while the backend is not implemented.
The runtime contract reserves frame timing concepts for the real render loop.
```

## ready to start means

The next patch can begin runtime/DX12 architecture work without first fixing repo hygiene, missing capability gates, or stale cache assumptions.

## Not ready yet means

If any of these appear, DX12 work should stop:

- `dx12|supported` before backend implementation exists
- `frame_update|supported` before an update loop exists
- wrapper cache key missing backend config or command specs
- emitted runtime actions missing from backend capabilities
- backend-only IR path accepting unsupported actions
