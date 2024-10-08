#include <cuda.h>
#include <cuda_runtime.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/scan.h>
#include "common.h"
#include "thrust.h"

namespace StreamCompaction {
    namespace Thrust {
        using StreamCompaction::Common::PerformanceTimer;
        PerformanceTimer& timer()
        {
            static PerformanceTimer timer;
            return timer;
        }
        /**
         * Performs prefix-sum (aka scan) on idata, storing the result into odata.
         */
        void scan(int n, int *odata, const int *idata) {
            timer().startGpuTimer();

            thrust::device_vector<int> idataDevice(idata, idata + n);
            thrust::device_vector<int> odataDevice(n);
            thrust::exclusive_scan(idataDevice.begin(), idataDevice.end(), odataDevice.begin());
            thrust::copy(odataDevice.begin(), odataDevice.end(), odata);

            timer().endGpuTimer();
        }
    }
}
