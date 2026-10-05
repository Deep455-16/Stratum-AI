# install/

This folder contains the installation scripts for Stratum AI.

| Script | Machine | What it installs |
|--------|---------|-----------------|
| `install_intel.bat` | Intel / AMD (x86-64) | Python venv, llama-cpp-python, RAG deps, Qwen2.5-3B GGUF, MiniLM, BGE reranker |
| `install_snapdragon.bat` | Snapdragon X Elite / X2 Elite (ARM64) | Common RAG deps, onnxruntime-qnn, onnxruntime-genai, Qwen3-4B ONNX, MiniLM, BGE reranker |

## Usage

**Intel / AMD machine:**
```
install\install_intel.bat
```

**Snapdragon machine (Windows ARM64):**
```
install\install_snapdragon.bat
```

After installation, go to the `launchers\` folder to start the app.
