final: prev:
let
  inherit (prev) lib;

  cudaSupport = prev.config.cudaSupport or false;
  cudaCapabilities = prev.config.cudaCapabilities or [ ];
  hasCustomCudaCapabilities = cudaSupport && cudaCapabilities != [ ];
  unpatchedCudaPackages = prev.cudaPackages_12_8 or prev.cudaPackages;
  baseCudaPackages =
    if unpatchedCudaPackages ? overrideScope then
      unpatchedCudaPackages.overrideScope (
        cuda-final: cuda-prev: {
          # The compatibility package is optional and can be null when the host
          # driver is new enough. Keeping it enabled for custom CUDA package sets
          # can force a broken redist package into otherwise valid CUDA builds.
          cuda_compat = null;
          autoAddCudaCompatRunpath = cuda-prev.autoAddCudaCompatRunpath.override {
            cuda_compat = cuda-final.cuda_compat;
          };
        }
      )
    else
      unpatchedCudaPackages;

  cudaArch =
    capability:
    lib.pipe capability [
      (lib.removeSuffix "+PTX")
      (lib.replaceStrings [ "." ] [ "" ])
    ];

  torchCudaArchList = lib.concatStringsSep ";" cudaCapabilities;
  cudaArchList = lib.concatMapStringsSep ";" cudaArch cudaCapabilities;
  ncclGencode = lib.concatMapStringsSep " " (
    capability:
    let
      arch = cudaArch capability;
    in
    "-gencode=arch=compute_${arch},code=sm_${arch} -gencode=arch=compute_${arch},code=compute_${arch}"
  ) cudaCapabilities;

  isCmakeFlagFor = name: flag: lib.hasPrefix "-D${name}=" flag || lib.hasPrefix "-D${name}:" flag;
  replaceCmakeFeature =
    name: value: flags:
    builtins.filter (flag: !(isCmakeFlagFor name flag)) flags
    ++ [
      (lib.cmakeFeature name value)
    ];
in
lib.optionalAttrs hasCustomCudaCapabilities {
  cudaPackages = baseCudaPackages // rec {
    cuda_compat = null;
    autoAddCudaCompatRunpath = baseCudaPackages.autoAddCudaCompatRunpath.override {
      inherit cuda_compat;
    };
    cuda_cudart = baseCudaPackages.cuda_cudart.override {
      inherit cuda_compat;
    };

    nccl = (baseCudaPackages.nccl.override { inherit cuda_cudart; }).overrideAttrs (oldAttrs: {
      makeFlags = builtins.map (
        flag: if lib.hasPrefix "NVCC_GENCODE=" flag then "NVCC_GENCODE=${ncclGencode}" else flag
      ) (oldAttrs.makeFlags or [ ]);
    });
  };

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      python-final: python-prev:
      let
        withTorchArchEnv =
          package:
          package.overridePythonAttrs (oldAttrs: {
            env = (oldAttrs.env or { }) // {
              TORCH_CUDA_ARCH_LIST = torchCudaArchList;
              CUDAARCHS = cudaArchList;
            };
          });
      in
      {
        torch = python-prev.torch.override {
          cudaSupport = true;
          cudaPackages = final.cudaPackages;
          gpuTargets = cudaCapabilities;
        };

        bitsandbytes =
          (python-prev.bitsandbytes.override {
            cudaSupport = true;
            cudaPackages = final.cudaPackages;
            torch = python-final.torch;
          }).overridePythonAttrs
            (oldAttrs: {
              cmakeFlags = replaceCmakeFeature "COMPUTE_CAPABILITY" cudaArchList (oldAttrs.cmakeFlags or [ ]);
              env = (oldAttrs.env or { }) // {
                CUDAARCHS = cudaArchList;
              };
            });

        torchvision = withTorchArchEnv (python-prev.torchvision.override { torch = python-final.torch; });

        torchcodec = withTorchArchEnv (
          python-prev.torchcodec.override {
            torch = python-final.torch;
            torchvision = python-final.torchvision;
            cudaPackages = final.cudaPackages;
          }
        );

        torchaudio = withTorchArchEnv (
          python-prev.torchaudio.override {
            torch = python-final.torch;
            torchcodec = python-final.torchcodec;
            cudaPackages = final.cudaPackages;
          }
        );
      }
    )
  ];
}
