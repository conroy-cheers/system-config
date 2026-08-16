#include <algorithm>
#include <atomic>
#include <cstdint>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <jack/jack.h>
#include <jack/midiport.h>
#include <unistd.h>

#include "faust/dsp/dsp.h"
#include "faust/gui/meta.h"
#include "faust/gui/MapUI.h"
#include "silakka54-dsp.cpp"

namespace {
constexpr unsigned char kMidiChannel = 15;
std::atomic<bool> running{true};

struct App {
    jack_client_t* client = nullptr;
    jack_port_t* midi = nullptr;
    jack_port_t* left = nullptr;
    jack_port_t* right = nullptr;
    Silakka54DSP dsp;
    MapUI map;
    FAUSTFLOAT* candidates[6]{};
    FAUSTFLOAT* modifiers[4]{};
    FAUSTFLOAT* layer = nullptr;
    bool control_state[10]{};
    unsigned char layer_value = 0;
    jack_nframes_t tail_frames = 0;
    jack_nframes_t sample_rate = 48000;
    std::atomic<unsigned long> xruns{0};
};

FAUSTFLOAT* required_zone(MapUI& map, const char* name) {
    FAUSTFLOAT* zone = map.getParamZone(name);
    if (!zone) {
        std::fprintf(stderr, "silakka54-sound-engine: DSP control '%s' is absent\n", name);
        std::exit(1);
    }
    return zone;
}

int process(jack_nframes_t frames, void* argument) {
    auto& app = *static_cast<App*>(argument);
    void* midi_buffer = jack_port_get_buffer(app.midi, frames);
    const auto count = jack_midi_get_event_count(midi_buffer);
    for (std::uint32_t index = 0; index < count; ++index) {
        jack_midi_event_t event{};
        if (jack_midi_event_get(&event, midi_buffer, index) != 0 || event.size < 2) continue;
        const unsigned char status = event.buffer[0];
        if ((status & 0x0f) != kMidiChannel) continue;
        if ((status & 0xf0) == 0xb0 && event.size >= 3) {
            const unsigned char control = event.buffer[1];
            const FAUSTFLOAT value = event.buffer[2] >= 64 ? 1.0f : 0.0f;
            int state_index = -1;
            FAUSTFLOAT* zone = nullptr;
            if (control >= 20 && control <= 25) {
                state_index = control - 20;
                zone = app.candidates[state_index];
            }
            if (control >= 30 && control <= 33) {
                state_index = 6 + control - 30;
                zone = app.modifiers[control - 30];
            }
            if (zone && app.control_state[state_index] != (value > 0.5f)) {
                app.control_state[state_index] = value > 0.5f;
                *zone = value;
                app.tail_frames = app.sample_rate;
            }
        } else if ((status & 0xf0) == 0xc0) {
            if (event.buffer[1] != app.layer_value) {
                app.layer_value = event.buffer[1];
                *app.layer = static_cast<FAUSTFLOAT>(app.layer_value);
                app.tail_frames = app.sample_rate;
            }
        }
    }

    FAUSTFLOAT* outputs[] = {
        static_cast<FAUSTFLOAT*>(jack_port_get_buffer(app.left, frames)),
        static_cast<FAUSTFLOAT*>(jack_port_get_buffer(app.right, frames)),
    };
    const bool held = std::any_of(
        std::begin(app.control_state), std::end(app.control_state), [](bool value) { return value; }
    );
    if (!held && app.tail_frames == 0) {
        std::memset(outputs[0], 0, sizeof(FAUSTFLOAT) * frames);
        std::memset(outputs[1], 0, sizeof(FAUSTFLOAT) * frames);
    } else {
        app.dsp.compute(static_cast<int>(frames), nullptr, outputs);
        app.tail_frames = app.tail_frames > frames ? app.tail_frames - frames : 0;
    }
    return 0;
}

int xrun(void* argument) {
    static_cast<App*>(argument)->xruns.fetch_add(1, std::memory_order_relaxed);
    return 0;
}

void shutdown(void*) { running.store(false); }
void signal_handler(int) { running.store(false); }
}

int main() {
    App app;
    jack_status_t status{};
    app.client = jack_client_open("silakka54_sound", JackNoStartServer, &status);
    if (!app.client) {
        std::fprintf(stderr, "silakka54-sound-engine: cannot connect to JACK (status 0x%x)\n", status);
        return 1;
    }

    app.sample_rate = jack_get_sample_rate(app.client);
    app.dsp.init(static_cast<int>(app.sample_rate));
    app.dsp.buildUserInterface(&app.map);
    const char* candidate_names[] = {
        "candidate_l_ctrl", "candidate_l_alt", "candidate_l_gui",
        "candidate_r_gui", "candidate_r_alt", "candidate_r_ctrl",
    };
    const char* modifier_names[] = {"ctrl", "alt", "gui", "shift"};
    for (int i = 0; i < 6; ++i) app.candidates[i] = required_zone(app.map, candidate_names[i]);
    for (int i = 0; i < 4; ++i) app.modifiers[i] = required_zone(app.map, modifier_names[i]);
    app.layer = required_zone(app.map, "layer");

    app.midi = jack_port_register(app.client, "midi_in", JACK_DEFAULT_MIDI_TYPE, JackPortIsInput, 0);
    app.left = jack_port_register(app.client, "out_left", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    app.right = jack_port_register(app.client, "out_right", JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    if (!app.midi || !app.left || !app.right) {
        std::fprintf(stderr, "silakka54-sound-engine: cannot register JACK ports\n");
        jack_client_close(app.client);
        return 1;
    }

    jack_set_process_callback(app.client, process, &app);
    jack_set_xrun_callback(app.client, xrun, &app);
    jack_on_shutdown(app.client, shutdown, &app);
    if (jack_activate(app.client) != 0) {
        std::fprintf(stderr, "silakka54-sound-engine: cannot activate JACK client\n");
        jack_client_close(app.client);
        return 1;
    }

    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);
    while (running.load()) pause();
    std::fprintf(stderr, "silakka54-sound-engine: xruns=%lu\n", app.xruns.load());
    jack_deactivate(app.client);
    jack_client_close(app.client);
    return 0;
}
