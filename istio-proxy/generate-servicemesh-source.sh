DIR="$(cd $(dirname $0) ; pwd -P)"

if [ $# -ne 1 ] ; then
  echo "Usage $(basename $0) <proxy-full.tar.xz>"
  exit 1
fi

INPUT_FILE="$(cd $(dirname $1) ; pwd -P)/$(basename $1)"
OUTPUT_DIR="servicemesh-proxy"
OUTPUT_FILE="${OUTPUT_DIR}.tar.xz"

if [ ! -f "${INPUT_FILE}" ] ; then
  echo "Could not locate input file: ${INPUT_FILE}"
  exit 2
fi

XZ=/usr/bin/xz

(
  cd /tmp
  rm -rf "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}"
  (
    cd "${OUTPUT_DIR}"
    ${XZ} -dc ${INPUT_FILE} | tar -xf - --strip-components=1
  )
  tar cf - "${OUTPUT_DIR}" | ${XZ} -cz - > "${DIR}/${OUTPUT_FILE}"
  rm -rf "${OUTPUT_DIR}"
  CHECKSUM=$(md5sum "${DIR}/${OUTPUT_FILE}" | awk '{print $1}')
  sed -i "${DIR}/servicemesh-proxy.spec" -e 's+\(^%global\s*checksum\s*\).*$+\1'${CHECKSUM}'+'
  mv "${DIR}/${OUTPUT_FILE}" "${DIR}/${OUTPUT_DIR}.${CHECKSUM}.tar.xz"
)
