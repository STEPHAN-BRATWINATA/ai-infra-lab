// streams_overlap.cu — Esconder latencia: transferencia + calculo SOBREPOSTOS
// Compara duas formas de processar o mesmo trabalho:
//   (A) SEQUENCIAL : copia tudo -> calcula tudo -> copia tudo de volta
//   (B) OVERLAP    : divide em pedacos e usa varias STREAMS, de modo que
//                    enquanto a GPU calcula um pedaco, o proximo ja esta
//                    sendo transferido. Requer memoria PINNED.
// Compilar/rodar:  build.bat streams_overlap.cu

#include <cstdio>
#include <cuda_runtime.h>

#define N        (1 << 24)   // 16.777.216 floats (~64 MB)
#define NSTREAMS 4
#define ITERS    48          // carga de calculo por elemento (p/ compute ~ transfer)

// Kernel com trabalho suficiente pra que o calculo "pese" parecido com a copia
__global__ void work(float *d, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        float x = d[i];
        for (int k = 0; k < ITERS; k++)
            x = sinf(x) * cosf(x) + 1.0f;
        d[i] = x;
    }
}

int main() {
    const size_t bytes = (size_t)N * sizeof(float);
    const int chunk = N / NSTREAMS;
    const size_t chunkBytes = (size_t)chunk * sizeof(float);

    printf("Trabalho: %d elementos (~%zu MB), %d streams, %d iteracoes/elemento\n\n",
           N, bytes / (1024 * 1024), NSTREAMS, ITERS);

    // Host PINNED (obrigatorio para cudaMemcpyAsync sobrepor de verdade)
    float *h = nullptr;
    cudaHostAlloc((void **)&h, bytes, cudaHostAllocDefault);
    float *d = nullptr;
    cudaMalloc(&d, bytes);
    for (int i = 0; i < N; i++) h[i] = 0.5f;

    int threads = 256;
    cudaEvent_t a, b; cudaEventCreate(&a); cudaEventCreate(&b);

    // ---------- (A) SEQUENCIAL ----------
    cudaEventRecord(a);
    cudaMemcpy(d, h, bytes, cudaMemcpyHostToDevice);          // copia tudo
    work<<<(N + threads - 1) / threads, threads>>>(d, N);      // calcula tudo
    cudaMemcpy(h, d, bytes, cudaMemcpyDeviceToHost);          // copia de volta
    cudaEventRecord(b); cudaEventSynchronize(b);
    float msSeq = 0; cudaEventElapsedTime(&msSeq, a, b);
    printf("(A) SEQUENCIAL : %.1f ms\n", msSeq);

    // ---------- (B) OVERLAP com streams ----------
    cudaStream_t s[NSTREAMS];
    for (int i = 0; i < NSTREAMS; i++) cudaStreamCreate(&s[i]);

    cudaEventRecord(a);
    for (int i = 0; i < NSTREAMS; i++) {
        int off = i * chunk;
        // Cada pedaco: copia -> calcula -> copia de volta, na SUA stream.
        // Com streams diferentes, esses passos se sobrepoem entre os pedacos.
        cudaMemcpyAsync(d + off, h + off, chunkBytes, cudaMemcpyHostToDevice, s[i]);
        work<<<(chunk + threads - 1) / threads, threads, 0, s[i]>>>(d + off, chunk);
        cudaMemcpyAsync(h + off, d + off, chunkBytes, cudaMemcpyDeviceToHost, s[i]);
    }
    cudaDeviceSynchronize();
    cudaEventRecord(b); cudaEventSynchronize(b);
    float msOvl = 0; cudaEventElapsedTime(&msOvl, a, b);
    printf("(B) OVERLAP    : %.1f ms\n", msOvl);

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) { printf("Erro CUDA: %s\n", cudaGetErrorString(err)); return 1; }

    printf("\n==> Overlap foi %.2fx mais rapido (latencia de transferencia escondida)\n",
           msSeq / msOvl);

    for (int i = 0; i < NSTREAMS; i++) cudaStreamDestroy(s[i]);
    cudaEventDestroy(a); cudaEventDestroy(b);
    cudaFreeHost(h); cudaFree(d);
    printf("\n[OK] Recursos liberados.\n");
    return 0;
}
