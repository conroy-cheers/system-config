final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (python-final: _: {
      vllm = python-final.callPackage ../../packages/vllm {
        inherit (final) cudaPackages rocmPackages;
        cudaSupport = prev.config.cudaSupport or false;
        rocmSupport = prev.config.rocmSupport or false;
        gpuTargets = if prev.config.cudaSupport or false then prev.config.cudaCapabilities or [ ] else [ ];
      };
    })
  ];

  vllm = final.python3Packages.vllm;
}
