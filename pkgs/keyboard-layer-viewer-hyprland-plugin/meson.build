project('keyboard-layer-viewer-hyprland-plugin', 'cpp',
  version: '0.1.0',
  default_options: ['buildtype=release'],
)

cpp_compiler = meson.get_compiler('cpp')
if cpp_compiler.has_argument('-std=c++23')
  add_global_arguments('-std=c++23', language: 'cpp')
elif cpp_compiler.has_argument('-std=c++2b')
  add_global_arguments('-std=c++2b', language: 'cpp')
else
  error('Could not configure a C++23 compiler')
endif

shared_module(meson.project_name(), 'main.cpp',
  dependencies: [
    dependency('hyprland'),
    dependency('libdrm'),
    dependency('libinput'),
    dependency('libudev'),
    dependency('pixman-1'),
    dependency('wayland-server'),
    dependency('xkbcommon'),
  ],
  install: true,
)
