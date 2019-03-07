set -x
set -e

function check_envs() {
  if [ -z "$FETCH_DIR" ]; then
    echo "FETCH_DIR required. Please set"
    exit 1
  fi
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
    STRIP_LATOMIC=false
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
  #prune git
  if [ ! "${CREATE_ARTIFACTS}" == "true" ]; then
    find . -name ".git*" | xargs -r rm -rf
  fi

  #prune logs
  find . -name "*.log" | xargs -r rm -rf

  #prune gzip
  #find . -name "*.gz" | xargs -r rm -rf

  #prune go sdk
  GO_HOME=/usr/lib/golang
  #rm -rf bazel/base/external/go_sdk/{api,bin,lib,pkg,wrc,test,misc,doc,blog}
  #ln -s ${GO_HOME}/api bazel/base/external/go_sdk/api
  #ln -s ${GO_HOME}/bin bazel/base/external/go_sdk/bin
  #ln -s ${GO_HOME}/lib bazel/base/external/go_sdk/lib
  #ln -s ${GO_HOME}/pkg bazel/base/external/go_sdk/pkg
  #ln -s ${GO_HOME}/src bazel/base/external/go_sdk/src
  #ln -s ${GO_HOME}/test bazel/base/external/go_sdk/test

  #prune boringssl tests
  #rm -rf boringssl/crypto/cipher_extra/test

  #prune grpc tests
  rm -rf bazel/base/external/com_github_grpc_grpc/test

  #prune build_tools
  #cp -rf BUILD.bazel bazel/base/external/io_bazel_rules_go/go/toolchain/BUILD.bazel

  #prune unecessary files
  #pushd ${FETCH_DIR}/istio-proxy/bazel
    #find . -name "*.html" | xargs -r rm -rf
    #find . -name "*.zip" | xargs -r rm -rf
    #find . -name "example" | xargs -r rm -rf
    #find . -name "examples" | xargs -r rm -rf
    #find . -name "sample" | xargs -r rm -rf
    #find . -name "samples" | xargs -r rm -rf
    #find . -name "android" | xargs -r rm -rf
    #find . -name "osx" | xargs -r rm -rf
    #find . -name "*.a" | xargs -r rm -rf
    #find . -name "*.so" | xargs -r rm -rf
    #rm -rf bazel/base/external/go_sdk/src/archive/
  #popd


  pushd ${FETCH_DIR}/istio-proxy
    rm -rf bazel/base/execroot
    rm -rf bazel/root/cache
#    find . -name "*.o" | xargs -r rm
  popd

}

function correct_links() {
  # replace links with copies (links are fully qualified paths so don't travel)
  pushd ${FETCH_DIR}/istio-proxy/bazel
    find . -lname '/*' -exec ksh -c '
      for link; do
        target=$(readlink "$link")
        link=${link#./}
        root=${link//+([!\/])/..}; root=${root#/}; root=${root%..}
        rm "$link"
        target="$root${target#/}"
        target=$(echo $target | sed "s|../../..${FETCH_DIR}/istio-proxy/bazel/base|../../../base|")
        target=$(echo $target | sed "s|../..${FETCH_DIR}/istio-proxy/bazel/base|../../base|")
        target=$(echo $target | sed "s|../../..${FETCH_DIR}/istio-proxy/bazel/root|../../../root|")
        target=$(echo $target | sed "s|..${FETCH_DIR}/istio-proxy/bazel/root|../root|")
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
  cp -rf recipes/*.sh bazel/base/external/envoy/ci/build_container/build_recipes
}

function copy_bazel_build_status(){
  cp -f ${RPM_SOURCE_DIR}/bazel_get_workspace_status ${FETCH_DIR}/istio-proxy/proxy/tools/bazel_get_workspace_status
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

        use_local_go
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
          bazel --output_base=${FETCH_DIR}/istio-proxy/bazel/base --output_user_root=${FETCH_DIR}/istio-proxy/bazel/root --batch ${FETCH_OR_BUILD} //...
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

      prune

      correct_links

      remove_build_artifacts

      add_custom_recipes

    popd
  fi
}

function add_path_markers() {
  pushd ${FETCH_DIR}/istio-proxy
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/cc_wrapper.sh
    sed -i "s|${FETCH_DIR}/istio-proxy/bazel|BUILD_PATH_MARKER/bazel|" ./bazel/base/external/local_config_cc/CROSSTOOL
  popd
}

function create_tarball(){
  if [ "$CREATE_TARBALL" = "true" ]; then
    # create tarball
    pushd ${FETCH_DIR}
      rm -rf proxy-full.tar.xz
      tar cf proxy-full.tar istio-proxy --exclude=istio-proxy/bazelorig --exclude=istio-proxy/bazel/X --atime-preserve
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
    pushd ${FETCH_DIR}/istio-proxy/bazel/base/external
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
        ./openssl.sh ${FETCH_DIR}/istio-proxy/bazel/base/external/envoy OPENSSL
      popd
      rm -rf envoy-openssl

      git clone http://github.com/bdecoste/jwt-verify-lib-openssl -b 02112019
      pushd jwt-verify-lib-openssl
        cat ${FETCH_DIR}/istio-proxy/bazel/base/external/com_github_google_jwt_verify/WORKSPACE
        ./openssl.sh ${FETCH_DIR}/istio-proxy/bazel/base/external/com_github_google_jwt_verify OPENSSL
      popd
      rm -rf jwt-verify-lib-openssl
    popd

    rm -rf ${FETCH_DIR}/istio-proxy/bazel/base/external/*boringssl*

    # re-fetch for updated dependencies
    pushd ${FETCH_DIR}/istio-proxy/proxy
      bazel --output_base=${FETCH_DIR}/istio-proxy/bazel/base --output_user_root=${FETCH_DIR}/istio-proxy/bazel/root --batch ${FETCH_OR_BUILD} //...
    popd
  fi
}

preprocess_envs
fetch
add_path_markers
#add_cxx_params
replace_ssl
add_BUILD_SCM_REVISIONS
strip_latomic
create_tarball
