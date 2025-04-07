#!/bin/bash

echo "--- Starting Project Setup ---"

# === PART 1: Create Directories and Files ===

echo "Step 1: Creating directories..."
# Create base directories
mkdir -p app/api/routers app/api/schemas app/compat app/core app/inference app/models config
echo "Directories created."

echo "Step 2: Creating configuration and code files..."

# .env
cat << EOF > .env
# .env
ENVIRONMENT=development
LOG_LEVEL=INFO
# Set to "cpu" if you don't have a CUDA-enabled GPU or compatible PyTorch build
INFERENCE_DEVICE=cuda:0
MODEL_CONFIG_PATH=config/models.yaml
EOF
echo "  - Created .env"

# config/models.yaml
cat << EOF > config/models.yaml
# config/models.yaml
models:
  - model_id: "mistral-7b-instruct" # User-facing ID for the API
    model_name: "mistralai/Mistral-7B-Instruct-v0.1" # Hugging Face model name/path
    task: "chat" # Type of task: 'chat' or 'embedding'
    model_kwargs: # Optional kwargs passed to from_pretrained
      torch_dtype: "float16" # Use "auto" or specific type like "float16", "bfloat16"
      trust_remote_code: True # Needed for some models

  - model_id: "bge-small-en"
    model_name: "BAAI/bge-small-en-v1.5"
    task: "embedding"
    model_kwargs:
      torch_dtype: "float16"
      trust_remote_code: False
EOF
echo "  - Created config/models.yaml"

# requirements.txt
cat << EOF > requirements.txt
# requirements.txt
fastapi>=0.100.0
uvicorn[standard]>=0.23.0
pydantic>=1.10.0,<2.0.0 # Or Pydantic v2 if schemas updated
PyYAML>=6.0
python-dotenv>=1.0.0
torch>=2.0.0 # Ensure CUDA version matches if using GPU
transformers>=4.30.0
accelerate>=0.21.0 # Often needed by transformers for optimal loading/inference
sse-starlette>=1.6.5 # For Server-Sent Events streaming
sentencepiece # Dependency for many tokenizers like Llama/Mistral
protobuf # Dependency for many tokenizers
EOF
echo "  - Created requirements.txt"

# app/main.py
cat << EOF > app/main.py
# app/main.py
import logging
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.lifespan import lifespan_handler
from app.core.config import settings
from app.api.routers import chat, embeddings, models, health

# Setup logging
logging.basicConfig(level=settings.log_level.upper())
logger = logging.getLogger(__name__)

def create_app() -> FastAPI:
    logger.info("Creating FastAPI application...")
    app = FastAPI(
        title="OpenAI-Compatible AI Platform",
        version="1.0.0",
        lifespan=lifespan_handler,
    )

    # Add CORS middleware (adjust origins as needed for security)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"], # Allows all origins
        allow_credentials=True,
        allow_methods=["*"], # Allows all methods
        allow_headers=["*"], # Allows all headers
    )

    # Register API routers
    logger.info("Registering API routers...")
    app.include_router(chat.router, prefix="/v1", tags=["Chat"])
    app.include_router(embeddings.router, prefix="/v1", tags=["Embeddings"])
    app.include_router(models.router, prefix="/v1", tags=["Models"])
    app.include_router(health.router, prefix="/", tags=["Health"])
    logger.info("Routers registered successfully.")

    return app

app = create_app()

# Entrypoint for \`uvicorn app.main:app\`
if __name__ == "__main__":
    logger.info("Starting Uvicorn server...")
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.environment == "development", # Enable reload only in dev
        log_level=settings.log_level.lower()
    )
EOF
echo "  - Created app/main.py"

# app/core/config.py
cat << EOF > app/core/config.py
# app/core/config.py
import yaml
import logging
from pathlib import Path
from typing import List, Dict, Any, Optional
from pydantic import BaseSettings, Field, validator # Corrected: Removed BaseModel import if not used directly
import torch # Import torch here for dtype conversion

logger = logging.getLogger(__name__)

class AppSettings(BaseSettings):
    environment: str = Field("development", env="ENVIRONMENT")
    log_level: str = Field("INFO", env="LOG_LEVEL")
    model_config_path: str = Field("config/models.yaml", env="MODEL_CONFIG_PATH")
    inference_device: str = Field("cuda:0", env="INFERENCE_DEVICE") # e.g., "cuda:0", "cpu"

    class Config:
        env_file = ".env"
        extra = "ignore"

class ModelKwargs(BaseSettings):
    # Flexible kwargs for Hugging Face's from_pretrained
    # Example: torch_dtype, trust_remote_code, revision, etc.
    torch_dtype: Optional[str] = "auto" # Can be "float16", "bfloat16", "float32", "auto"
    trust_remote_code: Optional[bool] = False
    # Add other potential kwargs as needed

    # Convert string dtype to actual torch.dtype
    @validator('torch_dtype', pre=True, allow_reuse=True)
    def parse_torch_dtype(cls, value):
        if isinstance(value, str):
            value = value.lower()
            if value == "auto":
                return "auto"
            elif value == "float16":
                return torch.float16
            elif value == "bfloat16":
                return torch.bfloat16
            elif value == "float32":
                return torch.float32
        return value # Return as is if not a recognized string or already correct type

    class Config:
        extra = "allow" # Allow any extra fields passed in YAML

class ModelConfig(BaseSettings):
    model_id: str # User-facing ID (e.g., "mistral-7b")
    model_name: str # Hugging Face path (e.g., "mistralai/Mistral-7B-Instruct-v0.1")
    task: str # "chat" or "embedding"
    model_kwargs: ModelKwargs = Field(default_factory=ModelKwargs)

    class Config:
        extra = "ignore" # Ignore extra fields at the top level of model config entry

def load_model_config(path: str) -> List[ModelConfig]:
    config_path = Path(path)
    if not config_path.is_file():
        logger.error(f"Model config file not found at {config_path}")
        raise FileNotFoundError(f"Model config file not found at {config_path}")

    try:
        with open(config_path, "r") as f:
            raw_config = yaml.safe_load(f)
            if not raw_config or "models" not in raw_config:
                logger.warning(f"Model config file {config_path} is empty or missing 'models' key.")
                return []

        models = [ModelConfig(**item) for item in raw_config.get("models", [])]
        logger.info(f"Successfully loaded {len(models)} model configurations from {config_path}")
        return models
    except yaml.YAMLError as e:
        logger.error(f"Error parsing YAML file {config_path}: {e}", exc_info=True)
        raise ValueError(f"Error parsing model config file: {e}")
    except Exception as e:
        logger.error(f"Failed to load model configurations from {config_path}: {e}", exc_info=True)
        raise e

# Singleton instances
settings = AppSettings()
model_configs = load_model_config(settings.model_config_path)
EOF
echo "  - Created app/core/config.py"

# app/core/lifespan.py
cat << EOF > app/core/lifespan.py
# app/core/lifespan.py
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
import torch # Import torch for cleanup

from app.core.config import model_configs, settings
from app.models.manager import ModelManager
from app.models.loader import load_model_and_tokenizer

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan_handler(app: FastAPI):
    # === Startup ===
    logger.info("Application startup sequence initiated...")
    loaded_models = 0
    try:
        logger.info(f"Attempting to load {len(model_configs)} model(s) onto device '{settings.inference_device}'...")
        for model_cfg in model_configs:
            try:
                logger.info(f"Loading model: ID='{model_cfg.model_id}', Name='{model_cfg.model_name}', Task='{model_cfg.task}'")
                model, tokenizer = load_model_and_tokenizer(
                    model_name_or_path=model_cfg.model_name,
                    task=model_cfg.task,
                    device=settings.inference_device,
                    model_kwargs=model_cfg.model_kwargs.dict() # Pass validated kwargs dict
                )
                ModelManager.register_model(
                    model_id=model_cfg.model_id,
                    model=model,
                    tokenizer=tokenizer,
                    task=model_cfg.task,
                    device=settings.inference_device # Store device info
                )
                loaded_models += 1
            except Exception as e:
                logger.error(f"Failed to load model '{model_cfg.model_id}' ({model_cfg.model_name}): {e}", exc_info=True)
                # Decide whether to continue or raise - here we log and continue
        if loaded_models > 0:
            logger.info(f"Successfully loaded {loaded_models} model(s).")
        else:
            logger.warning("No models were loaded during startup.")
        if loaded_models < len(model_configs):
             logger.warning(f"{len(model_configs) - loaded_models} model(s) failed to load.")

    except Exception as e:
        logger.critical(f"A critical error occurred during model loading: {e}", exc_info=True)
        # Depending on requirements, you might want to raise e here to stop the app
        # raise e

    yield  # === App runs here ===

    # === Shutdown ===
    logger.info("Application shutdown sequence initiated...")
    try:
        logger.info("Clearing model manager...")
        ModelManager.clear()
        logger.info("Model manager cleared.")
        # Attempt to clear GPU memory if CUDA is used
        if "cuda" in settings.inference_device and torch.cuda.is_available():
            logger.info("Clearing CUDA cache...")
            torch.cuda.empty_cache()
            logger.info("CUDA cache cleared.")
    except Exception as e:
        logger.error(f"Error during shutdown cleanup: {e}", exc_info=True)
    finally:
        logger.info("Shutdown sequence complete.")
EOF
echo "  - Created app/core/lifespan.py"

# app/models/loader.py
cat << EOF > app/models/loader.py
# app/models/loader.py
import logging
from typing import Tuple, Dict, Any
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, AutoModel, PreTrainedModel, PreTrainedTokenizerBase

logger = logging.getLogger(__name__)

def load_model_and_tokenizer(
    model_name_or_path: str,
    task: str,
    device: str = "cuda:0",
    model_kwargs: Dict[str, Any] = None
) -> Tuple[PreTrainedModel, PreTrainedTokenizerBase]:
    """
    Loads a Hugging Face model and tokenizer based on the specified task.

    Args:
        model_name_or_path (str): The name or path of the model in Hugging Face Hub.
        task (str): The task type, e.g., "chat" or "embedding".
        device (str): The device to load the model onto ("cuda:0", "cpu", etc.).
        model_kwargs (Dict[str, Any], optional): Additional keyword arguments for
                                                \`from_pretrained\`. Defaults to None.

    Returns:
        Tuple[PreTrainedModel, PreTrainedTokenizerBase]: The loaded model and tokenizer.

    Raises:
        ValueError: If the task is unsupported or model loading fails.
        Exception: For underlying Hugging Face or Torch errors.
    """
    if model_kwargs is None:
        model_kwargs = {}

    resolved_dtype = model_kwargs.pop("torch_dtype", "auto") # Use provided dtype or default to auto
    trust_remote_code = model_kwargs.pop("trust_remote_code", False) # Use provided or default

    logger.info(f"Loading tokenizer for '{model_name_or_path}'...")
    try:
        tokenizer = AutoTokenizer.from_pretrained(
            model_name_or_path,
            trust_remote_code=trust_remote_code
        )
        logger.info("Tokenizer loaded successfully.")
    except Exception as e:
        logger.error(f"Failed to load tokenizer for '{model_name_or_path}': {e}", exc_info=True)
        raise ValueError(f"Could not load tokenizer: {e}")

    logger.info(f"Loading model '{model_name_or_path}' for task '{task}' with dtype '{resolved_dtype}'...")
    try:
        if task == "chat":
            model = AutoModelForCausalLM.from_pretrained(
                model_name_or_path,
                torch_dtype=resolved_dtype,
                trust_remote_code=trust_remote_code,
                **model_kwargs # Pass remaining kwargs
            )
        elif task == "embedding":
            model = AutoModel.from_pretrained(
                model_name_or_path,
                torch_dtype=resolved_dtype,
                trust_remote_code=trust_remote_code,
                **model_kwargs
            )
        else:
            raise ValueError(f"Unsupported task type: '{task}'. Must be 'chat' or 'embedding'.")

        logger.info(f"Model loaded successfully. Moving to device: '{device}'")
        model.to(device)
        model.eval() # Set model to evaluation mode
        logger.info(f"Model '{model_name_or_path}' is ready on device '{device}'.")
        return model, tokenizer

    except Exception as e:
        logger.error(f"Failed to load model '{model_name_or_path}' for task '{task}': {e}", exc_info=True)
        # Clean up tokenizer if model loading failed? Maybe not necessary.
        raise ValueError(f"Could not load model: {e}")
EOF
echo "  - Created app/models/loader.py"

# app/models/manager.py
cat << EOF > app/models/manager.py
# app/models/manager.py
import logging
import threading
from typing import Dict, Tuple, Optional, Any
from transformers import PreTrainedModel, PreTrainedTokenizerBase

logger = logging.getLogger(__name__)

ModelEntry = Tuple[PreTrainedModel, PreTrainedTokenizerBase, str, str] # model, tokenizer, task, device

class ModelManager:
    """
    A thread-safe global registry for loaded Hugging Face models and tokenizers.
    Maps a user-defined model_id to the loaded artifacts and metadata.
    """
    _lock = threading.Lock()
    # Stores: model_id -> (model_object, tokenizer_object, task_string, device_string)
    _models: Dict[str, ModelEntry] = {}

    @classmethod
    def register_model(
        cls,
        model_id: str,
        model: PreTrainedModel,
        tokenizer: PreTrainedTokenizerBase,
        task: str,
        device: str
    ) -> None:
        """Registers a loaded model and tokenizer."""
        with cls._lock:
            if model_id in cls._models:
                logger.warning(f"Overwriting existing model registration for ID: {model_id}")
            cls._models[model_id] = (model, tokenizer, task, device)
            logger.info(f"Registered model: ID='{model_id}', Task='{task}', Device='{device}'")

    @classmethod
    def get(cls, model_id: str) -> Optional[ModelEntry]:
        """Retrieves a registered model entry by its ID."""
        with cls._lock:
            entry = cls._models.get(model_id)
            if entry is None:
                logger.warning(f"Attempted to access non-existent model ID: {model_id}")
            return entry

    @classmethod
    def list_models(cls) -> Dict[str, Dict[str, Any]]:
        """Lists all registered models with their ID, task, and device."""
        with cls._lock:
            # Return a copy to avoid modification issues outside the lock
            return {
                model_id: {"task": task, "device": device}
                for model_id, (_, _, task, device) in cls._models.items()
            }

    @classmethod
    def clear(cls) -> None:
        """Clears all registered models. (Use with caution, models might still be in memory)."""
        with cls._lock:
            count = len(cls._models)
            # Consider adding explicit deletion or moving models to CPU before clearing
            # For now, just clear the dictionary reference. Python GC should handle it eventually.
            cls._models.clear()
            if count > 0:
                logger.info(f"Cleared {count} model(s) from the manager.")
            else:
                logger.info("Model manager cleared (was already empty).")
EOF
echo "  - Created app/models/manager.py"

# app/inference/engine.py
cat << EOF > app/inference/engine.py
# app/inference/engine.py
import logging
from typing import Dict, Any, Union, AsyncGenerator

from app.models.manager import ModelManager
from app.inference.generate import generate_text_stream, generate_text_non_stream
from app.inference.embed import generate_embedding
from app.api.schemas.openai import ChatCompletionRequest, EmbeddingRequest # Import schemas for type hint clarity

logger = logging.getLogger(__name__)

async def run_inference(
    request: Union[ChatCompletionRequest, EmbeddingRequest]
) -> Union[Dict[str, Any], AsyncGenerator[Dict[str, Any], None], Dict[str, Any]]: # Corrected return type annotation
    """
    Main entry point for running inference based on the request type and model task.

    Args:
        request: Either a ChatCompletionRequest or EmbeddingRequest Pydantic model.

    Returns:
        Either a dictionary (for non-streaming chat or embeddings) or an
        async generator yielding dictionaries (for streaming chat).

    Raises:
        ValueError: If the requested model is not loaded or task is unsupported.
        HTTPException: Can be raised from underlying functions for API errors.
    """
    model_id = request.model
    logger.info(f"Received inference request for model_id='{model_id}'")

    model_entry = ModelManager.get(model_id)
    if model_entry is None:
        logger.error(f"Model '{model_id}' not found in ModelManager.")
        raise ValueError(f"Model '{model_id}' is not loaded or available.")

    model, tokenizer, task, device = model_entry
    logger.debug(f"Found model '{model_id}': task='{task}', device='{device}'")

    if isinstance(request, ChatCompletionRequest) and task == "chat":
        logger.info(f"Processing ChatCompletion request for model '{model_id}' (Stream: {request.stream})")
        if request.stream:
            # Return the async generator directly
            return generate_text_stream(model, tokenizer, request, device)
        else:
            # Await the non-streaming result
            return await generate_text_non_stream(model, tokenizer, request, device)

    elif isinstance(request, EmbeddingRequest) and task == "embedding":
        logger.info(f"Processing Embedding request for model '{model_id}'")
        # Embeddings are typically not streamed in the OpenAI API style
        return await generate_embedding(model, tokenizer, request, device)

    else:
        # This case handles mismatches, e.g., embedding request for a chat model
        logger.error(f"Mismatched request type/task for model '{model_id}'. Request: {type(request).__name__}, Task: {task}")
        raise ValueError(f"Model '{model_id}' (task: {task}) cannot handle request type {type(request).__name__}.")
EOF
echo "  - Created app/inference/engine.py"

# app/inference/generate.py
cat << EOF > app/inference/generate.py
# app/inference/generate.py
import logging
import time
import threading
from typing import Dict, Any, AsyncGenerator, List
import torch
from transformers import PreTrainedModel, PreTrainedTokenizerBase, TextIteratorStreamer, StoppingCriteriaList, StoppingCriteria
from app.api.schemas.openai import ChatCompletionRequest, ChatMessage # Import for type clarity
from app.inference.utils import count_tokens # Import token counter

logger = logging.getLogger(__name__)

# Helper function to apply chat template (moved here for direct access to tokenizer)
def apply_chat_template(tokenizer: PreTrainedTokenizerBase, messages: List[ChatMessage]) -> str:
    """Applies the tokenizer's chat template to a list of messages."""
    try:
        # Convert Pydantic models to dicts
        message_dicts = [msg.dict() for msg in messages]
        prompt = tokenizer.apply_chat_template(message_dicts, tokenize=False, add_generation_prompt=True)
        return prompt
    except Exception as e:
        logger.error(f"Failed to apply chat template: {e}. Falling back to basic formatting.", exc_info=True)
        # Basic fallback (less reliable)
        prompt_str = ""
        for msg in messages:
            prompt_str += f"<|{msg.role}|>\\n{msg.content}\\n" # Escaped newlines for bash heredoc
        prompt_str += "<|assistant|>\\n" # Escaped newlines
        return prompt_str

# Basic stopping criteria based on stop strings
class StopOnTokens(StoppingCriteria):
    def __init__(self, tokenizer: PreTrainedTokenizerBase, stop_sequences: List[str]):
        self.tokenizer = tokenizer
        # Encode stop sequences immediately
        self.stop_token_ids = [
            tokenizer.encode(seq, add_special_tokens=False) for seq in stop_sequences if seq
        ]
        if not self.stop_token_ids:
             logger.warning("No valid stop sequences provided or tokenized.")
        else:
             logger.info(f"Stop sequences tokenized to IDs: {self.stop_token_ids}")

    def __call__(self, input_ids: torch.LongTensor, scores: torch.FloatTensor, **kwargs) -> bool:
        # Check if the end of the generated sequence matches any stop sequence
        for stop_ids in self.stop_token_ids:
            if len(input_ids[0]) >= len(stop_ids):
                 # Check if the last tokens match the stop sequence
                 if torch.equal(input_ids[0][-len(stop_ids):], torch.tensor(stop_ids, device=input_ids.device)):
                     logger.debug(f"Stopping criteria met: Detected stop sequence.")
                     return True
        return False

async def generate_text_non_stream(
    model: PreTrainedModel,
    tokenizer: PreTrainedTokenizerBase,
    request: ChatCompletionRequest,
    device: str
) -> Dict[str, Any]:
    """Generates text without streaming."""
    start_time = time.time()
    prompt = apply_chat_template(tokenizer, request.messages)
    prompt_tokens = count_tokens(tokenizer, prompt)
    logger.debug(f"Generated prompt (non-stream) with {prompt_tokens} tokens.")

    inputs = tokenizer(prompt, return_tensors="pt").to(device)

    # Generation kwargs
    gen_kwargs = {
        "max_new_tokens": request.max_tokens,
        "temperature": request.temperature,
        "top_p": request.top_p,
        "do_sample": request.temperature > 0, # Sample only if temperature > 0
        "pad_token_id": tokenizer.eos_token_id,
        # Add more parameters as needed (top_k, repetition_penalty, etc.)
    }

    # Add stopping criteria if stop sequences are provided
    stop_sequences = request.stop if request.stop else []
    if isinstance(stop_sequences, str):
        stop_sequences = [stop_sequences]
    if stop_sequences:
        stopping_criteria = StoppingCriteriaList([StopOnTokens(tokenizer, stop_sequences)])
        gen_kwargs["stopping_criteria"] = stopping_criteria
        logger.debug(f"Using stopping criteria with sequences: {stop_sequences}")

    logger.info(f"Starting non-streamed generation for model '{request.model}'...")
    with torch.no_grad():
        output_ids = model.generate(**inputs, **gen_kwargs)

    # Remove input tokens from the output
    output_ids = output_ids[:, inputs.input_ids.shape[1]:]
    generated_text = tokenizer.decode(output_ids[0], skip_special_tokens=True)

    completion_tokens = count_tokens(tokenizer, generated_text)
    total_tokens = prompt_tokens + completion_tokens
    end_time = time.time()

    logger.info(f"Non-streamed generation completed in {end_time - start_time:.2f}s. Tokens: {completion_tokens}")

    return {
        "text": generated_text,
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        },
        "finish_reason": "stop" # Basic reason, could be refined by checking output vs max_tokens or stop sequence hit
    }

async def generate_text_stream(
    model: PreTrainedModel,
    tokenizer: PreTrainedTokenizerBase,
    request: ChatCompletionRequest,
    device: str
) -> AsyncGenerator[Dict[str, Any], None]:
    """Generates text token by token using TextIteratorStreamer."""
    start_time = time.time()
    prompt = apply_chat_template(tokenizer, request.messages)
    prompt_tokens = count_tokens(tokenizer, prompt)
    logger.debug(f"Generated prompt (stream) with {prompt_tokens} tokens.")

    inputs = tokenizer(prompt, return_tensors="pt").to(device)
    streamer = TextIteratorStreamer(tokenizer, skip_prompt=True, skip_special_tokens=True)

    # Generation kwargs (similar to non-stream, but using streamer)
    gen_kwargs = {
        "input_ids": inputs.input_ids,
        "attention_mask": inputs.attention_mask,
        "streamer": streamer,
        "max_new_tokens": request.max_tokens,
        "temperature": request.temperature,
        "top_p": request.top_p,
        "do_sample": request.temperature > 0,
        "pad_token_id": tokenizer.eos_token_id,
    }

    # Add stopping criteria if stop sequences are provided
    stop_sequences = request.stop if request.stop else []
    if isinstance(stop_sequences, str):
        stop_sequences = [stop_sequences]
    if stop_sequences:
        stopping_criteria = StoppingCriteriaList([StopOnTokens(tokenizer, stop_sequences)])
        gen_kwargs["stopping_criteria"] = stopping_criteria
        logger.debug(f"Using stopping criteria with sequences: {stop_sequences}")

    # Run generation in a separate thread as it's blocking
    thread = threading.Thread(target=model.generate, kwargs=gen_kwargs)
    thread.start()

    logger.info(f"Starting streamed generation for model '{request.model}'...")
    completion_tokens = 0
    finish_reason = "stop" # Default finish reason

    generated_text_so_far = ""
    try:
        for token_text in streamer:
            generated_text_so_far += token_text
            completion_tokens += 1 # Approx. 1 token per stream item
            yield {
                "delta": token_text,
                "usage": None, # Usage updated at the end
                "finish_reason": None
            }
            # Check stop sequences manually here if needed, although StopOnTokens should handle it
            # if any(seq in generated_text_so_far for seq in stop_sequences):
            #     logger.info("Stop sequence detected during streaming.")
            #     finish_reason = "stop"
            #     break # Stop yielding

        # Wait for the generation thread to finish
        thread.join()
        logger.info(f"Stream generation thread finished.")

        # Check if max_tokens was reached
        if completion_tokens >= request.max_tokens:
            finish_reason = "length"
            logger.info("Streaming finished due to max_tokens.")

    except Exception as e:
         logger.error(f"Error during streaming generation: {e}", exc_info=True)
         finish_reason = "error" # Or some other indicator
    finally:
        # Final yield with usage and finish reason
        total_tokens = prompt_tokens + completion_tokens
        end_time = time.time()
        logger.info(f"Streamed generation completed in {end_time - start_time:.2f}s. Tokens: ~{completion_tokens}")

        yield {
             "delta": None, # No more text
             "usage": {
                 "prompt_tokens": prompt_tokens,
                 "completion_tokens": completion_tokens,
                 "total_tokens": total_tokens,
             },
             "finish_reason": finish_reason
         }
EOF
echo "  - Created app/inference/generate.py"

# app/inference/embed.py
cat << EOF > app/inference/embed.py
# app/inference/embed.py
import logging
import time
from typing import Dict, Any, List
import torch
from transformers import PreTrainedModel, PreTrainedTokenizerBase
from app.api.schemas.openai import EmbeddingRequest # Import for type clarity
from app.inference.utils import count_tokens # Import token counter

logger = logging.getLogger(__name__)

# Pooling strategy helper (Mean Pooling)
def mean_pooling(model_output, attention_mask):
    token_embeddings = model_output.last_hidden_state
    input_mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
    # Sum embeddings and divide by the number of non-padding tokens
    sum_embeddings = torch.sum(token_embeddings * input_mask_expanded, 1)
    sum_mask = torch.clamp(input_mask_expanded.sum(1), min=1e-9)
    return sum_embeddings / sum_mask

async def generate_embedding(
    model: PreTrainedModel,
    tokenizer: PreTrainedTokenizerBase,
    request: EmbeddingRequest,
    device: str
) -> Dict[str, Any]:
    """
    Computes embeddings for the input texts using mean pooling.
    """
    start_time = time.time()
    texts = request.input
    if isinstance(texts, str):
        texts = [texts] # Ensure it's a list

    if not texts:
        raise ValueError("Input list for embedding cannot be empty.")

    logger.info(f"Starting embedding generation for {len(texts)} text(s) using model '{request.model}'...")

    # Tokenize (padding and truncation are important for batching)
    inputs = tokenizer(
        texts,
        padding=True,
        truncation=True,
        return_tensors="pt",
        max_length=tokenizer.model_max_length # Use model's max length for truncation
    ).to(device)

    # Calculate prompt tokens (sum tokens for all inputs)
    prompt_tokens = sum(count_tokens(tokenizer, text) for text in texts)

    with torch.no_grad():
        outputs = model(**inputs)
        # Use mean pooling - often better for sentence embeddings than CLS
        embeddings = mean_pooling(outputs, inputs['attention_mask'])

    # Normalize embeddings (L2 norm)
    embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)

    embeddings_list = embeddings.cpu().tolist()
    end_time = time.time()

    logger.info(f"Embedding generation completed in {end_time - start_time:.2f}s. Vectors: {len(embeddings_list)}")

    # NOTE: OpenAI Embedding API typically doesn't report completion_tokens
    total_tokens = prompt_tokens

    return {
        "embeddings": embeddings_list,
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": 0, # Usually 0 for embeddings
            "total_tokens": total_tokens,
        }
    }
EOF
echo "  - Created app/inference/embed.py"

# app/inference/utils.py
cat << EOF > app/inference/utils.py
# app/inference/utils.py
import logging
from typing import List, Dict, Union
from transformers import PreTrainedTokenizerBase

logger = logging.getLogger(__name__)

# Removed format_chat_prompt - now handled directly in generate.py using tokenizer.apply_chat_template

def count_tokens(tokenizer: PreTrainedTokenizerBase, text: Union[str, List[Dict[str, str]]]) -> int:
    """
    Counts the number of tokens in a given text or list of chat messages
    using the provided tokenizer.
    """
    if not text:
        return 0
    try:
        if isinstance(text, str):
            # Simple case: count tokens in a string
             encoded = tokenizer.encode(text)
             return len(encoded)
        elif isinstance(text, list):
             # Handle list of chat messages - apply template first if possible
             # Note: This might double-encode, but apply_chat_template is preferred
             # for accuracy if the model uses special tokens.
             try:
                 # Attempt to build the prompt string representation
                 prompt_string = tokenizer.apply_chat_template(text, tokenize=False, add_generation_prompt=True)
                 encoded = tokenizer.encode(prompt_string)
                 return len(encoded)
             except Exception:
                 # Fallback: sum tokens of content fields (less accurate)
                 logger.warning("Could not apply chat template for token counting, using fallback method.")
                 count = 0
                 for msg in text:
                     if isinstance(msg, dict) and "content" in msg and isinstance(msg['content'], str):
                         count += len(tokenizer.encode(msg["content"]))
                 return count
        else:
             logger.warning(f"Unsupported type for token counting: {type(text)}")
             return 0
    except Exception as e:
        logger.error(f"Error during token counting: {e}", exc_info=True)
        return 0 # Return 0 on error

# Removed truncate_text - truncation should be handled by tokenizer parameters
EOF
echo "  - Created app/inference/utils.py"

# app/api/schemas/openai.py
cat << EOF > app/api/schemas/openai.py
# app/api/schemas/openai.py
from typing import List, Optional, Literal, Union, Dict, Any
from pydantic import BaseModel, Field
from datetime import datetime
import uuid

# Utility function for generating default IDs
def generate_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:12]}"

# Utility function for current timestamp
def current_timestamp() -> int:
    return int(datetime.now().timestamp())

# ===== Common Usage Stats =====
class CompletionUsage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: Optional[int] = 0 # Optional for embeddings where it's typically 0
    total_tokens: int = 0

# ===== Chat Completion =====
class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

class ChatCompletionRequest(BaseModel):
    model: str
    messages: List[ChatMessage]
    max_tokens: Optional[int] = 1024 # Increased default
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 1.0 # Default 1.0 in OpenAI API
    stream: Optional[bool] = False
    stop: Optional[Union[str, List[str]]] = None
    # Add other potential OpenAI params like presence_penalty, frequency_penalty, logit_bias etc. if needed
    presence_penalty: Optional[float] = 0.0
    frequency_penalty: Optional[float] = 0.0

class ChatCompletionChoice(BaseModel):
    index: int
    message: ChatMessage
    finish_reason: Optional[Literal["stop", "length", "function_call", "content_filter", "error", "tool_calls"]] = "stop"

class ChatCompletionResponse(BaseModel):
    id: str = Field(default_factory=lambda: generate_id("chatcmpl"))
    object: Literal["chat.completion"] = "chat.completion"
    created: int = Field(default_factory=current_timestamp)
    model: str
    choices: List[ChatCompletionChoice]
    usage: Optional[CompletionUsage] = None # Usage can be None in errors

# ===== Chat Completion Streaming Chunks =====
class ChatCompletionChunkDelta(BaseModel):
    content: Optional[str] = None # Content is optional, might be empty delta
    role: Optional[Literal["assistant"]] = None # Role might appear in first chunk

class ChatCompletionChunkChoice(BaseModel):
    index: int
    delta: ChatCompletionChunkDelta
    finish_reason: Optional[Literal["stop", "length", "function_call", "content_filter", "error", "tool_calls"]] = None # Appears in last chunk

class ChatCompletionChunk(BaseModel):
    id: str = Field(default_factory=lambda: generate_id("chatcmpl"))
    object: Literal["chat.completion.chunk"] = "chat.completion.chunk"
    created: int = Field(default_factory=current_timestamp)
    model: str
    choices: List[ChatCompletionChunkChoice]
    usage: Optional[CompletionUsage] = None # Included in the final [DONE] message data in some implementations

# ===== Embedding =====
class EmbeddingRequest(BaseModel):
    model: str
    input: Union[str, List[str]]
    encoding_format: Optional[Literal["float", "base64"]] = "float" # Add if supporting base64

class EmbeddingData(BaseModel):
    index: int
    embedding: List[float] # Or str if encoding_format="base64"
    object: Literal["embedding"] = "embedding"

class EmbeddingResponse(BaseModel):
    object: Literal["list"] = "list"
    data: List[EmbeddingData]
    model: str
    usage: CompletionUsage # Usage is required in embedding responses

# ===== Models List =====
class ModelPermission(BaseModel):
    # Placeholder structure if needed, OpenAI's API has this
    id: str = Field(default_factory=lambda: f"modelperm-{uuid.uuid4().hex[:12]}")
    object: str = "model_permission"
    created: int = Field(default_factory=current_timestamp)
    allow_create_engine: bool = False
    allow_sampling: bool = True
    allow_logprobs: bool = True
    allow_search_indices: bool = False
    allow_view: bool = True
    allow_fine_tuning: bool = False
    organization: str = "*"
    group: Optional[str] = None
    is_blocking: bool = False

class ModelCard(BaseModel):
    id: str # The model_id used in requests
    object: Literal["model"] = "model"
    created: int = Field(default_factory=current_timestamp)
    owned_by: str = "your-organization" # Customize as needed
    root: Optional[str] = None # Typically same as id
    parent: Optional[str] = None
    permission: List[ModelPermission] = Field(default_factory=lambda: [ModelPermission()])

class ModelList(BaseModel):
    object: Literal["list"] = "list"
    data: List[ModelCard]
EOF
echo "  - Created app/api/schemas/openai.py"

# app/api/routers/chat.py
cat << EOF > app/api/routers/chat.py
# app/api/routers/chat.py
import logging
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from sse_starlette.sse import EventSourceResponse # Use sse-starlette for SSE

from app.api.schemas.openai import ChatCompletionRequest, ChatCompletionResponse, ChatCompletionChunk
from app.inference.engine import run_inference
from app.compat.openai_adapter import build_chat_response, build_chat_chunk

logger = logging.getLogger(__name__)
router = APIRouter()

@router.post(
    "/chat/completions",
    response_model=None, # Response model handled manually for streaming/non-streaming
    summary="OpenAI-Compatible Chat Completions",
    description="Creates a model response for the given chat conversation. Supports streaming.",
)
async def chat_completions(request: ChatCompletionRequest):
    """
    Handles OpenAI-compatible chat completion requests.
    Delegates to the inference engine and formats the response according
    to whether streaming is requested.
    """
    try:
        logger.info(f"Received chat completion request for model: {request.model}, Stream: {request.stream}")
        inference_result_or_generator = await run_inference(request)

        if request.stream:
            logger.debug("Starting SSE stream response.")
            async def event_generator():
                try:
                    stream_id = None # Will be set by the first chunk
                    async for chunk_data in inference_result_or_generator:
                         chunk, stream_id = build_chat_chunk(chunk_data, request.model, stream_id)
                         if chunk: # Don't send empty chunks if adapter filters them
                             yield chunk.json() # Yield JSON string for SSE
                    logger.debug(f"SSE stream finished for ID: {stream_id}")
                except Exception as e:
                     logger.error(f"Error during SSE streaming: {e}", exc_info=True)
                     # Yield an error message or handle differently?
                     # For now, just log and potentially terminate stream.
                     # Consider yielding a final error chunk.
                     yield build_chat_chunk({"delta": None, "finish_reason": "error"}, request.model, stream_id, is_error=True)[0].json()

            return EventSourceResponse(event_generator())
        else:
            # Non-streaming case
            logger.debug("Building non-stream response.")
            response_data = build_chat_response(inference_result_or_generator, request.model)
            return JSONResponse(content=response_data.dict())

    except ValueError as e:
        logger.warning(f"Value error during chat completion: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Internal server error during chat completion: {e}", exc_info=True)
        # Return a generic OpenAI-like error structure
        error_content = {
            "error": {
                "message": f"An internal server error occurred: {str(e)}",
                "type": "internal_server_error",
                "param": None,
                "code": None
            }
        }
        return JSONResponse(status_code=500, content=error_content)
EOF
echo "  - Created app/api/routers/chat.py"

# app/api/routers/embeddings.py
cat << EOF > app/api/routers/embeddings.py
# app/api/routers/embeddings.py
import logging
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse

from app.api.schemas.openai import EmbeddingRequest, EmbeddingResponse, EmbeddingData, CompletionUsage
from app.inference.engine import run_inference

logger = logging.getLogger(__name__)
router = APIRouter()

@router.post(
    "/embeddings",
    response_model=EmbeddingResponse,
    summary="OpenAI-Compatible Embeddings",
    description="Creates embedding vectors representing the input text.",
)
async def create_embedding(request: EmbeddingRequest):
    """
    Handles OpenAI-compatible embedding requests.
    """
    try:
        logger.info(f"Received embedding request for model: {request.model}")
        result = await run_inference(request) # run_inference handles task routing

        embeddings_list = result.get("embeddings")
        usage_data = result.get("usage")

        if embeddings_list is None or usage_data is None:
             raise ValueError("Inference engine did not return expected embeddings or usage data.")

        # Format the response according to OpenAI schema
        data = [
            EmbeddingData(index=i, embedding=vec)
            for i, vec in enumerate(embeddings_list)
        ]

        usage = CompletionUsage(**usage_data)

        response = EmbeddingResponse(
            object="list",
            data=data,
            model=request.model,
            usage=usage
        )
        logger.info(f"Successfully generated {len(data)} embeddings for model '{request.model}'.")
        return response

    except ValueError as e:
        logger.warning(f"Value error during embedding generation: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Internal server error during embedding generation: {e}", exc_info=True)
        error_content = {
            "error": {
                "message": f"An internal server error occurred: {str(e)}",
                "type": "internal_server_error",
                "param": None,
                "code": None
            }
        }
        return JSONResponse(status_code=500, content=error_content)
EOF
echo "  - Created app/api/routers/embeddings.py"

# app/api/routers/models.py
cat << EOF > app/api/routers/models.py
# app/api/routers/models.py
import logging
from fastapi import APIRouter, HTTPException
from app.api.schemas.openai import ModelList, ModelCard
from app.models.manager import ModelManager

logger = logging.getLogger(__name__)
router = APIRouter()

@router.get(
    "/models",
    response_model=ModelList,
    summary="List Available Models",
    description="Retrieves a list of models available through the API.",
)
async def list_models():
    """
    Lists all currently loaded and available models, mimicking OpenAI's /v1/models endpoint.
    """
    try:
        logger.info("Received request to list models.")
        model_entries = ModelManager.list_models() # Gets {id: {"task": task, "device": device}}

        if not model_entries:
            logger.info("No models are currently loaded.")
            return ModelList(data=[])

        model_cards = []
        for model_id, details in model_entries.items():
             # Create a ModelCard for each entry
             card = ModelCard(
                 id=model_id,
                 root=model_id, # Often root is the same as id
                 # owned_by can be customized via config if needed
             )
             model_cards.append(card)

        logger.info(f"Returning list of {len(model_cards)} model(s).")
        return ModelList(data=model_cards)
    except Exception as e:
        logger.error(f"Error retrieving model list: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error retrieving model list")
EOF
echo "  - Created app/api/routers/models.py"

# app/api/routers/health.py
cat << EOF > app/api/routers/health.py
# app/api/routers/health.py
import logging
from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
import torch
from app.core.config import settings
from app.models.manager import ModelManager

logger = logging.getLogger(__name__)
router = APIRouter()

@router.get(
    "/health",
    summary="Health Check",
    description="Performs a basic health check of the API server and backend resources.",
    tags=["Health"] # Use the tag defined in main.py
)
async def health_check():
    """
    Provides health status including CUDA availability and loaded models.
    """
    logger.debug("Received health check request.")
    cuda_available = False
    device_name = "cpu"
    try:
        cuda_available = torch.cuda.is_available()
        if cuda_available and "cuda" in settings.inference_device:
            try:
                 # Attempt to get device name based on configured device index
                 device_index = int(settings.inference_device.split(':')[-1]) if ':' in settings.inference_device else 0
                 if device_index < torch.cuda.device_count():
                     device_name = torch.cuda.get_device_name(device_index)
                 else:
                     device_name = f"Configured CUDA device index {device_index} out of range"
                     logger.warning(device_name)
            except Exception as e:
                 device_name = f"Error getting CUDA device name: {e}"
                 logger.warning(device_name)
        elif "cuda" in settings.inference_device:
             device_name = "CUDA configured but not available/found"
             logger.warning(device_name)

        # Check loaded models status
        loaded_models_status = ModelManager.list_models()
        model_status = {
            "count": len(loaded_models_status),
            "models": list(loaded_models_status.keys()) # List IDs of loaded models
        }

        status = {
            "status": "ok",
            "environment": settings.environment,
            "inference_device_configured": settings.inference_device,
            "cuda_available": cuda_available,
            "active_device": device_name,
            "loaded_models": model_status,
        }
        logger.debug(f"Health check status: {status}")
        return JSONResponse(content=status)

    except Exception as e:
        logger.error(f"Health check failed: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail=f"Health check failed: {str(e)}")
EOF
echo "  - Created app/api/routers/health.py"

# app/compat/openai_adapter.py
cat << EOF > app/compat/openai_adapter.py
# app/compat/openai_adapter.py
import logging
import time
import uuid
from typing import List, Dict, Any, Optional, Tuple

from app.api.schemas.openai import (
    ChatMessage, ChatCompletionChoice, ChatCompletionResponse, CompletionUsage,
    ChatCompletionChunk, ChatCompletionChunkChoice, ChatCompletionChunkDelta
)

logger = logging.getLogger(__name__)

# Removed convert_chat_request_to_prompt - handled in inference/generate.py

def build_chat_response(
    inference_result: Dict[str, Any],
    model_id: str
) -> ChatCompletionResponse:
    """
    Wraps non-streaming generated output into an OpenAI-style ChatCompletionResponse.
    """
    generated_text = inference_result.get("text")
    usage_data = inference_result.get("usage")
    finish_reason = inference_result.get("finish_reason", "stop")

    if generated_text is None or usage_data is None:
        logger.error("Incomplete inference result received for building chat response.")
        # Handle error case - maybe raise or return a specific error response
        # For now, create a response indicating an issue
        return ChatCompletionResponse(
             model=model_id,
             choices=[ChatCompletionChoice(index=0, message=ChatMessage(role="assistant", content="Error: Failed to generate response."), finish_reason="error")],
             usage=None # No valid usage if generation failed
        )

    choice = ChatCompletionChoice(
        index=0,
        message=ChatMessage(role="assistant", content=generated_text),
        finish_reason=finish_reason
    )

    usage = CompletionUsage(**usage_data)

    response = ChatCompletionResponse(
        model=model_id,
        choices=[choice],
        usage=usage
        # ID and created timestamp are handled by Pydantic default factories
    )
    logger.debug(f"Built non-stream response for model '{model_id}'")
    return response

def build_chat_chunk(
    stream_chunk_data: Dict[str, Any],
    model_id: str,
    existing_stream_id: Optional[str] = None,
    is_error: bool = False
) -> Tuple[Optional[ChatCompletionChunk], Optional[str]]:
    """
    Wraps a streaming chunk from the inference engine into an OpenAI-style ChatCompletionChunk.
    Handles the final [DONE] message implicitly when finish_reason is present.
    Returns a tuple: (ChatCompletionChunk or None, stream_id)
    Returns None for the chunk if it's just an empty delta with no finish reason.
    """
    delta_content = stream_chunk_data.get("delta")
    usage_data = stream_chunk_data.get("usage") # Available only in the last chunk
    finish_reason = stream_chunk_data.get("finish_reason")

    # Use existing stream ID or generate a new one for the first chunk
    stream_id = existing_stream_id or f"chatcmpl-{uuid.uuid4().hex[:12]}"

    # Determine if this is the last chunk (has finish_reason)
    is_last_chunk = finish_reason is not None

    # Create the delta object
    if is_error:
        delta = ChatCompletionChunkDelta(content="Error processing request.")
        finish_reason = "error" # Override finish reason
    elif delta_content is not None:
        delta = ChatCompletionChunkDelta(content=delta_content)
    else:
        # If it's the last chunk, delta might be empty {}
        delta = ChatCompletionChunkDelta()

    # Skip empty deltas unless it's the last chunk providing a finish reason
    if delta_content is None and not is_last_chunk and not is_error:
         logger.debug("Skipping empty intermediate chunk.")
         return None, stream_id

    choice = ChatCompletionChunkChoice(
        index=0,
        delta=delta,
        finish_reason=finish_reason if is_last_chunk or is_error else None
    )

    usage_object = CompletionUsage(**usage_data) if usage_data and (is_last_chunk or is_error) else None

    chunk = ChatCompletionChunk(
        id=stream_id, # Use the consistent ID for the whole stream
        model=model_id,
        choices=[choice],
        usage=usage_object
    )

    # logger.debug(f"Built stream chunk: ID={stream_id}, FinishReason={finish_reason}, HasContent={delta_content is not None}")
    return chunk, stream_id
EOF
echo "  - Created app/compat/openai_adapter.py"

# app/compat/stream_utils.py
cat << EOF > app/compat/stream_utils.py
# app/compat/stream_utils.py
import logging
import json
from typing import AsyncGenerator, Dict, Any
from app.compat.openai_adapter import build_chat_chunk # Import the builder

logger = logging.getLogger(__name__)

# This file might become less necessary as the logic is now primarily in
# the router and the openai_adapter. We keep it for potential future expansion
# or if the router logic becomes too complex.
# async def format_sse_stream(
#     stream_result_generator: AsyncGenerator[Dict[str, Any], None],
#     model_id: str
# ) -> AsyncGenerator[str, None]:
#     """
#     (Deprecated/Simplified) Formats the raw stream generator results into SSE events.
#     Now largely handled within the router using build_chat_chunk.
#     """
#     stream_id = None
#     logger.info(f"Starting SSE stream formatting for model '{model_id}'")
#     try:
#         async for chunk_data in stream_result_generator:
#             chunk, stream_id = build_chat_chunk(chunk_data, model_id, stream_id)
#             if chunk: # Only yield if a valid chunk was built
#                 yield f"data: {chunk.json()}\\n\\n" # Escaped newlines

#         # Send the final [DONE] message (OpenAI standard)
#         yield "data: [DONE]\\n\\n" # Escaped newlines
#         logger.info(f"SSE stream finished and [DONE] sent for ID: {stream_id}")

#     except Exception as e:
#         logger.error(f"Error during SSE stream formatting: {e}", exc_info=True)
#         # Optionally yield an error event
#         error_payload = {
#             "error": str(e),
#             "id": stream_id or "unknown",
#             "model": model_id
#         }
#         yield f"event: error\\ndata: {json.dumps(error_payload)}\\n\\n" # Escaped newlines
#         yield "data: [DONE]\\n\\n" # Still send DONE even on error? # Escaped newlines

# Keeping the file but commenting out the primary function as its logic
# is now integrated into the router's event_generator and openai_adapter.
# This simplifies the flow:
# engine -> router -> adapter (build_chat_chunk) -> router (yield json)
EOF
echo "  - Created app/compat/stream_utils.py"
echo "File creation complete."
echo ""

# === PART 2: Setup Environment and Install Dependencies ===

echo "Step 3: Creating Python virtual environment (./venv)..."
python3 -m venv venv
if [ $? -ne 0 ]; then
    echo "Error: Failed to create virtual environment."
    exit 1
fi
echo "Virtual environment created."
echo ""

echo "Step 4: Installing dependencies from requirements.txt..."
# Use pip from the virtual environment directly
./venv/bin/pip install -r requirements.txt
if [ $? -ne 0 ]; then
    echo "Error: Failed to install dependencies. Please check requirements.txt and network connection."
    exit 1
fi
echo "Dependencies installed."
echo ""

# === PART 3: Manual Steps and Running the Server ===

echo "Step 5: MANUAL ACTION REQUIRED!"
echo "  - Please check and edit the '.env' file if necessary (especially INFERENCE_DEVICE)."
echo "  - Please check 'config/models.yaml' to ensure you have access to the specified models."
echo "  - You might need to run 'huggingface-cli login' if models require authentication."
echo ""
echo "Step 6: Run the Server (Manual Command)"
echo "  - Once configuration is checked, run the following command in your terminal:"
echo "    (Ensure your virtual environment is active: 'source venv/bin/activate' or run python from venv path)"
echo ""
echo "    ./venv/bin/python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000"
echo ""
# The command below is commented out - run it manually after checking config.
# echo "Attempting to start the server (This script will hang here)..."
# ./venv/bin/python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

echo "--- Setup Script Finished ---"
