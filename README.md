CUDA Stream Compaction
======================

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 2**

* CARLOS LOPEZ GARCES
  * [LinkedIn](https://www.linkedin.com/in/clopezgarces/)
  * [Personal website](https://carlos-lopez-garces.github.io/)
* Tested on: Windows 11, 13th Gen Intel(R) Core(TM) i9-13900HX @ 2.20 GHz, RAM 32GB, NVIDIA GeForce RTX 4060, personal laptop.
 
### Description

This project implements several versions of the ***exclusive parallel prefix sum*** algorithm (aka parallel scan):

- `StreamCompaction::Naive::scan`, which first computes a per-block exclusive scan on input data, storing partial results in shared memory, then uses a second kernel to compute the exclusive scan of the block sums. Finally, it adds the block sums to the partial results from the previous step to produce the final scan result across all blocks.

- `StreamCompaction::Efficient::scan`, which performs a prefix sum computation using a balanced binary tree approach. It first runs an up-sweep phase to compute partial sums across the blocks of input data, followed by a down-sweep phase to propagate the exclusive scan results. For larger arrays, it combines the results from multiple blocks, performing a final addition of block-level results to complete the scan.

- `StreamCompaction::Thrust::scan`, which simply calls `thrust::exclusive_scan` on the input.

Using the work-efficient scan version, this project also implements ***stream compaction*** for efficiently removing 0s from an array of integers. Implementation is `StreamCompaction::Efficient::compact`.

To test them for correctness, their outputs have been compared to CPU versions of these algorithms, which are more straighforward and thus more likely to be correct. Implementations are called from  `StreamCompaction::CPU::scan`. If `simulateGPUScan` is true, the algorithm mimics the GPU parallel algorithm of StreamCompaction::Naive::scan to some extent; differences lie around how the GPU version deals with arbitrary length inputs across more than 1 block.

### Extra Credit 2: GPU Scan Using Shared Memory

`Naive::scan` performs the scan at the block level on shared memory (not in global memory). The shared memory chunk is twice the size of the block's size, so that we can alternate reads and writes using double-buffering (the first half of the shared memory chunk is one buffer and the second half is the other). `Efficient::scan` also performs the scan in shared memory (double-buffering is not needed in this case because a thread doesn't overwrite elements that other threads might need concurrently).

I didn't deal with memory bank conflicts.

### Improving the efficient scan

When I originally wrote the efficient scan with 0-padding to deal with non-power-of-two input sizes, I was aware that there would be entire blocks of 0-padding elements. In my original implementation, my algorithm would perform all the steps of the up-sweep and down-sweep for these 0-padding elements; since these elements are all 0s, operating on them as if they were genuine input elements did not influence the result. Still, the blocks of 0-padding elements and threads assigned to them are scheduled and thus take up compute time and resources. In my final version, I deal with these threads more carefully so that they don't perform unnecessary global memory writes. 

To determine the gains in efficiency of the improved version, I ran Nsight Compute for a single call of the original version and a single call of the improved version for a large input size (2^16). In the report, `Duration` reports the `gpu__time_duration_measured_user` metric in microseconds and represents total time spent in this invocation of the kernel across the GPU. The improved version decreased duration signifcantly for the first `exclusiveScanKernel` invocation (although it increased it a little for the `addBlockIncrementsKernel` kernel).

![](img/efficient_improvement.png)

### Determining block size for naive scan

To try to determine the best block size for the naive implementation of the scan, I ran Nsight Compute on a single invocation of the scan, for each block size in {64, 128, 256, 512, 1024} and input size in {128, 256, 500, 512, 1024, 2^16} (I included 500 to see if a non-power-of-two input size made any difference). From the reports, among all of the available metrics, I chose the `Duration` metric for the first invocation of `exclusiveScanKernel` (which is where the bulk of the work takes place; it's also the most complex kernel). `Duration` reports the `gpu__time_duration_measured_user` metric in microseconds and represents total time spent in this invocation of the kernel across the GPU.

This table shows input sizes from left to right and block sizes from top to bottom. In blue is marked the case where the block size equals the input size (so that only one block is used). 

![](img/naive_block_size_choice_table.png)

This chart shows multiple color bars per input size on the horizontal axis; each color represents a different block size. On the vertical axis, kernel duration is represented.

![](img/naive_block_size_choice_chart.png)

There is no clear winner, but we can choose one block size by elimination: a 1024 block size takes a noticeable longer time to process an input of equal size (1024); it is not a good sign when a kernel that can run for the entire input using only one block performs badly; a 512 block size takes significantly longer to process the largest input (2^16) than smaller block sizes; between block sizes 64 and 128, **I choose 128** because it yields slightly shorter duration than 64 across all input sizes (compare blue and red bars across input sizes).

### Determining block size for efficient scan

Following a similar procedure, I arrived at a block size of 256 for the work-efficient implementation.

### Performance analysis for scan

The following charts compare the execution times (in milliseconds) of all the scan implementations across a range of increasing power-of-2 input sizes.

![](img/perf_bars.png)

We observe that the GPU Efficient implementation consistently beats the execution time of the GPU Naive implementation; interestingly enough, though, for input size 1024, GPU Naive shows lower execution time.

The CPU implementation shows shorter execution times for small input sizes but eventually takes off (at about input size 1024) and increases rapidly as input size grows. On the other hand, execution time of GPU implementations fluctuate somewhat, increasing and decreasing as the input size grows. 

One may speculate as to why the CPU version beats the GPU versions for small input size: the overhead of launching the different kernels combined with the many more instructions computed per iteration in the first scan kernel may offset the gains of parallelization.

The same information is shown in the following charts in different format, where the lower one is a close-up of the upper one for small input sizes. In them, we can appreciate how the GPU Efficient implementation beats the GPU Naive one consistently, although the difference between them in execution time appears to remain constant (not growing, as one might hope).

![](img/perf_lines.png)

It's interesting to see how execution time changes when input size delta is small between a non-power-of-2 input and a power-of-2 input. Observe, for example, that there's a 0.2 ms difference between input size 32765 (NPOT) and 32768 (power of 2) for GPU Naive.

![](img/perf_bars_npot.png)

### Performance bottlenecks for scan

Digging a little deeper, the **efficient scan implementation** doesn't seem to be memory bound. As reported by Nsight Compute for an input size of 32768, memory hardware units are not fully utilized by the first `exclusiveScanKernel` invocation, and memory bandwidth is only partially consumed: `Mem Busy` is at 19% and `Max Bandwith` is at 34%. The maximum throughput for memory instructions is at 34% too. This all indicates that this version of the scan is not memory bound.

![](img/efficient_memory.png)

The achieved warp occupancy is at 74%, though, so latency is not being hidden very well in this efficient scan implementation.

![](img/efficient_occupancy.png)

Furthermore, 43% of compute throughput is very poor: compute units could be utilized more to improve performances. Based on warp occupancy and compute throughput, I would say this **efficient scan implementation is compute-bound**.

![](img/efficient_compute_throughput.png)

Analysing the same set of metrics for the **efficient implementation**, Nsight Compute reports that it is less memory-bound than the efficient version: `Mem Busy` is only at 11% and `Max Bandwith` at 18%, which indicates that neither the memory units nor the communication bandwith within them are fully utilized.

![](img/naive_memory.png)

Warp occupancy is at 69%, which is lower than in the efficient implementation case (74%). I speculate that this is so because the `exclusiveScanKernel` in the naive case uses twice the amount of shared memory than in the efficient case (because it does double buffering and the efficient case doesn't). With higher memory requirements, fewer warps can be scheduled, which leads to lower occupancy.

![](img/naive_occuppancy.png)

Due to its low occupancy and apparent memory unit and bandwith subutilization, I would say that the **naive implementation is compute-bound**. Its lower occupancy compared to the efficient implementation might be part of the reason why the efficient implementation has a lower execution time.

### Brief Thrust analysis

The Thrust-based implementation launches 3 different kernels. The second one appears to prepare the data for the third kernel, which appears to the one that actually performs the scan, based on its duration.

![](img/thrust_kernels.png)

This version achieves an occupancy of 81%, suggesting that it carefully balances memory requirements of each block with the number an size of blocks that it divides the launch into.

### Test program output

All original tests pass when GPU scan and compact outputs are compared to reference outputs obtained using the CPU versions of the code.

```
****************
** SCAN TESTS **
****************
    [   6  23  12   1  47   5  17  25  14  22   5  22  12 ...  41   0 ]
==== cpu scan, power-of-two ====
   elapsed time: 0.0021ms    (std::chrono Measured)
    [   0   6  29  41  42  89  94 111 136 150 172 177 199 ... 5758 5799 ]
==== cpu scan, non-power-of-two ====
   elapsed time: 0.0022ms    (std::chrono Measured)
    [   0   6  29  41  42  89  94 111 136 150 172 177 199 ... 5688 5694 ]
    passed
==== naive scan, power-of-two ====
   elapsed time: 1.2056ms    (CUDA Measured)
    passed
==== naive scan, non-power-of-two ====
   elapsed time: 0.431104ms    (CUDA Measured)
    passed
==== work-efficient scan, power-of-two ====
   elapsed time: 0.643136ms    (CUDA Measured)
    passed
==== work-efficient scan, non-power-of-two ====
   elapsed time: 0.389312ms    (CUDA Measured)
    passed
==== thrust scan, power-of-two ====
   elapsed time: 1.09962ms    (CUDA Measured)
    passed
==== thrust scan, non-power-of-two ====
   elapsed time: 0.311904ms    (CUDA Measured)
    passed

*****************************
** STREAM COMPACTION TESTS **
*****************************
    [   2   3   0   1   1   3   1   1   2   0   3   0   2 ...   3   0 ]
==== cpu compact without scan, power-of-two ====
   elapsed time: 0.0007ms    (std::chrono Measured)
    [   2   3   1   1   3   1   1   2   3   2   1   1   2 ...   2   3 ]
    passed
==== cpu compact without scan, non-power-of-two ====
   elapsed time: 0.0007ms    (std::chrono Measured)
    [   2   3   1   1   3   1   1   2   3   2   1   1   2 ...   3   2 ]
    passed
==== cpu compact with scan ====
   elapsed time: 0.0018ms    (std::chrono Measured)
    [   2   3   1   1   3   1   1   2   3   2   1   1   2 ...   2   3 ]
    passed
==== work-efficient compact, power-of-two ====
   elapsed time: 0.714784ms    (CUDA Measured)
    passed
==== work-efficient compact, non-power-of-two ====
   elapsed time: 0.467104ms    (CUDA Measured)
    passed
```

### Extra tests

I modified `main.cpp` to run the original set of tests for a range of input sizes (power of 2 and non-power-of-2): from `MIN_SIZE = 4` (so that NPOT>=1) to `MAX_SIZE = 1 << 16`. 

All tests pass in that range of sizes.

```
for (int SIZE = MIN_SIZE; SIZE <= MAX_SIZE; SIZE <<= 1) { ... scanTests(SIZE, NPOT, a, b, c, d); }

for (int SIZE = MIN_SIZE; SIZE <= MAX_SIZE; SIZE <<= 1) { ... compactionTests(SIZE, NPOT, a, b, c, d); }
```

Unfortunately, for larger sizes, I get errors like `failed to mempcy odataDevice to odata: invalid configuration argument` from the naive implementation. I couldn't determine the cause.