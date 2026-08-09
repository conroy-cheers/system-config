{ callPackage, inputs }:

callPackage ../../packages/silakka54 {
  qmkSource = inputs.qmk;
  qmkRev = inputs.qmk.rev;
}
