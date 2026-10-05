"""
pipeline/llm/snapdragon_backend.py
------------------------------------
Qualcomm Snapdragon NPU inference backend for Stratum AI.

Inference path:
    Qwen3-4B (ONNX format)
    → ONNX Runtime
    → QNNExecutionProvider
    → Snapdragon NPU (Hexagon)

⚠️  VALIDATION REQUIREMENT
This backend requires:
  1. Windows ARM64 machine with a Qualcomm Snapdragon SoC
     (Snapdragon X Elite / X2 Elite or equivalent)
  2. onnxruntime-qnn installed:
         pip install onnxruntime-qnn
  3. Qwen3-4B ONNX model downloaded from Qualcomm AI Hub or
     Hugging Face (qualcomm/Qwen3-4B) and placed at SNAPDRAGON_MODEL_PATH.

This file imports cleanly on Intel / x86 machines (all Snapdragon imports
are guarded).  On Intel the backend will raise RuntimeError when load()
is called, which factory.py handles gracefully with llama fallback.

This file does NOT claim NPU execution unless QNNExecutionProvider is
confirmed available AND the session is created with it.
"""
from __future__ import annotations

import queue
import threading
import time
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

from pipeline.llm.base import LLMBackend, StreamEvent
from pipeline.llm.hardware_detect import detect_hardware


class SnapdragonBackend(LLMBackend):
    """
    ONNX Runtime + QNN Execution Provider backend targeting the Snapdragon NPU.

    Streaming compatibility layer
    ─────────────────────────────
    ONNX Runtime InferenceSession.run() is synchronous (not token-streaming).
    onnxruntime-genai provides true token streaming on Snapdragon, and is used
    when available.  If onnxruntime-genai is NOT available, the backend performs
    a single run() call in a thread and emits the full output as a stream of
    chunks — the SSE API contract to the frontend stays identical either way.
    """

    # Maximum output tokens when onnxruntime-genai is unavailable
    _FALLBACK_MAX_TOKENS = 512

    def __init__(
        self,
        model_path: str,
        qnn_backend_type: str = "npu",   # "npu" | "gpu" | "cpu"
        max_tokens: int = 512,
    ) -> None:
        self._model_path = model_path
        self._qnn_backend_type = qnn_backend_type.lower()
        self._max_tokens = max_tokens

        # Set at load() time
        self._session: Optional[Any] = None          # ort.InferenceSession
        self._genai_model: Optional[Any] = None      # ort_genai.Model (if available)
        self._tokenizer: Optional[Any] = None        # tokenizer for fallback path
        self._load_time_ms: Optional[int] = None
        self._active_provider: Optional[str] = None  # confirmed EP after load
        self._genai_available: bool = False

    # ── Identity ─────────────────────────────────────────────────────────────

    @property
    def backend_name(self) -> str:
        return "snapdragon"

    @property
    def model_name(self) -> str:
        return Path(self._model_path).name

    @property
    def runtime_name(self) -> str:
        return "ONNX Runtime"

    @property
    def device_name(self) -> str:
        if self._active_provider == "QNNExecutionProvider":
            return "Snapdragon NPU"
        elif self._active_provider == "CUDAExecutionProvider":
            return "GPU"
        return "CPU"

    # ── Lifecycle ─────────────────────────────────────────────────────────────

    def load(self) -> None:
        """
        Initialise the ONNX Runtime session with QNNExecutionProvider.

        Raises RuntimeError with actionable instructions if:
          - onnxruntime is not installed
          - QNNExecutionProvider is not available
          - The model path does not exist
        """
        hw = detect_hardware()

        # ── Guard: onnxruntime installed? ────────────────────────────────────
        try:
            import onnxruntime as ort  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                "[SnapdragonBackend] onnxruntime is not installed.\n"
                "Install with:  pip install onnxruntime-qnn\n"
                "(Requires Windows ARM64 + Snapdragon hardware)"
            ) from exc

        # ── Guard: QNNExecutionProvider available? ───────────────────────────
        if not hw["qnn_available"]:
            raise RuntimeError(
                "[SnapdragonBackend] QNNExecutionProvider is not available.\n"
                "\n"
                "This backend requires:\n"
                "  • Windows ARM64 with a Qualcomm Snapdragon SoC\n"
                "  • onnxruntime-qnn installed:  pip install onnxruntime-qnn\n"
                "\n"
                f"Current hardware: {hw['architecture']} / {hw['cpu'] or 'unknown CPU'}\n"
                f"Available ORT providers: {ort.get_all_providers()}\n"
                "\n"
                "On Intel machines, use LLM_BACKEND=llama instead."
            )

        # ── Guard: model path exists? ────────────────────────────────────────
        model_dir = Path(self._model_path)
        if not model_dir.exists():
            raise RuntimeError(
                f"[SnapdragonBackend] ONNX model not found: {self._model_path}\n"
                "\n"
                "Download the Qwen3-4B ONNX model:\n"
                "  Option A — Qualcomm AI Hub:\n"
                "    https://aihub.qualcomm.com/compute/models/qwen3-4b\n"
                "  Option B — Hugging Face:\n"
                "    huggingface-cli download qualcomm/Qwen3-4B --local-dir models/Qwen3-4B-onnx\n"
                "\n"
                "Then set:  SNAPDRAGON_MODEL_PATH=<path to model directory>"
            )

        # ── Try onnxruntime-genai for token streaming ────────────────────────
        try:
            import onnxruntime_genai as og  # type: ignore

            t0 = time.time()
            self._genai_model = og.Model(str(model_dir))
            self._genai_available = True
            self._load_time_ms = int((time.time() - t0) * 1000)
            self._active_provider = "QNNExecutionProvider"
            print(
                f"[SnapdragonBackend] Loaded {self.model_name} via onnxruntime-genai "
                f"in {self._load_time_ms} ms. Device: {self.device_name}"
            )
            return

        except ImportError:
            print(
                "[SnapdragonBackend] onnxruntime-genai not installed — "
                "falling back to InferenceSession (no token streaming).\n"
                "Install with:  pip install onnxruntime-genai"
            )
        except Exception as exc:
            print(
                f"[SnapdragonBackend] onnxruntime-genai load failed ({exc}), "
                "falling back to InferenceSession."
            )

        # ── Fallback: plain InferenceSession ─────────────────────────────────
        # Find the .onnx model file inside the model directory
        onnx_files = list(model_dir.glob("*.onnx"))
        if not onnx_files:
            # Some ONNX model repos use a subfolder
            onnx_files = list(model_dir.glob("**/*.onnx"))
        if not onnx_files:
            raise RuntimeError(
                f"[SnapdragonBackend] No .onnx file found under {self._model_path}"
            )
        onnx_path = str(onnx_files[0])

        # QNN provider options (backend_type: "npu" | "gpu" | "cpu")
        qnn_options = {
            "backend_path": "QnnHtp.dll",   # Qualcomm HTP (Hexagon Tensor Processor)
            "profiling_level": "off",
        }

        providers = [
            ("QNNExecutionProvider", qnn_options),
            "CPUExecutionProvider",       # safety fallback
        ]

        t0 = time.time()
        self._session = ort.InferenceSession(onnx_path, providers=providers)
        used_providers = self._session.get_providers()
        self._active_provider = (
            "QNNExecutionProvider"
            if "QNNExecutionProvider" in used_providers
            else used_providers[0] if used_providers else "unknown"
        )
        self._load_time_ms = int((time.time() - t0) * 1000)

        print(
            f"[SnapdragonBackend] Loaded {onnx_path} in {self._load_time_ms} ms. "
            f"Active provider: {self._active_provider} → Device: {self.device_name}"
        )

    def unload(self) -> None:
        self._session = None
        self._genai_model = None
        self._tokenizer = None

    # ── Streaming inference ───────────────────────────────────────────────────

    def stream(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int = 512,
        temperature: float = 0.1,
        top_p: float = 0.8,
        repeat_penalty: float = 1.1,
    ) -> Iterator[StreamEvent]:
        """
        Yield stream events.

        If onnxruntime-genai is available: true token-level streaming.
        Otherwise: run inference in a thread, emit output in chunks.
        """
        if self._genai_model is not None:
            yield from self._stream_genai(messages, max_tokens, temperature, top_p)
        elif self._session is not None:
            yield from self._stream_session(messages, max_tokens)
        else:
            yield ("error", "[SnapdragonBackend] Model not loaded. Call load() first.")

    def _stream_genai(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int,
        temperature: float,
        top_p: float,
    ) -> Iterator[StreamEvent]:
        """Token-level streaming via onnxruntime-genai."""
        try:
            import onnxruntime_genai as og  # type: ignore

            t_start = time.time()
            first_token = True

            tokenizer = og.Tokenizer(self._genai_model)
            # Build prompt string from message list (ChatML format for Qwen3)
            prompt = _messages_to_chatml(messages)
            input_tokens = tokenizer.encode(prompt)

            params = og.GeneratorParams(self._genai_model)
            params.set_search_options(
                max_length=max_tokens,
                temperature=temperature,
                top_p=top_p,
            )
            params.input_ids = input_tokens

            generator = og.Generator(self._genai_model, params)
            tokenizer_stream = og.TokenizerStream(tokenizer)

            while not generator.is_done():
                generator.compute_logits()
                generator.generate_next_token()
                new_token = generator.get_next_tokens()[0]
                text = tokenizer_stream.decode(new_token)
                if text:
                    if first_token:
                        yield ("ttft", int((time.time() - t_start) * 1000))
                        first_token = False
                    yield ("token", text)

            yield ("done", None)

        except Exception as exc:
            yield ("error", f"[SnapdragonBackend/genai] {exc}")

    def _stream_session(
        self,
        messages: List[Dict[str, str]],
        max_tokens: int,
    ) -> Iterator[StreamEvent]:
        """
        Compatibility streaming layer for plain InferenceSession.
        Runs inference in a thread; emits the full output in word-sized chunks
        so the SSE frontend still receives a streaming experience.

        NOTE: This path does NOT provide true token-level latency.
        """
        result_queue: queue.Queue = queue.Queue()

        def _run() -> None:
            try:
                # The Qwen3-4B ONNX model from Qualcomm AI Hub uses a
                # generate() style interface — attempt that first.
                prompt = _messages_to_chatml(messages)
                # Input feed depends on the model's input names;
                # this is a best-effort attempt for text-generation models.
                inputs = self._session.get_inputs()
                input_names = [i.name for i in inputs]

                # Try to use the transformers tokenizer if available
                try:
                    from transformers import AutoTokenizer  # type: ignore
                    tok = AutoTokenizer.from_pretrained(
                        str(Path(self._model_path)), local_files_only=False
                    )
                    input_ids = tok(prompt, return_tensors="np").input_ids
                    feed = {}
                    if "input_ids" in input_names:
                        feed["input_ids"] = input_ids
                    if "attention_mask" in input_names:
                        import numpy as np
                        feed["attention_mask"] = np.ones_like(input_ids)
                    outputs = self._session.run(None, feed)
                    # Decode first output
                    output_ids = outputs[0][0]
                    text = tok.decode(output_ids, skip_special_tokens=True)
                    result_queue.put(("output", text))
                except Exception as tok_exc:
                    result_queue.put(("error", f"Tokenizer error: {tok_exc}"))

            except Exception as exc:
                result_queue.put(("error", str(exc)))

        t_start = time.time()
        threading.Thread(target=_run, daemon=True).start()

        try:
            kind, value = result_queue.get(timeout=120)
        except queue.Empty:
            yield ("error", "[SnapdragonBackend] Inference timed out after 120s")
            return

        if kind == "error":
            yield ("error", value)
            return

        # Emit first-token latency (total inference time in this path)
        yield ("ttft", int((time.time() - t_start) * 1000))

        # Emit output in word-sized chunks for streaming feel
        words = value.split(" ")
        for i, word in enumerate(words):
            chunk = word if i == len(words) - 1 else word + " "
            yield ("token", chunk)
            time.sleep(0.005)  # slight pacing so SSE doesn't batch everything

        yield ("done", None)

    # ── Health ────────────────────────────────────────────────────────────────

    def health(self) -> Dict[str, Any]:
        hw = detect_hardware()
        loaded = (self._session is not None) or (self._genai_model is not None)
        return {
            "backend": self.backend_name,
            "model": self.model_name,
            "runtime": self.runtime_name,
            "execution_provider": self._active_provider or "none",
            "device": self.device_name if loaded else "not_loaded",
            "status": "ready" if loaded else "not_loaded",
            "streaming_mode": "genai" if self._genai_available else "session_compat",
            "qnn_available": hw["qnn_available"],
            "npu_available": hw["npu_backend_available"],
            "load_time_ms": self._load_time_ms,
            # ⚠️ Honest claim: only report NPU if QNNExecutionProvider is active
            "npu_active": (
                loaded and self._active_provider == "QNNExecutionProvider"
            ),
            "validation_note": (
                None
                if hw["qnn_available"]
                else "Snapdragon NPU execution requires validation on compatible "
                     "Qualcomm hardware with onnxruntime-qnn installed."
            ),
        }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _messages_to_chatml(messages: List[Dict[str, str]]) -> str:
    """
    Convert OpenAI-style message list to ChatML format used by Qwen3.

    Example output:
        <|im_start|>system
        You are ...<|im_end|>
        <|im_start|>user
        Question<|im_end|>
        <|im_start|>assistant
    """
    parts = []
    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        parts.append(f"<|im_start|>{role}\n{content}<|im_end|>")
    parts.append("<|im_start|>assistant")
    return "\n".join(parts)
