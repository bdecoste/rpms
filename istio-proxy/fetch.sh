set -x
set -e

function check_envs() {
  if [ -z "$FETCH_DIR" ]; then
    echo "FETCH_DIR required. Please set"
    exit 1
  fi
   
  CACHE_PATH=${FETCH_DIR}/istio-proxy/bazel
}

function set_default_envs() {
  if [ -z "${PROXY_GIT_REPO}" ]; then
    PROXY_GIT_REPO=https://github.com/dmitri-d/proxy
  fi

  if [ -z "${PROXY_GIT_BRANCH}" ]; then
    PROXY_GIT_BRANCH=fix-happy-path
  fi

  if [ -z "${RECIPES_GIT_REPO}" ]; then
    RECIPES_GIT_REPO=https://github.com/Maistra/recipes-istio-proxy
  fi

  if [ -z "${RECIPES_GIT_BRANCH}" ]; then
    RECIPES_GIT_BRANCH=maistra-0.9
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
    STRIP_LATOMIC=false
  fi

  if [ -z "${REPLACE_SSL}" ]; then
    REPLACE_SSL=true
  fi

  if [ -z "${BUILD_CONFIG}" ]; then
    BUILD_CONFIG=release
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

  pushd ${CACHE_PATH}
    rm -rf base/execroot
    rm -rf root/cache
  popd

}

function correct_links() {
  # replace fully qualified links with relative links (former does not travel)
  pushd ${CACHE_PATH}
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
  rm -rf ${FETCH_DIR}/istio-proxy/proxy/bazel-*

  # remove fetch-build
  rm -rf ${CACHE_PATH}/base/external/envoy_deps_cache_*
}

function add_custom_recipes() {
  # use custom dependency recipes
  cp -rf ${FETCH_DIR}/istio-proxy/recipes/*.sh ${CACHE_PATH}/base/external/envoy/ci/build_container/build_recipes
}

function copy_bazel_build_status(){
  cp -f ${RPM_SOURCE_DIR}/bazel_get_workspace_status ${FETCH_DIR}/istio-proxy/proxy/tools/bazel_get_workspace_status
}

function add_fetch_config() {
  BUILD_OPTIONS="
# Release builds without debug symbols.
fetch:release --announce_rc=true  
"
  pushd ${FETCH_DIR}/istio-proxy/proxy
    echo "${BUILD_OPTIONS}" >> .bazelrc 
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

        add_fetch_config
        use_local_go
        copy_bazel_build_status
      fi

      if [ ! "$FETCH_ONLY" = "true" ]; then
        #clone dependency source and custom recipes
        if [ ! -d "recipes" ]; then
          git clone ${RECIPES_GIT_REPO} -b ${RECIPES_GIT_BRANCH} recipes
        fi

        #fetch dependency sources
        for filename in recipes/*.sh
        do
          FETCH=true ./$filename
        done
        rm -rf *.gz
      fi

      if [ ! -d "${bazel_dir}" ]; then
        set_path

        pushd ${FETCH_DIR}/istio-proxy/proxy
          bazel --output_base=${CACHE_PATH}/base --output_user_root=${CACHE_PATH}/root ${FETCH_OR_BUILD} --config=${BUILD_CONFIG} //...
        popd

      fi

      if [ "$FETCH_ONLY" = "true" ]; then
        popd
        exit 0
      fi

    popd
  fi
}

function add_path_markers() {
  pushd ${CACHE_PATH}
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./base/external/local_config_cc/cc_wrapper.sh
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./base/external/local_config_cc/CROSSTOOL
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

function add_BUILD_SCM_REVISIONS(){
  pushd ${FETCH_DIR}/istio-proxy/proxy
    sed -i "1i BUILD_SCM_REVISION=${BUILD_SCM_REVISION}\n" tools/bazel_get_workspace_status
  popd
}

# For devtoolset-7
function strip_latomic(){
  if [ "$STRIP_LATOMIC" = "true" ]; then
    pushd ${CACHE_PATH}/base/external
      find . -type f -name "configure.ac" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "CMakeLists.txt" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "configure" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "CROSSTOOL" -exec sed -i 's/-latomic//g' {} +
      find . -type f -name "envoy_build_system.bzl" -exec sed -i 's/-latomic//g' {} +
    popd
  fi
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
        ./openssl.sh ${CACHE_PATH}/base/external/envoy OPENSSL
      popd
      rm -rf envoy-openssl

      git clone http://github.com/bdecoste/jwt-verify-lib-openssl -b 02112019
      pushd jwt-verify-lib-openssl
        ./openssl.sh ${CACHE_PATH}/base/external/com_github_google_jwt_verify OPENSSL
      popd
      rm -rf jwt-verify-lib-openssl
    popd

    rm -rf ${CACHE_PATH}/base/external/*boringssl*

    # re-fetch for updated dependencies
    pushd ${FETCH_DIR}/istio-proxy/proxy
      bazel --output_base=${CACHE_PATH}/base --output_user_root=${CACHE_PATH}/root fetch --config=${BUILD_CONFIG} //...
    popd

    prune
  fi
}

preprocess_envs
fetch
prune
remove_build_artifacts
add_custom_recipes
add_path_markers
#add_cxx_params
replace_ssl
add_BUILD_SCM_REVISIONS
strip_latomic
correct_links
create_tarball
