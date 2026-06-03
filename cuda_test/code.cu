#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <ctime>
#include <cuda_runtime.h>

#define CUDA_CHECK(call)                                                       \
    do {                                                                       \
        cudaError_t _e = (call);                                               \
        if (_e != cudaSuccess) {                                               \
            fprintf(stderr, "CUDA error %s:%d: %s\n", __FILE__, __LINE__,      \
                    cudaGetErrorString(_e));                                   \
            exit(EXIT_FAILURE);                                                \
        }                                                                      \
    } while (0)

#define ITERS 100000u

__global__ void stress_kernel(uint32_t *sink, uint32_t seed) {
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;

    uint32_t a = seed ^ (idx * 2654435761u);  
    uint32_t b = idx + 0x9E3779B9u;    
    uint32_t c = ~idx;

    #pragma unroll 8
    for (uint32_t i = 0; i < ITERS; ++i) {
        a = a * 1664525u + 1013904223u;   
        b ^= (a >> 13);                 
        c += (b << 7) | (b >> 25);            
        a -= (c ^ i);      
        b = (b * 0x85EBCA6Bu) ^ (a >> 16);     
    }

    uint32_t mix = a ^ b ^ c;
    if (mix == 0xFFFFFFFFu && idx == 0xFFFFFFFFu) {
        sink[0] = mix;
    }
}

int main(int argc, char **argv) {
    int   seconds   = (argc > 1) ? atoi(argv[1]) : 30;
    int   device_id = (argc > 2) ? atoi(argv[2]) : 0;

    CUDA_CHECK(cudaSetDevice(device_id));

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device_id));

    const int threads = 256;
    const int blocks  = 128 * 32;

    printf("Device %d: %s (%d SMs)\n", device_id, prop.name,
           prop.multiProcessorCount);
    printf("Launch config: %d blocks x %d threads, %u iters/launch\n",
           blocks, threads, ITERS);
    printf("Running INT32 stress for ~%d s. Monitor with:\n", seconds);

    uint32_t *d_sink = nullptr;
    CUDA_CHECK(cudaMalloc(&d_sink, sizeof(uint32_t)));
    CUDA_CHECK(cudaMemset(d_sink, 0, sizeof(uint32_t)));

    time_t start = time(nullptr);
    uint32_t launch = 0;
    while (time(nullptr) - start < seconds) {
        printf("running kernel...\n");
        stress_kernel<<<blocks, threads>>>(d_sink, launch++);
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaDeviceSynchronize());
    }

    uint32_t h_sink = 0;
    CUDA_CHECK(cudaMemcpy(&h_sink, d_sink, sizeof(uint32_t),
                          cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaFree(d_sink));

    printf("Done. %u launches completed. sink=%u (expected 0)\n",
           launch, h_sink);
    return 0;
}
