{
  lib,
  ccache,
  python3Packages,
  cudaPackages,
  vllmSrc,
}:

let
  sitePackages = python3Packages.python.sitePackages;
  optionalCudaDependenciesToDrop = [
    "apache-tvm-ffi"
    "cupy"
    "fastsafetensors"
    "flashinfer"
    "flashinfer-cubin"
    "flashinfer-python"
    "mistral-common"
    "mistral_common"
    "nvidia-cudnn-frontend"
    "nvidia-cutlass-dsl"
    "opencv-python-headless"
    "opentelemetry-semantic-conventions-ai"
    "quack-kernels"
    "tilelang"
    "vllm-flash-attn"
    "xformers"
  ];
  isCmakeFlagFor = name: flag: lib.hasPrefix "-D${name}=" flag || lib.hasPrefix "-D${name}:" flag;
  packageName = package: package.pname or (lib.getName package);
  keepDependency = package: !(builtins.elem (packageName package) optionalCudaDependenciesToDrop);
  isMagmaPackage = package: lib.hasPrefix "magma" (packageName package);
  ncclPascalGencode = "-gencode=arch=compute_60,code=sm_60 -gencode=arch=compute_60,code=compute_60";
  ncclPascal = cudaPackages.nccl.overrideAttrs (oldAttrs: {
    makeFlags = builtins.map (
      flag: if lib.hasPrefix "NVCC_GENCODE=" flag then "NVCC_GENCODE=${ncclPascalGencode}" else flag
    ) oldAttrs.makeFlags;
  });
  cudaPackagesPascal = cudaPackages // {
    nccl = ncclPascal;
  };
  tritonPascal = python3Packages.triton.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./triton-pascal-sm60.patch ];
  });
  torchPascal =
    (python3Packages.torch.override {
      cudaSupport = true;
      cudaPackages = cudaPackagesPascal;
      gpuTargets = [ "6.0" ];
      _tritonEffective = tritonPascal;
    }).overridePythonAttrs
      (oldAttrs: {
        # vLLM serving does not need MAGMA-backed torch.linalg CUDA routines, and
        # retaining MAGMA adds a large extra CUDA build surface for Pascal.
        patches = (oldAttrs.patches or [ ]) ++ [ ./torch-pascal-triton-sm60.patch ];
        buildInputs = builtins.filter (package: !(isMagmaPackage package)) (oldAttrs.buildInputs or [ ]);
        env = (oldAttrs.env or { }) // {
          USE_MAGMA = "0";
        };
      });
  replaceTorchTritonDependency =
    package:
    let
      name = packageName package;
    in
    if name == "torch" then
      torchPascal
    else if name == "triton" then
      tritonPascal
    else
      package;
  replaceTorchTritonDependencies = deps: builtins.map replaceTorchTritonDependency deps;
  replaceModelStackDependency =
    package:
    let
      name = packageName package;
    in
    if name == "safetensors" then
      safetensorsPascal
    else if name == "torchaudio" then
      torchaudioPascal
    else if name == "torchvision" then
      torchvisionPascal
    else if name == "torchcodec" then
      torchcodecPascal
    else if name == "transformers" then
      transformersPascal
    else
      replaceTorchTritonDependency package;
  replaceModelStackDependencies = deps: builtins.map replaceModelStackDependency deps;
  safetensorsPascal = python3Packages.safetensors.overridePythonAttrs (oldAttrs: {
    dependencies = replaceTorchTritonDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceTorchTritonDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceTorchTritonDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  transformersPascal = python3Packages.transformers.overridePythonAttrs (oldAttrs: {
    dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  torchvisionPascal =
    (python3Packages.torchvision.override {
      torch = torchPascal;
    }).overridePythonAttrs
      (oldAttrs: {
        dependencies = replaceTorchTritonDependencies (oldAttrs.dependencies or [ ]);
        propagatedBuildInputs = replaceTorchTritonDependencies (oldAttrs.propagatedBuildInputs or [ ]);
        nativeCheckInputs = replaceTorchTritonDependencies (oldAttrs.nativeCheckInputs or [ ]);
        env = (oldAttrs.env or { }) // {
          FORCE_CUDA = "1";
          TORCH_CUDA_ARCH_LIST = "6.0";
        };
      });
  torchcodecPascal =
    (python3Packages.torchcodec.override {
      torch = torchPascal;
      torchvision = torchvisionPascal;
      cudaPackages = cudaPackagesPascal;
    }).overridePythonAttrs
      (oldAttrs: {
        dependencies = replaceTorchTritonDependencies (oldAttrs.dependencies or [ ]);
        build-system = replaceTorchTritonDependencies (oldAttrs.build-system or [ ]);
        # The upstream torchcodec test suite is large and codec/device-matrix
        # oriented. Keep this override focused on producing the runtime library.
        nativeCheckInputs = [ ];
        doCheck = false;
        env = (oldAttrs.env or { }) // {
          TORCH_CUDA_ARCH_LIST = "6.0";
        };
      });
  torchaudioPascal =
    (python3Packages.torchaudio.override {
      torch = torchPascal;
      torchcodec = torchcodecPascal;
      cudaPackages = cudaPackagesPascal;
    }).overridePythonAttrs
      (oldAttrs: {
        dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
        propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
        # The upstream torchaudio test suite is not part of the vLLM runtime
        # contract, and pulls in a broad audio package test surface.
        nativeCheckInputs = [ ];
        doCheck = false;
        env = (oldAttrs.env or { }) // {
          TORCH_CUDA_ARCH_LIST = "6.0";
        };
      });
  einopsWithoutTorchChecks = python3Packages.einops.overridePythonAttrs (oldAttrs: {
    # einops only needs torch for its own upstream test matrix. vLLM already
    # brings the Pascal torch into the runtime closure.
    nativeCheckInputs = builtins.filter (package: (packageName package) != "torch") (
      oldAttrs.nativeCheckInputs or [ ]
    );
  });
  xgrammarPascal = python3Packages.xgrammar.overridePythonAttrs (oldAttrs: {
    dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  outlinesCorePascal = python3Packages.outlines-core.overridePythonAttrs (oldAttrs: {
    dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  replaceOutlinesDependency =
    package:
    if (packageName package) == "outlines-core" then
      outlinesCorePascal
    else
      replaceModelStackDependency package;
  replaceOutlinesDependencies = deps: builtins.map replaceOutlinesDependency deps;
  outlinesPascal = python3Packages.outlines.overridePythonAttrs (oldAttrs: {
    dependencies = replaceOutlinesDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceOutlinesDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceOutlinesDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  compressedTensorsPascal = python3Packages.compressed-tensors.overridePythonAttrs (oldAttrs: {
    dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  llguidancePascal = python3Packages.llguidance.overridePythonAttrs (oldAttrs: {
    dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
    propagatedBuildInputs = replaceModelStackDependencies (oldAttrs.propagatedBuildInputs or [ ]);
    nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
  });
  bitsandbytesPascal =
    (python3Packages.bitsandbytes.override {
      cudaSupport = true;
      cudaPackages = cudaPackagesPascal;
      torch = torchPascal;
    }).overridePythonAttrs
      (oldAttrs: {
        dependencies = replaceModelStackDependencies (oldAttrs.dependencies or [ ]);
        buildInputs = replaceModelStackDependencies (oldAttrs.buildInputs or [ ]);
        nativeCheckInputs = replaceModelStackDependencies (oldAttrs.nativeCheckInputs or [ ]);
        cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [
          (lib.cmakeFeature "COMPUTE_CAPABILITY" "60")
        ];
        env = (oldAttrs.env or { }) // {
          CUDAARCHS = "60";
        };
      });
  replaceVllmDependency =
    package:
    let
      name = packageName package;
    in
    if name == "compressed-tensors" then
      compressedTensorsPascal
    else if name == "einops" then
      einopsWithoutTorchChecks
    else if name == "outlines" then
      outlinesPascal
    else if name == "outlines-core" then
      outlinesCorePascal
    else if name == "safetensors" then
      safetensorsPascal
    else if name == "transformers" then
      transformersPascal
    else if name == "bitsandbytes" then
      bitsandbytesPascal
    else if name == "llguidance" then
      llguidancePascal
    else if name == "xgrammar" then
      xgrammarPascal
    else
      replaceModelStackDependency package;
  vllmDependencies = deps: builtins.map replaceVllmDependency (builtins.filter keepDependency deps);
  audioRuntimeDependencies = with python3Packages; [
    av
    soundfile
  ];
  base = python3Packages.vllm.override {
    cudaSupport = true;
    cudaPackages = cudaPackagesPascal;
    gpuTargets = [ "6.0" ];
    torch = torchPascal;
  };
in
base.overridePythonAttrs (oldAttrs: {
  pname = "vllm-p100";
  version = "0.20.0+p100";
  src = vllmSrc;

  # Preserve nixpkgs' vLLM packaging patches and add the small CUDA/Pascal
  # compatibility patches needed by this 0.20.0 source. The ROCm requirements
  # patch from nixpkgs' 0.19 package no longer applies to vLLM 0.20 and is
  # irrelevant for this CUDA-only build.
  patches =
    builtins.filter (patch: !(lib.hasInfix "drop-rocm-extra-reqs" (toString patch))) (
      oldAttrs.patches or [ ]
    )
    ++ [
      ./vllm-intermediate-tensors-get.patch
      ./vllm-disable-moe-marlin-before-turing.patch
      ./vllm-bitsandbytes-pascal.patch
      ./vllm-gemma4-pp-intermediates.patch
      ./vllm-gemma4-audio-projection-dtype.patch
    ];

  postPatch =
    (builtins.replaceStrings
      [
        ''
          substituteInPlace pyproject.toml \
            --replace-fail "torch ==" "torch >=" \
            --replace-fail "setuptools>=77.0.3,<81.0.0" "setuptools" \
            --replace-fail "grpcio-tools==1.78.0" "grpcio"
        ''
      ]
      [
        ''
          substituteInPlace pyproject.toml \
            --replace-fail "torch ==" "torch >=" \
            --replace-fail "setuptools>=77.0.3,<81.0.0" "setuptools"
        ''
      ]
      (oldAttrs.postPatch or "")
    )
    + ''
      find . \( -name '*.orig' -o -name '*.rej' \) -delete
    '';

  dependencies = vllmDependencies (oldAttrs.dependencies or [ ]) ++ audioRuntimeDependencies;
  propagatedBuildInputs = vllmDependencies (oldAttrs.propagatedBuildInputs or [ ]) ++ audioRuntimeDependencies;
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ ccache ];
  pythonRemoveDeps = (oldAttrs.pythonRemoveDeps or [ ]) ++ optionalCudaDependenciesToDrop;

  cmakeFlags =
    let
      cleanCmakeFlags = builtins.filter (
        flag:
        !(isCmakeFlagFor "TORCH_CUDA_ARCH_LIST" flag)
        && !(isCmakeFlagFor "CMAKE_CUDA_ARCHITECTURES" flag)
        && !(isCmakeFlagFor "CUTLASS_NVCC_ARCHS_ENABLED" flag)
        && !(isCmakeFlagFor "VLLM_FLASH_ATTN_SRC_DIR" flag)
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
    ];

  env = (oldAttrs.env or { }) // {
    TORCH_CUDA_ARCH_LIST = "6.0";
    CUDAARCHS = "60";
    CCACHE_COMPRESS = "1";
    CCACHE_DIR = "/nix/var/cache/ccache";
    CCACHE_UMASK = "007";
    VLLM_TARGET_DEVICE = "cuda";
    VLLM_NCCL_SO_PATH = "${ncclPascal}/lib/libnccl.so";
  };

  makeWrapperArgs = (oldAttrs.makeWrapperArgs or [ ]) ++ [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ cudaPackagesPascal.cuda_nvcc ])
    "--prefix"
    "PYTHONPATH"
    ":"
    "${tritonPascal}/${sitePackages}"
    "--set"
    "VLLM_NCCL_SO_PATH"
    "${ncclPascal}/lib/libnccl.so"
  ];

  meta = (oldAttrs.meta or { }) // {
    description = "P100/Pascal-capable vLLM build";
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
})
