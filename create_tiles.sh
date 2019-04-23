#!/bin/bash
shopt -s extglob

THREADS="4"
INPUT_DIR="./input"

# Examples
LR_SCALE=25%
LR_FILTER=Catrom
LR_INTERPOLATE=Catrom
LR_OUTPUT_DIR="./output/LR"

# Ground truth
HR_SCALE=100%
HR_FILTER=point
HR_INTERPOLATE=Nearest
HR_OUTPUT_DIR="./output/HR"

# Min and max must be equal
MIN_TILE_WIDTH=128
MIN_TILE_HEIGHT=128

MAX_TILE_WIDTH=128
MAX_TILE_HEIGHT=128

# Category regexp for Skyrim SE
CATEGORY_REGEXP='s/.*_\(a\|b\|d\|e\|g\|h\|m\|n\|p\|s\|an\|bl\|em\|sk\|msn\|rim\)$/\1/ip'

for OPTION in "$@"; do
  case ${OPTION} in
    -t=*|--threads=*)
    THREADS="${OPTION#*=}"
    shift
    ;;
    -i=*|--input-dir=*)
    INPUT_DIR="${OPTION#*=}"
    shift
    ;;
    --lr-scale-=*)
    LR_SCALE="${OPTION#*=}"
    shift
    ;;
    --lr-filter=*)
    LR_FILTER="${OPTION#*=}"
    shift
    ;;
    --lr-interpolate-=*)
    LR_INTERPOLATE="${OPTION#*=}"
    shift
    ;;
    -l=*|--lr-output-dir=*)
    LR_OUTPUT_DIR="${OPTION#*=}"
    shift
    ;;
    --hr-scale-=*)
    HR_SCALE="${OPTION#*=}"
    shift
    ;;
    --hr-filter=*)
    HR_FILTER="${OPTION#*=}"
    shift
    ;;
    --hr-interpolate-=*)
    HR_INTERPOLATE="${OPTION#*=}"
    shift
    ;;
    -h=*|--hr-output-dir=*)
    HR_OUTPUT_DIR="${OPTION#*=}"
    shift
    ;;
    -w=*|--tile-width=*)
    MIN_TILE_WIDTH="${OPTION#*=}"
    MAX_TILE_WIDTH="${OPTION#*=}"
    shift
    ;;
    -h=*|--tile-height=*)
    MIN_TILE_HEIGHT="${OPTION#*=}"
    MAX_TILE_HEIGHT="${OPTION#*=}"
    shift
    ;;
    *)
      echo "usage: $@ ..."
      echo "-t, --threads \"<number>\" (default: ${THREADS})"
      echo "-i, --input-dir \"<input dir>\" (default: ${INPUT_DIR})"
      echo "--lr-scale \"<percentage>\" (default: ${LR_SCALE})"
      echo "--lr-filter \"<filter>\" (default: ${LR_FILTER})"
      echo "--lr-interpolate \"<interpolate>\" (default: ${LR_INTERPOLATE})"
      echo "-l, --lr-output-dir \"<lr output dir>\" (default: ${LR_OUTPUT_DIR})"
      echo "--hr-scale \"<percentage>\" (default: ${HR_SCALE})"
      echo "--hr-filter \"<filter>\" (default: ${HR_FILTER})"
      echo "--hr-interpolate \"<interpolate>\" (default: ${HR_INTERPOLATE})"
      echo "-h, --hr-output-dir \"<hr output dir>\" (default: ${HR_OUTPUT_DIR})"
      echo "-w, --tile-width \"<pixels>\" (default: ${MIN_TILE_WIDTH})"
      echo "-h, --tile-height \"<pixels>\" (default: ${MIN_TILE_HEIGHT})"
      exit 1
    ;;
  esac
done

wait_for_jobs() {
  local JOBLIST=($(jobs -p))
  if [ "${#JOBLIST[@]}" -gt "${THREADS}" ]; then
    for JOB in ${JOBLIST}; do
      echo Waiting for job ${JOB}...
      wait ${JOB}
    done
  fi
}

while read FILENAME; do

  DIRNAME=$(dirname "${FILENAME}")

  BASENAME=$(basename "${FILENAME}")
  BASENAME_NO_EXT="${BASENAME%.*}"

  ESCAPED_DIR=$(printf '%q' "${DIRNAME}")
  ESCAPED_FILE=$(printf '%q' "${FILENAME}")

  DIRNAME_HASH=$(echo ${DIRNAME} | md5sum | cut -d' ' -f1)

  CATEGORY=$(echo ${BASENAME} | sed -ne "${CATEGORY_REGEXP}")

  if [ ! -f "${OUTPUT_DIR}/${DIRNAME_HASH}_${BASENAME_NO_EXT}_000.png" ]; then

    IMAGE_INFO=$(identify -format '%[width] %[height] %[channels]' "${FILENAME}")
    IMAGE_WIDTH=$(echo ${IMAGE_INFO} | cut -d' ' -f 1)
    IMAGE_HEIGHT=$(echo ${IMAGE_INFO} | cut -d' ' -f 2)
    IMAGE_CHANNELS=$(echo ${IMAGE_INFO} | cut -d' ' -f 3)

    RELATIVE_DIR=$(realpath --relative-to "${INPUT_DIR}" "${DIRNAME}")

    if [ "${IMAGE_WIDTH}" -ge "${MIN_TILE_WIDTH}" ] && [ "${IMAGE_HEIGHT}" -ge "${MIN_TILE_HEIGHT}" ]; then

      VERTICAL_SUBDIVISIONS=$((${IMAGE_HEIGHT} / ${MAX_TILE_HEIGHT}))
      if [ "${VERTICAL_SUBDIVISIONS}" -lt "1" ]; then
        VERTICAL_SUBDIVISIONS=$((${IMAGE_HEIGHT} / ${MIN_TILE_HEIGHT}))
      fi
      HORIZONTAL_SUBDIVISIONS=$((${IMAGE_WIDTH} / ${MAX_TILE_WIDTH}))
      if [ "${HORIZONTAL_SUBDIVISIONS}" -lt "1" ]; then
        HORIZONTAL_SUBDIVISIONS=$((${IMAGE_WIDTH} / ${MIN_TILE_WIDTH}))
      fi

      if [ "$(convert "${FILENAME}" -alpha off -format "%[k]" info:)" -gt "1" ]; then
        mkdir -p "${HR_OUTPUT_DIR}/${CATEGORY}/rgb"
        mkdir -p "${LR_OUTPUT_DIR}/${CATEGORY}/rgb"
        echo ${FILENAME}, rgb \(${IMAGE_WIDTH}x${IMAGE_HEIGHT} divided by ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}\) ${CATEGORY}
        wait_for_jobs
        convert "${FILENAME}" -alpha off -crop ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}@ +repage +adjoin -define png:color-type=2 -interpolate ${HR_INTERPOLATE} -filter ${HR_FILTER} -resize ${HR_SCALE} "${HR_OUTPUT_DIR}/${CATEGORY}/rgb/${DIRNAME_HASH}_${BASENAME_NO_EXT}_%03d.png" &
        wait_for_jobs
        convert "${FILENAME}" -alpha off -crop ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}@ +repage +adjoin -define png:color-type=2 -interpolate ${LR_INTERPOLATE} -filter ${LR_FILTER} -resize ${LR_SCALE} "${LR_OUTPUT_DIR}/${CATEGORY}/rgb/${DIRNAME_HASH}_${BASENAME_NO_EXT}_%03d.png" &
      else
        echo ${FILENAME}, rgb single color, skipped
      fi
      if [ "${IMAGE_CHANNELS}" == "rgba" ] || [ "${IMAGE_CHANNELS}" == "srgba" ]; then
        if [ "$(convert "${FILENAME}" -alpha extract -format "%[k]" info:)" -gt "1" ]; then
          mkdir -p "${HR_OUTPUT_DIR}/${CATEGORY}/alpha"
          mkdir -p "${LR_OUTPUT_DIR}/${CATEGORY}/alpha"
          echo ${FILENAME}, alpha \(${IMAGE_WIDTH}x${IMAGE_HEIGHT} divided by ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}\) ${CATEGORY}
          wait_for_jobs
          convert "${FILENAME}" -alpha extract -crop ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}@ +repage +adjoin -define png:color-type=2 -interpolate ${HR_INTERPOLATE} -filter ${HR_FILTER} -resize ${HR_SCALE} "${HR_OUTPUT_DIR}/${CATEGORY}/alpha/${DIRNAME_HASH}_${BASENAME_NO_EXT}_alpha_%03d.png" &
          wait_for_jobs
          convert "${FILENAME}" -alpha extract -crop ${HORIZONTAL_SUBDIVISIONS}x${VERTICAL_SUBDIVISIONS}@ +repage +adjoin -define png:color-type=2 -interpolate ${LR_INTERPOLATE} -filter ${LR_FILTER} -resize ${LR_SCALE} "${LR_OUTPUT_DIR}/${CATEGORY}/alpha/${DIRNAME_HASH}_${BASENAME_NO_EXT}_alpha_%03d.png" &
        else
          echo ${FILENAME}, alpha single color, skipped
        fi
      fi

    else
      echo ${FILENAME} too small \(${IMAGE_WIDTH}x${IMAGE_HEIGHT}\), skipped
    fi

  else
    echo ${FILENAME}, already processed, skipped
  fi
  
done < <(find "${INPUT_DIR}" \( -iname "*.dds" -or -iname "*.png"  \))

wait_for_jobs
wait

echo "finished"
