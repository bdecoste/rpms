set -x 
set -e

if [ -z "${BAZEL_VERSION}" ]; then
  BAZEL_VERSION=0.22.0
fi

function check_dependencies() {
  RESULT=$(bazel version)
  rm -rf ~/.cache/bazel

  if [[ $RESULT != *"${BAZEL_VERSION}"* ]]; then
    echo "Error: Istio Proxy requires Bazel ${BAZEL_VERSION}"
    exit -1
  fi
}

function set_path() {
  if [ ! -f "/root/python" ]; then
    cp /usr/bin/python3 /root/python
  fi

  export PATH=$PATH:/root
}

