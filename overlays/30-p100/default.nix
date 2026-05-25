final: prev:
let
  inherit (prev) lib;

  isP100Cuda =
    (prev.config.cudaSupport or false)
    &&
      (prev.config.cudaCapabilities or [ ]) == [
        "6.0"
      ];

  packageName = package: package.pname or (lib.getName package);
  isMagmaPackage = package: lib.hasPrefix "magma" (packageName package);
  isCmakeFlagFor = name: flag: lib.hasPrefix "-D${name}=" flag || lib.hasPrefix "-D${name}:" flag;

  optionalCudaDependenciesToDrop = [
    "apache-tvm-ffi"
    "cupy"
    "fastsafetensors"
    "flashinfer"
    "flashinfer-cubin"
    "flashinfer-python"
    "nvidia-cudnn-frontend"
    "nvidia-cutlass-dsl"
    "opencv-python-headless"
    "quack-kernels"
    "tilelang"
    "vllm-flash-attn"
    "xformers"
  ];
  optionalCudaBuildInputsToDrop = [
    "cudnn"
    "libcufile"
  ];

  keepDependency = package: !(builtins.elem (packageName package) optionalCudaDependenciesToDrop);
  keepBuildInput = package: !(builtins.elem (packageName package) optionalCudaBuildInputsToDrop);
  p100Dependencies = deps: builtins.filter keepDependency deps;
in
lib.optionalAttrs isP100Cuda {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      python-final: python-prev:
      let
        tritonPascal = python-prev.triton.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or [ ]) ++ [ ./patches/triton-pascal-sm60.patch ];
        });

        torchPascal =
          (python-prev.torch.override {
            cudaSupport = true;
            cudaPackages = final.cudaPackages;
            gpuTargets = [ "6.0" ];
            withNvshmem = false;
            _tritonEffective = python-final.triton;
          }).overridePythonAttrs
            (oldAttrs: {
              patches = (oldAttrs.patches or [ ]) ++ [ ./patches/torch-pascal-triton-sm60.patch ];
              buildInputs = builtins.filter (package: !(isMagmaPackage package)) (oldAttrs.buildInputs or [ ]);
              env = (oldAttrs.env or { }) // {
                USE_MAGMA = "0";
                TORCH_CUDA_ARCH_LIST = "6.0";
                CUDAARCHS = "60";
              };
            });
      in
      {
        triton = tritonPascal;
        torch = torchPascal;

        vllm =
          (python-prev.vllm.override {
            cudaSupport = true;
            cudaPackages = final.cudaPackages;
            gpuTargets = [ "6.0" ];
            torch = python-final.torch;
          }).overridePythonAttrs
            (oldAttrs: {
              patches = (oldAttrs.patches or [ ]) ++ [
                ./patches/vllm-p100-cmake-sm60.patch
                ./patches/vllm-p100-setup-gate-flash-attn.patch
                ./patches/vllm-moe-wna16-half-atomic-pascal.patch
                ./patches/vllm-intermediate-tensors-get.patch
                ./patches/vllm-disable-moe-marlin-before-turing.patch
                ./patches/vllm-bitsandbytes-pascal.patch
                ./patches/vllm-gemma4-pp-intermediates.patch
                ./patches/vllm-gemma4-audio-projection-dtype.patch
                ./patches/vllm-gemma4-fused-quantized-experts.patch
                ./patches/vllm-moe-merge-partial-tuned-config.patch
                ./patches/vllm-p100-gemma4-moe-config.patch
                ./patches/vllm-fp8-e5m2-disable-query-quant.patch
                ./patches/vllm-triton-decode-gqa-block-h.patch
              ];

              dependencies = p100Dependencies (oldAttrs.dependencies or [ ]);
              propagatedBuildInputs = p100Dependencies (oldAttrs.propagatedBuildInputs or [ ]);
              buildInputs = builtins.filter keepBuildInput (oldAttrs.buildInputs or [ ]);
              pythonRemoveDeps = (oldAttrs.pythonRemoveDeps or [ ]) ++ optionalCudaDependenciesToDrop;
              nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ final.ccache ];

              cmakeFlags =
                let
                  cleanCmakeFlags = builtins.filter (
                    flag:
                    !(isCmakeFlagFor "TORCH_CUDA_ARCH_LIST" flag)
                    && !(isCmakeFlagFor "CMAKE_CUDA_ARCHITECTURES" flag)
                    && !(isCmakeFlagFor "CUTLASS_NVCC_ARCHS_ENABLED" flag)
                    && !(isCmakeFlagFor "CAFFE2_USE_CUDNN" flag)
                    && !(isCmakeFlagFor "CAFFE2_USE_CUFILE" flag)
                  ) (oldAttrs.cmakeFlags or [ ]);
                in
                cleanCmakeFlags
                ++ [
                  (lib.cmakeFeature "TORCH_CUDA_ARCH_LIST" "6.0")
                  (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "60")
                  (lib.cmakeFeature "CUTLASS_NVCC_ARCHS_ENABLED" "60")
                  (lib.cmakeFeature "CMAKE_C_COMPILER_LAUNCHER" "ccache")
                  (lib.cmakeFeature "CMAKE_CXX_COMPILER_LAUNCHER" "ccache")
                  (lib.cmakeFeature "CMAKE_CUDA_COMPILER_LAUNCHER" "ccache")
                  (lib.cmakeFeature "CAFFE2_USE_CUDNN" "OFF")
                  (lib.cmakeFeature "CAFFE2_USE_CUFILE" "OFF")
                ];

              env = (oldAttrs.env or { }) // {
                TORCH_CUDA_ARCH_LIST = "6.0";
                CUDAARCHS = "60";
                CCACHE_COMPRESS = "1";
                CCACHE_DIR = "/nix/var/cache/ccache";
                CCACHE_UMASK = "007";
                VLLM_TARGET_DEVICE = "cuda";
                VLLM_NCCL_SO_PATH = "${final.cudaPackages.nccl}/lib/libnccl.so";
              };

              makeWrapperArgs = (oldAttrs.makeWrapperArgs or [ ]) ++ [
                "--prefix"
                "PATH"
                ":"
                (lib.makeBinPath [ final.cudaPackages.cuda_nvcc ])
              ];
            });
      }
    )
  ];
}
