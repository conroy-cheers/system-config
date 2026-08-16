#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <jack/jack.h>
#include <jack/midiport.h>

namespace {
std::atomic<bool> pending{true};
unsigned char message[3]{};
std::size_t message_size = 0;

int process(jack_nframes_t frames, void* port) {
    void* buffer = jack_port_get_buffer(static_cast<jack_port_t*>(port), frames);
    jack_midi_clear_buffer(buffer);
    if (pending.exchange(false)) jack_midi_event_write(buffer, 0, message, message_size);
    return 0;
}

int number(const char* value, int maximum) {
    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (!end || *end != '\0' || parsed < 0 || parsed > maximum) {
        std::fprintf(stderr, "invalid MIDI value: %s\n", value);
        std::exit(2);
    }
    return static_cast<int>(parsed);
}
}

int main(int argc, char** argv) {
    if (argc == 4 && std::strcmp(argv[1], "cc") == 0) {
        message[0] = 0xbf;
        message[1] = number(argv[2], 127);
        message[2] = number(argv[3], 127);
        message_size = 3;
    } else if (argc == 3 && std::strcmp(argv[1], "layer") == 0) {
        message[0] = 0xcf;
        message[1] = number(argv[2], 127);
        message_size = 2;
    } else {
        std::fprintf(stderr, "Usage: silakka54-sound-send cc CONTROL VALUE | layer PROGRAM\n");
        return 2;
    }

    jack_status_t status{};
    jack_client_t* client = jack_client_open("silakka54_sound_test", JackNoStartServer, &status);
    if (!client) return 1;
    jack_port_t* port = jack_port_register(client, "midi_out", JACK_DEFAULT_MIDI_TYPE, JackPortIsOutput, 0);
    jack_set_process_callback(client, process, port);
    if (jack_activate(client) != 0) return 1;
    if (jack_connect(client, jack_port_name(port), "silakka54_sound:midi_in") != 0) return 1;
    for (int i = 0; pending.load() && i < 100; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(2));
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    jack_client_close(client);
    return pending.load() ? 1 : 0;
}
