set -x
set -e

function check_envs() {
  if [ -z "$FETCH_DIR" ]; then
    echo "FETCH_DIR required. Please set"
    exit 1
  fi

  CACHE_DIR=${FETCH_DIR}/istio-proxy/bazel
}

function set_default_envs() {
  if [ -z "${PROXY_GIT_REPO}" ]; then
    PROXY_GIT_REPO=https://github.com/Maistra/proxy
  fi

  if [ -z "${PROXY_GIT_BRANCH}" ]; then
    PROXY_GIT_BRANCH=maistra-0.10
  fi

  if [ -z "${RECIPES_GIT_REPO}" ]; then
    RECIPES_GIT_REPO=https://github.com/Maistra/recipes-istio-proxy
  fi

  if [ -z "${RECIPES_GIT_BRANCH}" ]; then
    RECIPES_GIT_BRANCH=maistra-0.10
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
    rm -rf ${FETCH_DIR}/istio-proxy
  fi
}

function prune() {
  pushd ${FETCH_DIR}/istio-proxy
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
      PWD=$(pwd)
echo $PWD
      for link; do
        target=$(readlink "$link")
        link=${link#./}
        root=${link//+([!\/])/..}; root=${root#/}; root=${root%..}
        rm "$link"
        target="$root${target#/}"
        target=$(echo $target | sed "s|../../..${PWD}/base|../../../base|")
        target=$(echo $target | sed "s|../..${PWD}/base|../../base|")
        target=$(echo $target | sed "s|../../..${PWD}/root|../../../root|")
        target=$(echo $target | sed "s|..${PWD}/root|../root|")
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

function add_custom_recipes() {
  # use custom dependency recipes
  cp -rf ${FETCH_DIR}/istio-proxy/recipes/*.sh ${CACHE_DIR}/base/external/envoy/ci/build_container/build_recipes
}

function copy_bazel_build_status(){
  cp -f ${RPM_SOURCE_DIR}/bazel_get_workspace_status ${FETCH_DIR}/istio-proxy/proxy/tools/bazel_get_workspace_status
}

function replace_python() {
  pushd ${CACHE_DIR}
    find . -type f -name "rules" -exec sed -i 's|/usr/bin/python|/usr/bin/python3|g' {} +
    find . -type f -name "rules" | xargs touch -m -t 210012120101
    sed -i 's|/usr/bin/python|/usr/bin/python3|g' base/external/local_config_cc/extra_tools/envoy_cc_wrapper
    #chmod 777 base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    #sed -i "s|/usr/bin/env python|/usr/bin/env python3|g" bazel/base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    #sed -i "s|PYTHON_BINARY = 'python'|PYTHON_BINARY = 'python3'|g" base/execroot/__main__/bazel-out/host/bin/external/bazel_tools/tools/build_defs/pkg/build_tar
    find base/external -type f -name "*.py" -exec sed -i 's|.iteritems()|.items()|g' {} +
    find base/external -type f -name "*.yaml" -exec sed -i 's|.iteritems()|.items()|g' {} +
  popd
}

function update_envoy(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
    sed -i "s|925810d00b0d3095a8e67fd4e04e0f597ed188bb|8912fa36acdf4367d37998d98cead376762d2b49|g" WORKSPACE
    sed -i "s|26d1f14e881455546cf0e222ec92a8e1e5f65cb2c5761d63c66598b39cd9c47d|4a87094ef0a113a66baa5841cc19a0eb8524e2078cf9b495ce3f950705c63905|g" WORKSPACE
  popd
}

function fetch() {
  if [ ! -d "${FETCH_DIR}/istio-proxy" ]; then
    mkdir -p ${FETCH_DIR}/istio-proxy

    pushd ${FETCH_DIR}/istio-proxy

      #clone proxy
      if [ ! -d "proxy" ]; then
        git clone ${PROXY_GIT_REPO}
        pushd ${FETCH_DIR}/istio-proxy/proxy
        git checkout ${PROXY_GIT_BRANCH}
          if [ -d ".git" ]; then
            SHA="$(git rev-parse --verify HEAD)"
          fi
        popd

        update_envoy
        #use_local_go
        copy_bazel_build_status
      fi

      if [ ! "$FETCH_ONLY" = "true" ]; then
        #clone dependency source and custom recipes
        if [ ! -d "recipes" ]; then
          # benchmark e1c3a83b8197cf02e794f61228461c27d4e78cfb
          # cares cares-1_14_0
          # gperftools 2.6.3
          # libevent 2.1.8-stable
          # luajit 2.0.5
          # nghttp2 1.32.0
          # yaml-cpp 0.6.2
          # nghttp2 1.31.1
          # yaml-cpp 0.6.1
          # zlib 1.2.11

          git clone ${RECIPES_GIT_REPO} -b ${RECIPES_GIT_BRANCH} recipes
        fi

        #fetch dependency sources
        for filename in recipes/*.sh
        do
          FETCH=true ./$filename
        done
        rm -rf *.gz
      fi

      bazel_dir="bazel"
      if [ "${DEBUG_FETCH}" == "true" ]; then
        bazel_dir="bazelorig"
      fi

      if [ ! -d "${bazel_dir}" ]; then
        set_path

        pushd ${FETCH_DIR}/istio-proxy/proxy
          bazel --output_base=${FETCH_DIR}/istio-proxy/bazel/base --output_user_root=${FETCH_DIR}/istio-proxy/bazel/root ${FETCH_OR_BUILD} //...
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
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/cc_wrapper.sh
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/CROSSTOOL
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
      tar cf proxy-full.tar istio-proxy --atime-preserve
      xz proxy-full.tar
    popd
  fi
}

function add_cxx_params(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
    sed -i '1i build --cxxopt -D_GLIBCXX_USE_CXX11_ABI=1\n' .bazelrc
    sed -i '1i build --cxxopt -DENVOY_IGNORE_GLIBCXX_USE_CXX11_ABI_ERROR=1\n' .bazelrc
  popd
}

function use_local_go(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
    sed -i 's|go_register_toolchains()|go_register_toolchains(go_version="host")|g' WORKSPACE
  popd
}

function update_go_deps(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
    sed -i 's|def.bzl|deps.bzl|g' WORKSPACE
  popd
}

function add_BUILD_SCM_REVISIONS(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
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
  pushd ${FETCH_DIR}/istio-proxy/proxy
#    sed -i "s|memset(\&old_stats_, 0, sizeof(old_stats_));|free(\&old_stats_);\n  ::istio::mixerclient::Statistics new_stats;\n  old_stats_ = new_stats;|g" src/envoy/utils/stats.cc
    echo "build --cxxopt -Wno-error=class-memaccess" >> .bazelrc
  popd
}

function replace_ssl() {
  if [ "$REPLACE_SSL" = "true" ]; then
    pushd ${FETCH_DIR}/istio-proxy/proxy
      git clone http://github.com/bdecoste/istio-proxy-openssl -b 02112019
      pushd istio-proxy-openssl
        ./openssl.sh ${FETCH_DIR}/istio-proxy/proxy OPENSSL
      popd
      rm -rf istio-proxy-openssl

      git clone http://github.com/bdecoste/envoy-openssl -b 02112019
      pushd envoy-openssl
        ./openssl.sh ${CACHE_DIR}/base/external/envoy OPENSSL
      popd
      rm -rf envoy-openssl

      git clone http://github.com/bdecoste/jwt-verify-lib-openssl -b 02112019
      pushd jwt-verify-lib-openssl
        ./openssl.sh ${CACHE_DIR}/base/external/com_github_google_jwt_verify OPENSSL
      popd
      rm -rf jwt-verify-lib-openssl
    popd

    rm -rf ${CACHE_DIR}/base/external/*boringssl*

    # re-fetch for updated dependencies
    pushd ${FETCH_DIR}/istio-proxy/proxy
      bazel --output_base=${CACHE_DIR}/base --output_user_root=${CACHE_DIR}/root fetch //...
    popd

    prune

    pushd ${CACHE_DIR}
      find . -type f -name "rules" | xargs touch -m -t 210012120101
    popd

  fi
}

preprocess_envs
fetch
patch_class_memaccess
replace_python
update_compiler_flags
prune
remove_build_artifacts
add_custom_recipes
add_path_markers
#add_cxx_params
#update_go_deps
replace_ssl
add_BUILD_SCM_REVISIONS
strip_latomic
correct_links
create_tarball
