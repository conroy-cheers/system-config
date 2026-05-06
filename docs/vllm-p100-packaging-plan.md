# vLLM P100 Packaging Refactor Plan

## Goal

Make the `sleet` vLLM stack a clean composition of Nixpkgs package sets instead of a
single special-purpose `vllm-p100` derivation. `sleet` should use a nixpkgs instance
with:

```nix
{
  cudaSupport = true;
  cudaCapabilities = [ "6.0" ];
}
```

CUDA-capable packages used on `sleet` should then be built from that package set and
should naturally target compute capability 6.0 unless a package needs a generic or
P100-specific fix.

## Upstream References

- Nixpkgs vLLM 0.19 upgrade PR: https://github.com/NixOS/nixpkgs/pull/498040
- vLLM 0.20.1 release: https://github.com/vllm-project/vllm/releases/tag/v0.20.1

## Customisation Zones

### Zone 1: vLLM 0.20.1 Package

Location: `packages/vllm/default.nix`

This package should track the Nixpkgs vLLM 0.19 package from PR 498040 as closely as
possible, with only the minimal changes needed for vLLM 0.20.1. It should not contain
P100 hardware assumptions. Any unconditional vLLM patches that are needed to make
0.20.1 build correctly should live beside this package and be suitable for upstreaming
to Nixpkgs.

Execution steps:

- Copy the vLLM 0.19 Nixpkgs PR package definition and package-local patches.
- Update version, source, hashes, and dependency adjustments for vLLM 0.20.1.
- Expose this package through the Python package set so host configs can use
  `pkgs.python3Packages.vllm`.

### Zone 2: Generic Custom `cudaCapabilities` Fixes

Location: `overlays/20-cuda-capabilities/default.nix`

These fixes apply to any package that incorrectly ignores or hardcodes CUDA
architectures. They must not contain P100-only logic. They may read
`prev.config.cudaCapabilities` and pass the corresponding build flags to package
definitions or package build systems.

Candidate package fixes:

- `cudaPackages.nccl`: derive `NVCC_GENCODE` from `cudaCapabilities`.
- `cudaPackages`: keep the custom-capability CUDA package set internally consistent,
  including disabling optional forward-compatibility redists when the selected host
  driver does not require them.
- `python3Packages.bitsandbytes`: pass `COMPUTE_CAPABILITY` and `CUDAARCHS` from
  `cudaCapabilities`.
- Torch-adjacent Python packages: ensure `TORCH_CUDA_ARCH_LIST` comes from
  `cudaCapabilities` when the build system requires it.

Execution steps:

- Prefer `override` and `overrideAttrs` over copied package definitions.
- Keep source patches here only when an upstream build system ignores correctly passed
  CUDA architecture flags.
- Make these fixes useful for arbitrary custom capabilities, not just `[ "6.0" ]`.

### Zone 3: P100 / Pascal Source Patches

Location: `overlays/30-p100/default.nix` and `overlays/30-p100/patches/`

These patches are for packages whose source code has dropped, blocks, or fails to
handle Pascal / compute capability 6.0. These are expected to be less upstreamable to
Nixpkgs, but should still be clean source patches that do not make assumptions outside
their package.

Candidate package patches:

- `triton`: allow and lower code for sm_60 where the source rejects Pascal.
- `torch`: integrate the Pascal Triton compatibility patch and any necessary build
  constraints.
- `vllm`: apply Pascal-specific kernel and quantization compatibility patches.

Execution steps:

- Move P100-specific patches out of the monolithic `packages/vllm-p100` package.
- Apply patches in package-specific overrides only.
- Avoid duplicating full Nixpkgs package definitions.

## Host Composition

Execution steps:

- Add a `withCuda60` nixpkgs variant.
- Set `hosts/nixos/sleet/meta.nix` to use `nixpkgs.variant = "withCuda60"`.
- Change `sleet` to use `pkgs.python3Packages.vllm` from the host package set.
- Remove the direct `packages.vllm-p100 = pkgs.withCuda.callPackage ...` path.

## Validation

Minimum validation before considering the refactor complete:

- `nix flake check` or targeted eval for the affected outputs.
- `nix eval` confirms `sleet` uses the `withCuda60` package set.
- `nix eval` confirms the selected vLLM package is `0.20.1`.
- Build the vLLM package or the `sleet` system closure far enough to catch packaging
  errors.

Runtime benchmarking and service validation remain follow-up work after the package
graph is cleanly refactored and builds.
