{
  lib,
  stdenvNoCC,
  ccache,
  python3Packages,
  cudaPackages,
  vllmSrc,
}:

let
  sitePackages = python3Packages.python.sitePackages;
  optionalCudaDependenciesToDrop = [
    "apache-tvm-ffi"
    "bitsandbytes"
    "cupy"
    "fastsafetensors"
    "flashinfer"
    "flashinfer-cubin"
    "flashinfer-python"
    "llguidance"
    "mistral-common"
    "mistral_common"
    "nvidia-cudnn-frontend"
    "nvidia-cutlass-dsl"
    "opencv-python-headless"
    "opentelemetry-semantic-conventions-ai"
    "quack-kernels"
    "tilelang"
    "torchaudio"
    "torchvision"
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
    else if name == "xgrammar" then
      xgrammarPascal
    else
      replaceModelStackDependency package;
  vllmDependencies = deps: builtins.map replaceVllmDependency (builtins.filter keepDependency deps);
  torchPascalSitecustomize = stdenvNoCC.mkDerivation {
    pname = "torch-pascal-sitecustomize";
    version = "0.1.0";
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/${sitePackages}"
      cat > "$out/${sitePackages}/sitecustomize.py" <<'PY'
      import builtins
      import functools


      _patched = False
      _patching = False
      _real_import = builtins.__import__


      def _patch_p100_triton_support():
          global _patched, _patching
          if _patched:
              return True
          if _patching:
              return False

          _patching = True
          try:
              torch = _real_import("torch")
              torch_triton = _real_import("torch.utils._triton", fromlist=[""])
              device_interface = _real_import(
                  "torch._dynamo.device_interface", fromlist=["CudaInterface"]
              )
              CudaInterface = device_interface.CudaInterface
          except Exception:
              return False
          finally:
              _patching = False

          @functools.cache
          def _p100_has_triton():
              if not torch_triton.has_triton_package():
                  return False

              from torch._inductor.config import triton_disable_device_detection

              if triton_disable_device_detection:
                  return False

              from torch._dynamo.device_interface import get_interface_for_device

              def cuda_extra_check(device_interface):
                  return device_interface.Worker.get_device_properties().major >= 6

              def cpu_extra_check(device_interface):
                  import triton.backends

                  return "cpu" in triton.backends.backends

              def _return_true(device_interface):
                  return True

              triton_supported_devices = {
                  "cuda": cuda_extra_check,
                  "xpu": _return_true,
                  "cpu": cpu_extra_check,
                  "mtia": _return_true,
              }

              def is_device_compatible(device):
                  return (
                      device in triton_supported_devices
                      and triton_supported_devices[device](get_interface_for_device(device))
                  )

              return any(is_device_compatible(device) for device in triton_supported_devices)

          def _p100_is_triton_capable(device=None):
              return (
                  torch.version.hip is not None
                  or torch.cuda.get_device_properties(device).major >= 6
              )

          torch_triton.has_triton = _p100_has_triton
          CudaInterface.is_triton_capable = staticmethod(_p100_is_triton_capable)
          _patched = True
          return True


      def _p100_import(name, globals=None, locals=None, fromlist=(), level=0):
          module = _real_import(name, globals, locals, fromlist, level)
          if not _patched and name in {
              "torch.utils._triton",
              "torch._dynamo.device_interface",
              "torch._inductor.scheduler",
          }:
              _patch_p100_triton_support()
          return module


      if not _patch_p100_triton_support():
          builtins.__import__ = _p100_import
      PY
      runHook postInstall
    '';
  };
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

  # Keep the Nix support patches from nixpkgs' vLLM package, but use the local
  # vLLM source tree for Pascal support patches while iterating. The ROCm
  # requirements patch from nixpkgs' 0.19 package no longer applies to vLLM
  # 0.20 and is irrelevant for this CUDA-only build.
  patches = builtins.filter (patch: !(lib.hasInfix "drop-rocm-extra-reqs" (toString patch))) (
    oldAttrs.patches or [ ]
  ) ++ [
    ./vllm-intermediate-tensors-get.patch
    ./vllm-disable-moe-marlin-before-turing.patch
    ./vllm-gemma4-pp-intermediates.patch
  ];

  postPatch =
    builtins.replaceStrings
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
      (oldAttrs.postPatch or "");

  dependencies = vllmDependencies (oldAttrs.dependencies or [ ]);
  propagatedBuildInputs = vllmDependencies (oldAttrs.propagatedBuildInputs or [ ]);
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
    "PYTHONPATH"
    ":"
    "${torchPascalSitecustomize}/${sitePackages}:${tritonPascal}/${sitePackages}"
    "--set"
    "VLLM_NCCL_SO_PATH"
    "${ncclPascal}/lib/libnccl.so"
  ];

  meta = (oldAttrs.meta or { }) // {
    description = "P100/Pascal-capable vLLM build";
    maintainers = with lib.maintainers; [ conroy-cheers ];
  };
})
