# launchers/

This folder contains the start scripts for Stratum AI.

| Script | Machine | LLM Backend |
|--------|---------|-------------|
| `start_intel.bat` | Intel / AMD (x86-64) | Qwen2.5-3B GGUF via llama.cpp → CPU |
| `start_snapdragon.bat` | Snapdragon X Elite / X2 Elite (ARM64) | Qwen3-4B ONNX via QNNExecutionProvider → NPU |

## Usage

Run **after** installation is complete.

**Intel / AMD machine:**
```
launchers\start_intel.bat
```

**Snapdragon machine:**
```
launchers\start_snapdragon.bat
```

Both launchers open Stratum AI at **http://127.0.0.1:8000**

The top-bar runtime badge will show the active backend and device.
