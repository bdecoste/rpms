set -x 
set -e

if [ -z "${BAZEL_VERSION}" ]; then
  BAZEL_VERSION=0.22.0
fi

function check_dependencies() {
  RESULT=$(bazel version)
  rm -rf ${HOME}/.cache/bazel

  if [[ $RESULT != *"${BAZEL_VERSION}"* ]]; then
    echo "Error: Istio Proxy requires Bazel ${BAZEL_VERSION}"
    exit -1
  fi
}
function set_python_rules_date() {
  pushd ${CACHE_DIR}
    find . -type f -name "rules" | xargs touch -m -t 210012120101
  popd
}

function set_path() {
  if [ ! -f "${HOME}/python" ]; then
    cp /usr/bin/python3 ${HOME}/python
  fi

  export PATH=$PATH:$HOME
}

