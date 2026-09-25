// device_query.cu — Validacao da pilha CUDA + specs da GPU + teste de banda
// Equivale aos exemplos classicos deviceQuery + bandwidthTest da NVIDIA.
// Compilar/rodar:  build.bat device_query.cu

#include <cstdio>
#include <cuda_runtime.h>

// Mapeia (major,minor) -> nucleos CUDA por SM (Streaming Multiprocessor)
static int coresPerSM(int major, int minor) {
    typedef struct { int sm; int cores; } SMtoCores;
    SMtoCores table[] = {
        {0x30, 192}, {0x32, 192}, {0x35, 192}, {0x37, 192},
        {0x50, 128}, {0x52, 128}, {0x53, 128},
        {0x60,  64}, {0x61, 128}, {0x62, 128},
        {0x70,  64}, {0x72,  64}, {0x75,  64},
        {0x80,  64}, {0x86, 128}, {0x87, 128}, {0x89, 128},
        {0x90, 128}, {-1, -1}
    };
    int key = (major << 4) + minor;
    for (int i = 0; table[i].sm != -1; i++)
        if (table[i].sm == key) return table[i].cores;
    return 128; // fallback
}

int main() {
    int n = 0;
    cudaError_t e = cudaGetDeviceCount(&n);
    if (e != cudaSuccess) {
        printf("[FALHA] cudaGetDeviceCount -> %s\n", cudaGetErrorString(e));
        return 1;
    }
    printf("===== VALIDACAO DA PILHA CUDA =====\n");
    printf("GPUs CUDA detectadas: %d\n\n", n);

    int rt = 0, drv = 0;
    cudaRuntimeGetVersion(&rt);
    cudaDriverGetVersion(&drv);
    printf("Runtime CUDA : %d.%d\n", rt / 1000, (rt % 100) / 10);
    printf("Driver CUDA  : %d.%d\n\n", drv / 1000, (drv % 100) / 10);

    for (int d = 0; d < n; d++) {
        cudaDeviceProp p;
        cudaGetDeviceProperties(&p, d);
        int cores = coresPerSM(p.major, p.minor) * p.multiProcessorCount;

        // CUDA 13 removeu clockRate/memoryClockRate da struct -> usar atributos
        int clkKHz = 0, memClkKHz = 0;
        cudaDeviceGetAttribute(&clkKHz, cudaDevAttrClockRate, d);
        cudaDeviceGetAttribute(&memClkKHz, cudaDevAttrMemoryClockRate, d);
        double memBW = 2.0 * memClkKHz * (p.memoryBusWidth / 8) / 1.0e6; // GB/s

        printf("----- GPU %d: %s -----\n", d, p.name);
        printf("  Compute capability : %d.%d\n", p.major, p.minor);
        printf("  SMs                : %d\n", p.multiProcessorCount);
        printf("  Nucleos CUDA       : %d\n", cores);
        printf("  Memoria global     : %.0f MB\n", p.totalGlobalMem / 1048576.0);
        printf("  Clock GPU          : %.0f MHz\n", clkKHz / 1000.0);
        printf("  Clock memoria      : %.0f MHz\n", memClkKHz / 1000.0);
        printf("  Largura barramento : %d bits\n", p.memoryBusWidth);
        printf("  Banda teorica      : %.1f GB/s\n", memBW);
        printf("  Threads/bloco max  : %d\n", p.maxThreadsPerBlock);
        printf("  Warp size          : %d\n\n", p.warpSize);
    }

    // ---- Teste de banda real Host<->Device (256 MB) ----
    const size_t bytes = 256 * 1024 * 1024;
    char *h = (char *)malloc(bytes);
    char *dptr = nullptr;
    if (cudaMalloc(&dptr, bytes) != cudaSuccess) {
        printf("[AVISO] cudaMalloc falhou no teste de banda.\n");
        free(h); return 0;
    }
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    float msH2D = 0, msD2H = 0;

    cudaEventRecord(a);
    cudaMemcpy(dptr, h, bytes, cudaMemcpyHostToDevice);
    cudaEventRecord(b); cudaEventSynchronize(b);
    cudaEventElapsedTime(&msH2D, a, b);

    cudaEventRecord(a);
    cudaMemcpy(h, dptr, bytes, cudaMemcpyDeviceToHost);
    cudaEventRecord(b); cudaEventSynchronize(b);
    cudaEventElapsedTime(&msD2H, a, b);

    double gb = bytes / 1.0e9;
    printf("===== TESTE DE BANDA (256 MB) =====\n");
    printf("  Host -> Device : %.1f GB/s\n", gb / (msH2D / 1000.0));
    printf("  Device -> Host : %.1f GB/s\n", gb / (msD2H / 1000.0));

    cudaEventDestroy(a); cudaEventDestroy(b);
    cudaFree(dptr); free(h);
    printf("\n[OK] Pilha CUDA validada com sucesso.\n");
    return 0;
}
