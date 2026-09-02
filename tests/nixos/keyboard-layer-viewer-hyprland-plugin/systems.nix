{ stdenv, ... }:

stdenv.hostPlatform.isLinux && stdenv.hostPlatform.is64bit
