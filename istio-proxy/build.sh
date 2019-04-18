set -x
set -e

function set_default_envs() {
  if [ -z "${PROXY_GIT_BRANCH}" ]; then
    PROXY_GIT_BRANCH=maistra-0.11
  fi

  if [ -z "${PROXY_NAME}" ]; then
    PROXY_NAME=servicemesh-proxy
  fi

  if [ -z "${FETCH_DIR}" ]; then
    FETCH_DIR=${RPM_BUILD_DIR}/${PROXY_NAME}
  fi

  if [ -z "${BUILD_CONFIG}" ]; then
    BUILD_CONFIG=release
  fi

  if [ -z "${TARBALL_SUFFIX}" ]; then
    TARBALL_SUFFIX=alpha
  fi

  if [ -z "${RPM_SOURCE_DIR}" ]; then
    RPM_SOURCE_DIR=.
  fi

  if [ -z "${STRIP}" ]; then
    STRIP="--strip-unneeded"
  fi

  CACHE_DIR=${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel
}

set_default_envs

source ${RPM_SOURCE_DIR}/common.sh

check_dependencies

function copy_fetch() {

  if [ "$FETCH_DIR" == "${RPM_BUILD_DIR}/${PROXY_NAME}" ]; then
    pushd ${FETCH_DIR}/proxy
      if [ -d ".git" ]; then
        SHA="$(git rev-parse --verify HEAD)"
      fi
    popd

    #bazel build expects ${PROXY_NAME}-${PROXY_GIT_BRANCH} dir
    mkdir -p ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}
    mv ${FETCH_DIR} ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}

    #rpmbuild expects ${PROXY_NAME} dir
    mkdir -p ${RPM_BUILD_DIR}/${PROXY_NAME}
  else
    pushd ${FETCH_DIR}/${PROXY_NAME}/proxy
      if [ -d ".git" ]; then
        SHA="$(git rev-parse --verify HEAD)"
      fi
    popd

    rm -rf ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}
    cp -rfp ${FETCH_DIR} ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}
  fi
}

function run_build() {
  pushd ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/proxy

    #replace fully qualified tool path from fetch
    sed -i "s|BUILD_PATH_MARKER/bazel|${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel|" ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel/base/external/local_config_cc/cc_wrapper.sh
    sed -i "s|BUILD_PATH_MARKER/bazel|${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel|" ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel/base/external/local_config_cc/CROSSTOOL

    set_python_rules_date
    RECIPES_DIR=${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME} bazel --output_base=${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel/base --output_user_root=${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/bazel/root build --config=${BUILD_CONFIG} "//..."

  popd
}

function create_artifacts() {
  if [ "${CREATE_ARTIFACTS}" == "true" ]; then
    pushd ${RPM_BUILD_DIR}/${PROXY_NAME}-${PROXY_GIT_BRANCH}
      mkdir -p usr/local/bin
      cp ${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy usr/local/bin/envoy
      cp ${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy envoy
      tar -cvf envoy-${TARBALL_SUFFIX}-${SHA}.tar usr
      gzip envoy-${TARBALL_SUFFIX}-${SHA}.tar
      sha256sum "envoy-${TARBALL_SUFFIX}-${SHA}.tar.gz" > "envoy-${TARBALL_SUFFIX}-${SHA}.sha256"

      if [ ${COPY_ARTIFACTS} == "true" ]; then
        if [ -z "${ARTIFACTS_REMOTE_HOST}" ]; then
          echo "You have to set ARTIFACTS_REMOTE_HOST variable"
          exit 1
        fi
        if [ -z "${ARTIFACTS_REMOTE_FOLDER}" ]; then
          echo "You have to set ARTIFACTS_REMOTE_FOLDER variable"
          exit 1
        fi
        scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa envoy-${TARBALL_SUFFIX}-${SHA}.tar.gz ${ARTIFACTS_REMOTE_HOST}:${ARTIFACTS_REMOTE_FOLDER}
        scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i $HOME/.ssh/id_rsa envoy-${TARBALL_SUFFIX}-${SHA}.sha256 ${ARTIFACTS_REMOTE_HOST}:${ARTIFACTS_REMOTE_FOLDER}
      fi
    popd
  fi
}

function copy_binary() {
  if [ "${FETCH_DIR}" == "${RPM_BUILD_DIR}/${PROXY_NAME}" ]; then
    pushd ${RPM_BUILD_DIR}
      if [ ! -z "${STRIP}" ]; then
        strip ${STRIP} ${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy -o ${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy-stripped
        cp ${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy-stripped ${RPM_BUILD_DIR}/envoy
      else
        cp ${PROXY_NAME}-${PROXY_GIT_BRANCH}/${PROXY_NAME}/proxy/bazel-bin/src/envoy/envoy ${RPM_BUILD_DIR}
      fi
    popd
  fi
}

set_path
copy_fetch
run_build
create_artifacts
copy_binary
