declare name "Silakka54 Sound";
declare version "1";

import("stdfaust.lib");

candidate_l_ctrl = button("candidate_l_ctrl");
candidate_l_alt = button("candidate_l_alt");
candidate_l_gui = button("candidate_l_gui");
candidate_r_gui = button("candidate_r_gui");
candidate_r_alt = button("candidate_r_alt");
candidate_r_ctrl = button("candidate_r_ctrl");
ctrl_gate = checkbox("ctrl");
alt_gate = checkbox("alt");
gui_gate = checkbox("gui");
shift_gate = checkbox("shift");
layer = nentry("layer", 0, 0, 7, 1);

rising(x) = (x > 0.5) * (x' <= 0.5);
changed(x) = x != x';

glass(freq, brightness) =
    0.62 * os.osc(freq)
  + 0.23 * os.osc(freq * 2.01)
  + (0.10 + 0.12 * brightness) * os.osc(freq * 3.99)
  + (0.05 + 0.15 * brightness) * os.osc(freq * 6.03);

tick(freq, gate) = glass(freq, 0.45) * en.ar(0.0007, 0.030, rising(gate)) * 0.105;

shift_smooth = shift_gate : si.smooth(ba.tau2pole(0.012));
held(freq, gate) = glass(freq, shift_smooth) * en.adsr(0.003, 0.045, 0.045, 0.060, gate) * 0.22;

candidate_l_ctrl_voice = tick(293.665, candidate_l_ctrl);
candidate_l_alt_voice = tick(349.228, candidate_l_alt);
candidate_l_gui_voice = tick(440.000, candidate_l_gui);
candidate_r_gui_voice = tick(440.000, candidate_r_gui);
candidate_r_alt_voice = tick(349.228, candidate_r_alt);
candidate_r_ctrl_voice = tick(293.665, candidate_r_ctrl);

ctrl_voice = held(146.832, ctrl_gate);
alt_voice = held(174.614, alt_gate);
gui_voice = held(220.000, gui_gate);

layer_frequency =
    (layer == 0) * 293.665
  + (layer == 1) * 587.330
  + (layer == 2) * 698.456
  + (layer == 3) * 880.000
  + (layer == 4) * 1046.502;
layer_trigger = changed(layer) * (layer >= 0) * (layer <= 4);
layer_voice = glass(layer_frequency, 0.7) * en.ar(0.0015, 0.095, layer_trigger) * 0.16;

shift_halo = no.noise : fi.highpass(2, 2800) : fi.lowpass(2, 10500)
    : *(en.adsr(0.002, 0.035, 0.025, 0.055, shift_gate) * 0.018);

left_candidate =
    candidate_l_ctrl_voice * 0.82 + candidate_l_alt_voice * 0.82 + candidate_l_gui_voice * 0.82
  + candidate_r_gui_voice * 0.57 + candidate_r_alt_voice * 0.57 + candidate_r_ctrl_voice * 0.57;
right_candidate =
    candidate_l_ctrl_voice * 0.57 + candidate_l_alt_voice * 0.57 + candidate_l_gui_voice * 0.57
  + candidate_r_gui_voice * 0.82 + candidate_r_alt_voice * 0.82 + candidate_r_ctrl_voice * 0.82;

left_held = ctrl_voice * 0.76 + alt_voice * 0.70 + gui_voice * 0.64;
right_held = ctrl_voice * 0.64 + alt_voice * 0.70 + gui_voice * 0.76;

dry_left = left_candidate + left_held + layer_voice * 0.707 + shift_halo * 0.65;
dry_right = right_candidate + right_held + layer_voice * 0.707 + shift_halo * 0.65;

condition(x) = x : fi.highpass(1, 35);
soft_limit = *(1.35) : ma.tanh : /(0.874053);

wet_left = condition(dry_left) + 0.11 * de.delay(2048, 613, condition(dry_right));
wet_right = condition(dry_right) + 0.11 * de.delay(2048, 487, condition(dry_left));

process = (wet_left : soft_limit), (wet_right : soft_limit);
