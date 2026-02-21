# DocGemma

> **Source repositories:** [docgemma-connect](https://github.com/galinilin/docgemma-connect) (FastAPI backend) | [docgemma-frontend](https://github.com/galinilin/docgemma-frontend) (Vue 3 UI)
>
> **Competition:** [The MedGemma Impact Challenge](https://www.kaggle.com/competitions/med-gemma-impact-challenge) on Kaggle

Agentic medical AI assistant powered by MedGemma, with autonomous tool calling for clinical decision support. Designed for resource-limited healthcare environments. Compatible with [MedGemma 27B](https://huggingface.co/google/medgemma-27b-it) and [MedGemma 1.5 4B](https://huggingface.co/google/medgemma-1.5-4b-it).

DocGemma combines a Vue 3 web interface with a FastAPI/LangGraph agent backend that can query drug safety databases, search medical literature, manage electronic health records, and analyze medical images — all with human-in-the-loop approval for safety-critical actions.

## Live Demo

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/galinilin/docgemma-app/blob/main/docgemma_colab.ipynb)

Try DocGemma instantly on Google Colab — no local setup required. The notebook provisions an A100 GPU, deploys the full stack (vLLM + backend + frontend), and generates a public URL. Just provide a [HuggingFace token](https://huggingface.co/settings/tokens) with MedGemma access.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2+, or [Podman](https://podman.io/) with `podman compose`

**For local GPU inference (optional):**
- NVIDIA GPU — 48 GB+ VRAM for MedGemma 27B (e.g., A100, A6000) or 8 GB+ for MedGemma 1.5 4B
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- A [HuggingFace](https://huggingface.co) account with access to [MedGemma](https://huggingface.co/google/medgemma-27b-it)

**For remote inference:**
- A running vLLM-compatible endpoint (e.g., [RunPod](https://www.runpod.io/), [Together AI](https://www.together.ai/))

## Quick Start

### Option 1: Native (No Docker)

For GPU cloud instances (RunPod, Vast.ai, Lambda, Paperspace, AWS/GCP/Azure) or bare metal with an NVIDIA GPU. Installs everything directly on the host — no containers needed.

```bash
git clone https://github.com/galinilin/docgemma-app.git
HF_TOKEN=hf_your_token_here bash docgemma-app/run-native.sh
```

The script auto-detects GPU VRAM (falls back to MedGemma 4B if < 40 GB), installs dependencies (Node.js, UV, vLLM), builds the frontend, and starts vLLM + the app on a single port.

| Variable | Default | Description |
|---|---|---|
| `HF_TOKEN` | — | HuggingFace token (required) |
| `DOCGEMMA_MODEL` | `google/medgemma-27b-it` | Auto-selected based on VRAM |
| `APP_PORT` | `8080` | Web UI port |
| `VLLM_PORT` | `8000` | vLLM API port |
| `WORKDIR` | `/workspace/docgemma` | Clone/build directory |

### Option 2: Docker — Remote Endpoint (No GPU Required)

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

### Option 3: Docker — Local GPU with vLLM

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

> **Note:** The first run downloads model weights (~54 GB for MedGemma 27B, ~8 GB for MedGemma 1.5 4B). The vLLM health check allows up to 10 minutes for the model to load.

### Podman

Both profiles work with Podman. For the `remote` profile, use the default compose file:

```bash
podman compose --profile remote up
```

For the `gpu` profile, use the Podman-specific compose file (uses CDI instead of Docker's `deploy.resources` for GPU passthrough):

```bash
podman compose -f docker-compose.podman.yml --profile gpu up
```

> Requires [NVIDIA Container Toolkit with CDI](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html) configured for Podman.

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
- **Model:** MedGemma 27B or 1.5 4B via vLLM (OpenAI-compatible API)

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `DOCGEMMA_ENDPOINT` | remote profile | — | vLLM endpoint URL |
| `DOCGEMMA_API_KEY` | remote profile | — | API key for the endpoint |
| `HF_TOKEN` | gpu profile | — | HuggingFace token (with MedGemma access) |
| `DOCGEMMA_MODEL` | no | `google/medgemma-27b-it` | Model ID — also supports `google/medgemma-1.5-4b-it` |
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
First run downloads model weights (~54 GB for MedGemma 27B, ~8 GB for MedGemma 1.5 4B). Subsequent runs use the cached weights in the `vllm-cache` Docker volume.

**GPU out of memory**
Reduce `VLLM_GPU_UTIL` (e.g., `0.80`) or `VLLM_MAX_MODEL_LEN` (e.g., `4096`) in your `.env`.

**Connection refused on remote profile**
Verify `DOCGEMMA_ENDPOINT` is reachable and includes the correct port (e.g., `https://host:8000`).

**Rebuilding after source updates**
Force a fresh build to pull latest source code:

```bash
docker compose build --no-cache
```

## Related Repositories

| Repository | Description |
|---|---|
| [docgemma-connect](https://github.com/galinilin/docgemma-connect) | FastAPI backend with LangGraph agent, FHIR R4 EHR, and medical tool integrations |
| [docgemma-frontend](https://github.com/galinilin/docgemma-frontend) | Vue 3 web interface with real-time chat, EHR management, and tool approval UI |

## Disclaimer

DocGemma is a research and educational tool. It is **not** certified for clinical use. Do not use for real patient care decisions.
