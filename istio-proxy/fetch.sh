set -x
set -e

PROXY_DIR=${PROXY_DIR:-istio-proxy}
function check_envs() {
  if [ -z "$FETCH_DIR" ]; then
    echo "FETCH_DIR required. Please set"
    exit 1
  fi

	PROXY_FETCH_DIR=${FETCH_DIR}/${PROXY_DIR}
  CACHE_DIR=${PROXY_FETCH_DIR}/bazel
}

function set_default_envs() {
  if [ -z "${PROXY_GIT_REPO}" ]; then
    PROXY_GIT_REPO=https://github.com/maistra/proxy
  fi

  if [ -z "${OPENSSL_GIT_BRANCH}" ]; then
    OPENSSL_GIT_BRANCH=maistra-1.0
  fi

  if [ -z "${PROXY_GIT_BRANCH}" ]; then
    PROXY_GIT_BRANCH=maistra-1.0
  fi

  if [ -z "${CLEAN_FETCH}" ]; then
    CLEAN_FETCH=true
  fi

  if [ -z "${FETCH_ONLY}" ]; then
    FETCH_ONLY=false
  fi

  if [ -z "${CREATE_TARBALL}" ]; then
    CREATE_TARBALL=false
  fi

  if [ -z "${DEBUG_FETCH}" ]; then
    DEBUG_FETCH=false
  fi

  if [ -z "${CREATE_ARTIFACTS}" ]; then
    CREATE_ARTIFACTS=false
  fi

  if [ -z "${RPM_SOURCE_DIR}" ]; then
    RPM_SOURCE_DIR=$(pwd)
  fi

  if [ -z "${FETCH_OR_BUILD}" ]; then
    FETCH_OR_BUILD=fetch
  fi

  if [ -z "${BUILD_SCM_REVISION}" ]; then
    BUILD_SCM_REVISION=$(date +%s)
  fi

  if [ -z "${STRIP_LATOMIC}" ]; then
    STRIP_LATOMIC=true
  fi

  if [ -z "${REPLACE_SSL}" ]; then
    REPLACE_SSL=true
  fi
}

check_envs
set_default_envs

source ${RPM_SOURCE_DIR}/common.sh

check_dependencies

function preprocess_envs() {
  if [ "${CLEAN_FETCH}" == "true" ]; then
    rm -rf ${PROXY_FETCH_DIR}
  fi
}

function prune() {
  pushd ${PROXY_FETCH_DIR}
    #prune git
    if [ ! "${CREATE_ARTIFACTS}" == "true" ]; then
      find . -name ".git*" | xargs -r rm -rf
    fi

    #prune logs
    find . -name "*.log" | xargs -r rm -rf
  popd

  pushd ${CACHE_DIR}
    rm -rf base/execroot
    rm -rf root/cache
  popd

}

function correct_links() {
  # replace fully qualified links with relative links (former does not travel)
  pushd ${CACHE_DIR}
    find . -lname '/*' -exec ksh -c '
      CACHE_WORKING_DIR=$(pwd)
      for link; do
        target=$(readlink "$link")
        link=${link#./}
        root=${link//+([!\/])/..}; root=${root#/}; root=${root%..}
        rm "$link"
        target="$root${target#/}"
        target=$(echo $target | sed "s|../../..${CACHE_WORKING_DIR}/base|../../../base|")
        target=$(echo $target | sed "s|../..${CACHE_WORKING_DIR}/base|../../base|")
        target=$(echo $target | sed "s|../../..${CACHE_WORKING_DIR}/root|../../../root|")
        target=$(echo $target | sed "s|..${CACHE_WORKING_DIR}/root|../root|")
        target=$(echo $target | sed "s|../../../usr/lib/jvm|/usr/lib/jvm|")
        ln -s "$target" "$link"
      done
    ' _ {} +

    rm -rf base/external/envoy_deps/thirdparty base/external/envoy_deps/thirdparty_build
  popd
}

function remove_build_artifacts() {
  #clean
  rm -rf proxy/bazel-*

  # remove fetch-build
  rm -rf bazel/base/external/envoy_deps_cache_*
}

function copy_bazel_build_status(){
  cp -f ${RPM_SOURCE_DIR}/bazel_get_workspace_status ${PROXY_FETCH_DIR}/proxy/tools/bazel_get_workspace_status
}

function replace_python() {

  pushd ${CACHE_DIR}
    find . -type f -name "rules" -exec sed -i 's|/usr/bin/python|/usr/bin/python3|g' {} +
    sed -i 's|/usr/bin/python|/usr/bin/python3|g' base/external/local_config_cc/extra_tools/envoy_cc_wrapper
    #chmod 777 base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    #sed -i "s|/usr/bin/env python|/usr/bin/env python3|g" bazel/base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    #sed -i "s|PYTHON_BINARY = 'python'|PYTHON_BINARY = 'python3'|g" base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    find base/external -type f -name "*.py" -exec sed -i 's|.iteritems()|.items()|g' {} +
    find base/external -type f -name "*.yaml" -exec sed -i 's|.iteritems()|.items()|g' {} +
  popd

  set_python_rules_date
}

function fetch() {
  if [ ! -d "${PROXY_FETCH_DIR}" ]; then
    mkdir -p ${PROXY_FETCH_DIR}

    pushd ${PROXY_FETCH_DIR}

      #clone proxy
      git clone ${PROXY_GIT_REPO}
      pushd ${PROXY_FETCH_DIR}/proxy
        git checkout ${PROXY_GIT_BRANCH}
        SHA="$(git rev-parse --verify HEAD)"
      popd

      use_local_go
      copy_bazel_build_status

      bazel_dir="bazel"
      if [ "${DEBUG_FETCH}" == "true" ]; then
        bazel_dir="bazelorig"
      fi

      if [ ! -d "${bazel_dir}" ]; then
        set_path

        pushd ${PROXY_FETCH_DIR}/proxy
          bazel --output_base=${PROXY_FETCH_DIR}/bazel/base --output_user_root=${PROXY_FETCH_DIR}/bazel/root ${FETCH_OR_BUILD} //...
        popd

        if [ "${DEBUG_FETCH}" == "true" ]; then
          cp -rfp bazel bazelorig
        fi
      fi

      if [ "$FETCH_ONLY" = "true" ]; then
        popd
        exit 0
      fi

      if [ "${DEBUG_FETCH}" == "true" ]; then
        rm -rf bazel
        cp -rfp bazelorig bazel
      fi

    popd
  fi
}

function add_path_markers() {
  pushd ${FETCH_DIR}/istio-proxy
    sed -i "s|${PROXY_FETCH_DIR}/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/cc_wrapper.sh
    sed -i "s|${PROXY_FETCH_DIR}/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/CROSSTOOL
  popd
}

function update_compiler_flags() {
  pushd ${CACHE_DIR}
    sed -i 's|compiler_flag: "-fcolor-diagnostics"|cxx_builtin_include_directory: "/usr/include"|g' base/external/local_config_cc/CROSSTOOL
    sed -i 's|compiler_flag: "-Wself-assign"|cxx_builtin_include_directory: "/usr/lib/gcc/x86_64-redhat-linux/8/include"|g' base/external/local_config_cc/CROSSTOOL
    sed -i 's|compiler_flag: "-Wthread-safety"||g' base/external/local_config_cc/CROSSTOOL

    sed -i 's|\["-static-libstdc++", "-static-libgcc"],||g' base/external/envoy/bazel/envoy_build_system.bzl
  popd
}

function create_tarball(){
  if [ "$CREATE_TARBALL" = "true" ]; then
    # create tarball
    pushd ${FETCH_DIR}
      rm -rf proxy-full.tar.xz
      tar cf proxy-full.tar ${PROXY_DIR} --atime-preserve
      xz proxy-full.tar
    popd
  fi
}

function add_cxx_params(){
  pushd ${PROXY_FETCH_DIR}/proxy
    sed -i '1i build --cxxopt -D_GLIBCXX_USE_CXX11_ABI=1\n' .bazelrc
    sed -i '1i build --cxxopt -DENVOY_IGNORE_GLIBCXX_USE_CXX11_ABI_ERROR=1\n' .bazelrc
  popd
}

function use_local_go(){
  pushd ${PROXY_FETCH_DIR}/proxy
    sed -i 's|go_register_toolchains(go_version = GO_VERSION)|go_register_toolchains(go_version="host")|g' WORKSPACE
  popd
}

function add_BUILD_SCM_REVISIONS(){
  pushd ${PROXY_FETCH_DIR}/proxy
    sed -i "1i BUILD_SCM_REVISION=${BUILD_SCM_REVISION}\n" tools/bazel_get_workspace_status
  popd
}

# For devtoolset-7/8
function strip_latomic(){
  if [ "$STRIP_LATOMIC" = "true" ]; then
    pushd ${CACHE_DIR}/base/external
      find . -type f -name "configure.ac" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "CMakeLists.txt" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "configure" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "CROSSTOOL" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "envoy_build_system.bzl" -exec sed -i 's/-latomic//g' {} +
    popd
  fi
}

function patch_class_memaccess() {
  pushd ${PROXY_FETCH_DIR}/proxy
#    sed -i "s|memset(\&old_stats_, 0, sizeof(old_stats_));|free(\&old_stats_);\n  ::istio::mixerclient::Statistics new_stats;\n  old_stats_ = new_stats;|g" src/envoy/utils/stats.cc
    echo "build --cxxopt -Wno-error=class-memaccess" >> .bazelrc
  popd
}

function replace_ssl() {
  if [ "$REPLACE_SSL" = "true" ]; then
    pushd ${PROXY_FETCH_DIR}/proxy
      git clone http://github.com/maistra/istio-proxy-openssl -b ${OPENSSL_GIT_BRANCH}
      pushd istio-proxy-openssl
        ./openssl.sh ${PROXY_FETCH_DIR}/proxy OPENSSL
      popd
      rm -rf istio-proxy-openssl

      git clone http://github.com/maistra/envoy-openssl -b ${OPENSSL_GIT_BRANCH}
      pushd envoy-openssl
        ./openssl.sh ${CACHE_DIR}/base/external/envoy OPENSSL ${SHA}
      popd
      rm -rf envoy-openssl

      git clone http://github.com/maistra/jwt-verify-lib-openssl -b ${OPENSSL_GIT_BRANCH}
      pushd jwt-verify-lib-openssl
        ./openssl.sh ${CACHE_DIR}/base/external/com_github_google_jwt_verify OPENSSL
      popd
      rm -rf jwt-verify-lib-openssl
    popd

    rm -rf ${CACHE_DIR}/base/external/*boringssl*

    # re-fetch for updated dependencies
    pushd ${PROXY_FETCH_DIR}/proxy
      bazel --output_base=${CACHE_DIR}/base --output_user_root=${CACHE_DIR}/root fetch //...
    popd

    prune

    set_python_rules_date

  fi
}

function add_annobin_flags() {
  pushd ${PROXY_FETCH_DIR}/proxy
    BUILD_OPTIONS="build --cxxopt -fPIE
build --cxxopt -fPIC
build --cxxopt -fcf-protection=full
build --cxxopt -fstack-clash-protection
build --cxxopt -fplugin=annobin
build --cxxopt -fstack-protector-all
build --cxxopt -fstack-protector-strong
build --cxxopt -O2
build --cxxopt -fexceptions
build --cxxopt -D_GLIBCXX_ASSERTIONS
"
echo "${BUILD_OPTIONS}" >> .bazelrc

  popd

  pushd ${CACHE_DIR}/base/external/local_config_cc

    FILE="CROSSTOOL"
    DELETE_START_PATTERN="cxx_flag: \"-std=c++0x\""
    DELETE_STOP_PATTERN=""
    START_OFFSET="0"
    ADD_TEXT="  cxx_flag: \"-std=c++0x\"
  cxx_flag: \"-fPIC\"
  cxx_flag: \"-fPIE\"
  cxx_flag: \"-fcf-protection=full\"
  cxx_flag: \"-fplugin=annobin\"
  cxx_flag: \"-O2\"
  cxx_flag: \"-fstack-protector-strong\"
  cxx_flag: \"-fstack-protector-all\"
  cxx_flag: \"-fexceptions\"
  cxx_flag: \"-D_GLIBCXX_ASSERTIONS\"
"
    replace_text

    FILE="CROSSTOOL"
    DELETE_START_PATTERN="compiler_flag: \"-Wall\""
    DELETE_STOP_PATTERN=""
    START_OFFSET="0"
    ADD_TEXT="  compiler_flag: \"-Wall\"
  compiler_flag: \"-fPIC\"
  compiler_flag: \"-fPIE\"
  compiler_flag: \"-fcf-protection=full\"
  compiler_flag: \"-fplugin=annobin\"
  compiler_flag: \"-O2\"
  compiler_flag: \"-fstack-protector-strong\"
  compiler_flag: \"-fstack-protector-all\"
  compiler_flag: \"-fexceptions\"
  compiler_flag: \"-D_GLIBCXX_ASSERTIONS\"
"
    replace_text

    FILE="CROSSTOOL"
    DELETE_START_PATTERN="compiler_flag: \"-D_FORTIFY_SOURCE=1\""
    DELETE_STOP_PATTERN=""
    START_OFFSET="0"
    ADD_TEXT="    compiler_flag: \"-D_FORTIFY_SOURCE=2\"
    compiler_flag: \"-fPIC\"
    compiler_flag: \"-fPIE\"
    compiler_flag: \"-fplugin=annobin\"
    compiler_flag: \"-fcf-protection=full\"
    compiler_flag: \"-fstack-clash-protection\"
    compiler_flag: \"-fplugin=annobin\"
    compiler_flag: \"-fstack-protector-all\"
    compiler_flag: \"-fstack-protector-strong\"
    compiler_flag: \"-fexceptions\"
    compiler_flag: \"-D_GLIBCXX_ASSERTIONS\"
"
    replace_text

  popd

  pushd ${CACHE_DIR}/base/external/com_github_luajit_luajit
    sed -i 's|CCOPT= -O2 -fomit-frame-pointer|CCOPT= -O2 -fomit-frame-pointer -fPIC -fPIE -fcf-protection=full -fplugin=annobin -fstack-protector-strong -fstack-protector-all|g' src/Makefile
  popd

}

remove_rpath() {
  pushd ${CACHE_DIR}
    crosstool_lib=$(find . -name "crosstool_lib.bzl" -type f)
    sed -i 's|-Wl,-rpath,$ORIGIN/%{runtime_library_search_directories}||g' ${crosstool_lib}
    touch -m -t 210012120101 ${crosstool_lib}
  popd
}

preprocess_envs
fetch
patch_class_memaccess
replace_python
update_compiler_flags
prune
remove_build_artifacts
add_path_markers
#add_cxx_params
replace_ssl
add_BUILD_SCM_REVISIONS
strip_latomic
correct_links
add_annobin_flags
remove_rpath
create_tarball
