#!/bin/bash

nvidia-smi

# Runtime Parameters
MODEL_NAME=""
DATA_DIR=""
MODEL_DIR=""

# Default Argument Values
NVIDIA_TF32_OVERRIDE=""

BATCH_SIZE=8
MAX_WORKSPACE_SIZE=$((2 ** (32 + 1)))  # + 1 necessary compared to python
INPUT_SIZE=640

BYPASS_ARGUMENTS=""

# Loop through arguments and process them
for arg in "$@"
do
    case $arg in
        --model_name=*)
        MODEL_NAME="${arg#*=}"
        shift # Remove --model_name from processing
        ;;
        --no_tf32)
        NVIDIA_TF32_OVERRIDE="NVIDIA_TF32_OVERRIDE=0"
        shift # Remove --no_tf32 from processing
        ;;
        --batch_size=*)
        BATCH_SIZE="${arg#*=}"
        shift # Remove --batch_size= from processing
        ;;
        --data_dir=*)
        DATA_DIR="${arg#*=}"
        shift # Remove --data_dir= from processing
        ;;
        --input_saved_model_dir=*)
        MODEL_DIR="${arg#*=}"
        shift # Remove --input_saved_model_dir= from processing
        ;;
        *)
        BYPASS_ARGUMENTS=" ${BYPASS_ARGUMENTS} ${arg}"
        ;;
    esac
done

# ============== Set model specific parameters ============= #

case ${MODEL_NAME} in
  "faster_rcnn_resnet50_coco" | "ssd_mobilenet_v1_fpn_coco")
    MAX_WORKSPACE_SIZE=$((2 ** (24 + 1)))  # + 1 necessary compared to python
    ;;
esac

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% #

echo -e "\n********************************************************************"
echo "[*] MODEL_NAME: ${MODEL_NAME}"
echo ""
echo "[*] DATA_DIR: ${DATA_DIR}"
echo "[*] MODEL_DIR: ${MODEL_DIR}"
echo ""
echo "[*] NVIDIA_TF32_OVERRIDE: ${NVIDIA_TF32_OVERRIDE}"
echo ""
# Custom Object Detection Task Flags
echo "[*] BATCH_SIZE: ${BATCH_SIZE}"
echo "[*] INPUT_SIZE: ${INPUT_SIZE}"
echo "[*] MAX_WORKSPACE_SIZE: ${MAX_WORKSPACE_SIZE}"
echo ""
echo "[*] BYPASS_ARGUMENTS: $(echo \"${BYPASS_ARGUMENTS}\" | tr -s ' ')"
echo -e "********************************************************************\n"

# ======================= ARGUMENT VALIDATION ======================= #

# Dataset Directory

if [[ -z ${DATA_DIR} ]]; then
    echo "ERROR: \`--data_dir=/path/to/directory\` is missing."
    exit 1
fi

if [[ ! -d ${DATA_DIR} ]]; then
    echo "ERROR: \`--data_dir=/path/to/directory\` does not exist. [Received: \`${DATA_DIR}\`]"
    exit 1
fi

VAL_DATA_DIR=${DATA_DIR}/val2017
ANNOTATIONS_DATA_FILE=${DATA_DIR}/annotations/instances_val2017.json

if [[ ! -d ${VAL_DATA_DIR} ]]; then
    echo "ERROR: the directory \`${VAL_DATA_DIR}\` does not exist."
    exit 1
fi

if [[ ! -f ${ANNOTATIONS_DATA_FILE} ]]; then
    echo "ERROR: the file \`${ANNOTATIONS_DATA_FILE}\` does not exist."
    exit 1
fi

# ----------------------  Model Directory --------------

if [[ -z ${MODEL_DIR} ]]; then
    echo "ERROR: \`--input_saved_model_dir=/path/to/directory\` is missing."
    exit 1
fi

if [[ ! -d ${MODEL_DIR} ]]; then
    echo "ERROR: \`--input_saved_model_dir=/path/to/directory\` does not exist. [Received: \`${MODEL_DIR}\`]"
    exit 1
fi

INPUT_SAVED_MODEL_DIR=${MODEL_DIR}/${MODEL_NAME}_640_bs${BATCH_SIZE}

if [[ ! -d ${INPUT_SAVED_MODEL_DIR} ]]; then
    echo "ERROR: the directory \`${INPUT_SAVED_MODEL_DIR}\` does not exist."
    exit 1
fi

# %%%%%%%%%%%%%%%%%%%%%%% ARGUMENT VALIDATION %%%%%%%%%%%%%%%%%%%%%%% #

BENCH_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd )"
cd ${BENCH_DIR}

# Step 1: Installing dependencies if needed:
python -c "from pycocotools.coco import COCO" > /dev/null 2>&1
DEPENDENCIES_STATUS=$?

if [[ ${DEPENDENCIES_STATUS} != 0 ]]; then
    bash install_dependencies.sh
fi

# Step 2: Execute the example

PREPEND_COMMAND="TF_XLA_FLAGS=--tf_xla_auto_jit=2 TF_CPP_MIN_LOG_LEVEL=2 ${NVIDIA_TF32_OVERRIDE}"

COMMAND="${PREPEND_COMMAND} python object_detection.py \
    --data_dir ${VAL_DATA_DIR} \
    --calib_data_dir ${VAL_DATA_DIR} \
    --annotation_path ${ANNOTATIONS_DATA_FILE} \
    --input_saved_model_dir ${INPUT_SAVED_MODEL_DIR} \
    --output_saved_model_dir /tmp/$RANDOM \
    --batch_size ${BATCH_SIZE} \
    --input_size ${INPUT_SIZE} \
    --max_workspace_size ${MAX_WORKSPACE_SIZE} \
    ${BYPASS_ARGUMENTS}"

COMMAND=$(echo "${COMMAND}" | tr -s " ")

echo -e "**Executing:**\n\n${COMMAND}\n"
sleep 5

eval ${COMMAND}
