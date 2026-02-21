# DocGemma

Agentic medical AI assistant powered by [MedGemma](https://huggingface.co/google/medgemma-27b-it), with autonomous tool calling for clinical decision support. Designed for resource-limited healthcare environments.

DocGemma combines a Vue 3 web interface with a FastAPI/LangGraph agent backend that can query drug safety databases, search medical literature, manage electronic health records, and analyze medical images — all with human-in-the-loop approval for safety-critical actions.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2+

**For local GPU inference (optional):**
- NVIDIA GPU with 48 GB+ VRAM (e.g., A100, A6000)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- A [HuggingFace](https://huggingface.co) account with access to [MedGemma](https://huggingface.co/google/medgemma-27b-it)

**For remote inference:**
- A running vLLM-compatible endpoint (e.g., [RunPod](https://www.runpod.io/), [Together AI](https://www.together.ai/))

## Quick Start

### Option 1: Remote Endpoint (No GPU Required)

```bash
git clone https://github.com/galinilin/docgemma-app.git
cd docgemma-app
cp .env.example .env
```

Edit `.env` and set your endpoint credentials:

```ini
DOCGEMMA_ENDPOINT=https://your-vllm-endpoint.example.com
DOCGEMMA_API_KEY=your-api-key-here
```

```bash
docker compose --profile remote up
```

### Option 2: Local GPU with vLLM

```bash
git clone https://github.com/galinilin/docgemma-app.git
cd docgemma-app
cp .env.example .env
```

Edit `.env` and set your HuggingFace token:

```ini
HF_TOKEN=hf_your_token_here
```

```bash
docker compose --profile gpu up
```

> **Note:** The first run downloads ~54 GB of model weights. The vLLM health check allows up to 10 minutes for the model to load.

---

Open **http://localhost:8080** in your browser.

## Architecture

```
Browser ──→ Vue 3 SPA ──→ FastAPI + LangGraph Agent ──→ vLLM / MedGemma
                │                    │
                │                    ├── Drug safety (OpenFDA)
                │                    ├── Drug interactions (RxNav)
                │                    ├── Medical literature (PubMed)
                │                    ├── Clinical trials (ClinicalTrials.gov)
                │                    ├── FHIR R4 EHR (local store)
                │                    └── Medical image analysis (vision API)
                │
                └── Patient management, imaging upload, clinical notes
```

The Docker image bundles everything into a single container:

- **Frontend:** Vue 3 + TypeScript + Tailwind CSS, built and served as static files
- **Backend:** Python/FastAPI with a 7-node LangGraph agent workflow
- **Model:** MedGemma 27B via vLLM (OpenAI-compatible API)

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `DOCGEMMA_ENDPOINT` | remote profile | — | vLLM endpoint URL |
| `DOCGEMMA_API_KEY` | remote profile | — | API key for the endpoint |
| `HF_TOKEN` | gpu profile | — | HuggingFace token (with MedGemma access) |
| `DOCGEMMA_MODEL` | no | `google/medgemma-27b-it` | Model ID (HuggingFace format) |
| `DOCGEMMA_PORT` | no | `8080` | Host port for the web UI |
| `VLLM_MAX_MODEL_LEN` | no | `8192` | Maximum context length |
| `VLLM_GPU_UTIL` | no | `0.90` | GPU memory utilization (0.0–1.0) |

## Data Persistence

Patient records (FHIR R4) and chat session history are stored in a Docker volume (`docgemma-data`). On first run, sample patient records are seeded automatically.

To reset all data to defaults:

```bash
docker compose down -v
```

## Building with Specific Versions

Pin the backend and frontend to specific branches or tags:

```bash
docker compose build \
  --build-arg BACKEND_REF=v1.0.0 \
  --build-arg FRONTEND_REF=v1.0.0
```

Available build args:

| Arg | Default | Description |
|---|---|---|
| `BACKEND_REPO` | `https://github.com/galinilin/docgemma-connect.git` | Backend repo URL |
| `BACKEND_REF` | `main` | Branch, tag, or commit |
| `FRONTEND_REPO` | `https://github.com/galinilin/docgemma-frontend.git` | Frontend repo URL |
| `FRONTEND_REF` | `main` | Branch, tag, or commit |

## Development

For development, clone the source repositories directly:

- **Backend:** [galinilin/docgemma-connect](https://github.com/galinilin/docgemma-connect)
- **Frontend:** [galinilin/docgemma-frontend](https://github.com/galinilin/docgemma-frontend)

## Troubleshooting

**vLLM takes a long time to start**
First run downloads ~54 GB of model weights. Subsequent runs use the cached weights in the `vllm-cache` Docker volume.

**GPU out of memory**
Reduce `VLLM_GPU_UTIL` (e.g., `0.80`) or `VLLM_MAX_MODEL_LEN` (e.g., `4096`) in your `.env`.

**Connection refused on remote profile**
Verify `DOCGEMMA_ENDPOINT` is reachable and includes the correct port (e.g., `https://host:8000`).

**Rebuilding after source updates**
Force a fresh build to pull latest source code:

```bash
docker compose build --no-cache
```

## Disclaimer

DocGemma is a research and educational tool. It is **not** certified for clinical use. Do not use for real patient care decisions.
