#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "faust/dsp/dsp.h"
#include "faust/gui/meta.h"
#include "faust/gui/MapUI.h"
#include "silakka54-dsp.cpp"

namespace {
constexpr int kBlock = 128;

FAUSTFLOAT* zone(MapUI& map, const char* name) {
    auto* result = map.getParamZone(name);
    if (!result) {
        std::fprintf(stderr, "missing DSP control: %s\n", name);
        std::exit(1);
    }
    return result;
}

double render(Silakka54DSP& dsp, int blocks) {
    std::vector<FAUSTFLOAT> left(kBlock), right(kBlock);
    FAUSTFLOAT* outputs[] = {left.data(), right.data()};
    double peak = 0;
    for (int block = 0; block < blocks; ++block) {
        dsp.compute(kBlock, nullptr, outputs);
        for (int i = 0; i < kBlock; ++i) {
            peak = std::max(peak, static_cast<double>(std::abs(left[i])));
            peak = std::max(peak, static_cast<double>(std::abs(right[i])));
        }
    }
    return peak;
}

void expect(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "silakka54-sound self-test failed: %s\n", message);
        std::exit(1);
    }
}
}

int main() {
    Silakka54DSP dsp;
    dsp.init(48000);
    MapUI map;
    dsp.buildUserInterface(&map);

    expect(render(dsp, 4) < 1e-6, "idle output is not silent");

    *zone(map, "candidate_l_ctrl") = 1;
    expect(render(dsp, 24) > 0.01, "candidate cue did not sound");
    *zone(map, "candidate_l_ctrl") = 0;
    render(dsp, 32);

    *zone(map, "ctrl") = 1;
    expect(render(dsp, 48) > 0.01, "confirmed modifier attack did not sound");
    expect(render(dsp, 128) > 0.001, "confirmed modifier held tail disappeared");
    *zone(map, "ctrl") = 0;
    render(dsp, 256);
    expect(render(dsp, 16) < 0.001, "confirmed modifier release did not settle");

    *zone(map, "shift") = 1;
    expect(render(dsp, 64) > 0.001, "Shift halo did not sound alone");
    *zone(map, "shift") = 0;
    render(dsp, 256);

    *zone(map, "layer") = 1;
    expect(render(dsp, 64) > 0.01, "layer entry tone did not sound");
    render(dsp, 256);
    *zone(map, "layer") = 1;
    expect(render(dsp, 16) < 0.001, "identical layer snapshot retriggered the tone");
    *zone(map, "layer") = 0;
    expect(render(dsp, 64) > 0.01, "return-to-Base tone did not sound");
    return 0;
}
