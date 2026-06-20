# cuda-lab

Fundamentos de CUDA e otimização de GPU numa RTX 3050, com foco em **medir e entender** cada gargalo (não só "fazer funcionar").

## Programas (em ordem de aprendizado)
| Arquivo | Conceito | Destaque |
|---|---|---|
| `vector_add.cu` | Kernel, threads, indexação | primeira execução na GPU |
| `device_query.cu` | Specs + validação da pilha CUDA | 2560 cores, 168 GB/s, teste de banda |
| `matmul.cu` | Paralelismo: CPU vs GPU | **GPU ~675x mais rápida** |
| `pinned_memory.cu` | Pageable vs pinned memory | teto do PCIe |
| `streams_overlap.cu` | Esconder latência (streams/async) | overlap só ajuda se transfer ≈ compute |
| `matmul_tiled.cu` | Shared-memory tiling | naive vs tiled, GFLOP/s |
| `matmul_regblock.cu` | **Register blocking** | 7,9% → 36,9% do pico (4,64x) |
| `cublas_matmul.cu` | Biblioteca otimizada (cuBLAS) | **59,5% do pico**; benchmarking com warmup+média |

## Como compilar (Windows + CUDA Toolkit + MSVC Build Tools)
```bat
build.bat                 :: compila vector_add.cu
build.bat matmul_tiled.cu :: compila o arquivo informado
```
O `build.bat` carrega o ambiente do compilador C++ e compila com `-arch=sm_86` (Ampere, RTX 3050).

## A jornada de otimização do GEMM
naive (8% do pico) → tiling → **register blocking (37%)** → cuBLAS (60%).
O salto do register blocking foi diagnosticado com **Nsight Compute** (gargalo no pipeline MIO,
saturado por loads de shared memory → reuso em registradores resolve). É o ciclo de HPC completo:
**medir → diagnosticar → otimizar → validar.**
