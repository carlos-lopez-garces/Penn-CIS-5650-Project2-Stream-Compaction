#pragma once

#include "common.h"

namespace StreamCompaction {
    namespace Efficient {
        StreamCompaction::Common::PerformanceTimer& timer();

        void reduce(int n, int *odata, const int *idata);

        void scan(int n, int *odata, const int *idata);

        void scanNoTimer(int n, int *odata, const int *idata);

        int compact(int n, int *odata, const int *idata);
    }
}
