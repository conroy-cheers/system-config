{
  lib,
  networkmanager,
}:

let
  replacedMesonOptions = [
    "bluez5_dun"
    "clat"
    "concheck"
    "crypto"
    "dhcpcd"
    "dnsmasq"
    "docs"
    "ebpf"
    "firewalld_zone"
    "ifupdown"
    "introspection"
    "iptables"
    "iwd"
    "libaudit"
    "libpsl"
    "man"
    "mobile_broadband_provider_info_database"
    "modem_manager"
    "more_logging"
    "nft"
    "nm_cloud_setup"
    "nmtui"
    "ovs"
    "polkit"
    "polkit_agent_helper_1"
    "ppp"
    "pppd"
    "qt"
    "readline"
    "selinux"
    "vapi"
  ];
  isReplacedMesonFlag = flag: lib.any (option: lib.hasInfix "-D${option}=" flag) replacedMesonOptions;

  omittedNativeInputs = [
    "bpftools"
    "clang-wrapper"
    "docbook-xml"
    "docbook-xsl-nons"
    "elfutils"
    "gtk-doc"
    "libxslt"
    "python3"
    "vala"
  ];
  omittedBuildInputs = [
    "audit"
    "bluez"
    "curl"
    "dnsmasq"
    "jansson"
    "libbpf"
    "libpsl"
    "libselinux"
    "mobile-broadband-provider-info"
    "modemmanager"
    "newt"
    "polkit"
    "ppp"
    "slang"
  ];
  keepInput = omitted: input: !(lib.elem (lib.getName input) omitted);
in
networkmanager.overrideAttrs (old: {
  pname = "shrimpus-networkmanager";

  mesonFlags = lib.filter (flag: !isReplacedMesonFlag flag) old.mesonFlags ++ [
    "-Dbluez5_dun=false"
    "-Dclat=false"
    "-Dconcheck=false"
    "-Dcrypto=null"
    "-Ddhcpcd="
    "-Ddnsmasq="
    "-Ddocs=false"
    "-Debpf=false"
    "-Dfirewalld_zone=false"
    "-Difupdown=false"
    "-Dintrospection=false"
    "-Diptables="
    "-Diwd=false"
    "-Dlibaudit=no"
    "-Dlibpsl=false"
    "-Dman=false"
    "-Dmobile_broadband_provider_info_database="
    "-Dmodem_manager=false"
    "-Dmore_logging=false"
    "-Dnft="
    "-Dnm_cloud_setup=false"
    "-Dnmtui=false"
    "-Dovs=false"
    "-Dpolkit=false"
    "-Dpolkit_agent_helper_1="
    "-Dppp=false"
    "-Dpppd="
    "-Dqt=false"
    "-Dreadline=libreadline"
    "-Dselinux=false"
    "-Dvapi=false"
  ];

  nativeBuildInputs = lib.filter (keepInput omittedNativeInputs) old.nativeBuildInputs;
  buildInputs = lib.filter (keepInput omittedBuildInputs) old.buildInputs;
  propagatedBuildInputs = [ ];

  postInstall = (old.postInstall or "") + ''
    mkdir -p "$devdoc" "$man"
  '';
})
