set -x
set -e

function set_default_envs() {
  if [ -z "${PROXY_GIT_BRANCH}" ]; then
    PROXY_GIT_BRANCH=maistra-0.9
  fi

  if [ -z "${FETCH_DIR}" ]; then
    FETCH_DIR=${RPM_BUILD_DIR}/istio-proxy
  fi

  if [ -z "${BUILD_CONFIG}" ]; then
    BUILD_CONFIG=release
  fi

  if [ -z "${RPM_SOURCE_DIR}" ]; then
    RPM_SOURCE_DIR=.
  fi

  if [ -z "${TEST_ENVOY}" ]; then
    TEST_ENVOY=true
  fi
}

set_default_envs

source ${RPM_SOURCE_DIR}/common.sh

check_dependencies

function run_tests() {
  if [ "${RUN_TESTS}" == "true" ]; then
    pushd ${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/proxy
      if [ "${RUN_TESTS}" == "true" ]; then
        if [ "${FORCE_TEST_FAILURE}" == "true" ]; then
          sed -i 's|ASSERT_TRUE|ASSERT_FALSE|g' src/istio/mixerclient/check_cache_test.cc
          sed -i 's|EXPECT_TRUE|EXPECT_FALSE|g' src/istio/mixerclient/check_cache_test.cc
          sed -i 's|EXPECT_OK|EXPECT_FALSE|g' src/istio/mixerclient/check_cache_test.cc
          sed -i 's|TEST_F|TEST|g' src/istio/mixerclient/check_cache_test.cc
        fi

        bazel --output_base=${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/bazel/base --output_user_root=${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/bazel/root test --test_env=ENVOY_IP_TEST_VERSIONS=v4only --config=${BUILD_CONFIG} "//..."

        if [ "${TEST_ENVOY}" == "true" ]; then
          bazel --output_base=${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/bazel/base --output_user_root=${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/bazel/root test --test_env=ENVOY_IP_TEST_VERSIONS=v4only --run_under=${RPM_BUILD_DIR}/istio-proxy-${PROXY_GIT_BRANCH}/istio-proxy/proxy/external_tests.sh --config=${BUILD_CONFIG} "@envoy//test/..."
        fi
      fi
    popd
  fi
}

set_default_envs
set_path
run_tests


