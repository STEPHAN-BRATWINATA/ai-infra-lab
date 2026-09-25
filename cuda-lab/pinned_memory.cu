// pinned_memory.cu — Otimizacao classica: memoria PAGEABLE vs PINNED
// Mede a banda de transferencia Host<->Device nos dois modos e compara.
// Compilar/rodar:  build.bat pinned_memory.cu
//
// Conceito:
//  - PAGEABLE (malloc): a RAM pode ser paginada pelo SO. A GPU precisa de
//    uma copia intermediaria -> transferencia mais lenta.
//  - PINNED (cudaHostAlloc): RAM "travada", a GPU acessa direto via DMA
//    -> transferencia bem mais rapida. Liberada com cudaFreeHost ao final.

#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

// Mede banda (GB/s) de H2D e D2H para um buffer de host ja alocado
static void mede(const char *nome, char *host, char *dev, size_t bytes) {
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    float msH2D = 0, msD2H = 0;

    // Host -> Device
    cudaEventRecord(a);
    cudaMemcpy(dev, host, bytes, cudaMemcpyHostToDevice);
    cudaEventRecord(b); cudaEventSynchronize(b);
    cudaEventElapsedTime(&msH2D, a, b);

    // Device -> Host
    cudaEventRecord(a);
    cudaMemcpy(host, dev, bytes, cudaMemcpyDeviceToHost);
    cudaEventRecord(b); cudaEventSynchronize(b);
    cudaEventElapsedTime(&msD2H, a, b);

    double gb = bytes / 1.0e9;
    printf("  %-9s | H2D: %5.1f GB/s | D2H: %5.1f GB/s\n",
           nome, gb / (msH2D / 1000.0), gb / (msD2H / 1000.0));

    cudaEventDestroy(a); cudaEventDestroy(b);
}

int main() {
    const size_t bytes = 256 * 1024 * 1024; // 256 MB
    printf("Teste de banda Host<->Device com %zu MB\n\n", bytes / (1024 * 1024));

    char *dev = nullptr;
    cudaMalloc(&dev, bytes);

    // --- PAGEABLE: malloc comum ---
    char *pageable = (char *)malloc(bytes);
    for (size_t i = 0; i < bytes; i += 4096) pageable[i] = 1; // "toca" as paginas

    // --- PINNED: cudaHostAlloc (RAM travada) ---
    char *pinned = nullptr;
    cudaError_t err = cudaHostAlloc((void **)&pinned, bytes, cudaHostAllocDefault);
    if (err != cudaSuccess) { printf("cudaHostAlloc falhou: %s\n", cudaGetErrorString(err)); return 1; }

    printf("  Modo      | Host->Device      | Device->Host\n");
    printf("  ----------+-------------------+------------------\n");
    mede("PAGEABLE", pageable, dev, bytes);
    mede("PINNED",   pinned,   dev, bytes);

    // Comparacao rapida (roda H2D de novo so pra calcular o fator)
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);
    float mp = 0, mq = 0;
    cudaEventRecord(a); cudaMemcpy(dev, pageable, bytes, cudaMemcpyHostToDevice);
    cudaEventRecord(b); cudaEventSynchronize(b); cudaEventElapsedTime(&mp, a, b);
    cudaEventRecord(a); cudaMemcpy(dev, pinned, bytes, cudaMemcpyHostToDevice);
    cudaEventRecord(b); cudaEventSynchronize(b); cudaEventElapsedTime(&mq, a, b);
    printf("\n==> Pinned foi %.1fx mais rapida que pageable no Host->Device\n", mp / mq);

    // Libera tudo (pinned tem funcao propria!)
    cudaEventDestroy(a); cudaEventDestroy(b);
    free(pageable);
    cudaFreeHost(pinned);   // <- devolve a RAM travada
    cudaFree(dev);
    printf("\n[OK] Memoria liberada. RAM travada devolvida ao sistema.\n");
    return 0;
}
