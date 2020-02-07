#!/bin/bash
if [[ -v GATE_COLOR && ${GATE_COLOR} = "1" ]]; then
    C_CLEAR="\e[0m"
    C_ERROR="\e[38;5;160m"
    C_HEADER="\e[38;5;164m"
    C_HILIGHT="\e[38;5;27m"
    C_MUTE="\e[38;5;238m"
    C_SUCCESS="\e[38;5;46m"
    C_TEMP="\e[38;5;226m"
else
    C_CLEAR=""
    C_ERROR=""
    C_HEADER=""
    C_HILIGHT=""
    C_MUTE=""
    C_SUCCESS=""
    C_TEMP=""
fi

log() {
    d=$(date --utc)
    echo -e "${C_MUTE}${d}${C_CLEAR} ${*}" 1>&2
    echo -e "${d} ${*}" >> "${LOG_FILE}"
}

log_warn() {
    d=$(date --utc)
    echo -e "${C_MUTE}${d}${C_CLEAR} ${C_HILIGHT}WARN${C_CLEAR} ${*}" 1>&2
    echo -e "${d} ${*}" >> "${LOG_FILE}"
}

log_error() {
    d=$(date --utc)
    echo -e "${C_MUTE}${d}${C_CLEAR} ${C_ERROR}ERROR${C_CLEAR} ${*}" 1>&2
    echo -e "${d} ${*}" >> "${LOG_FILE}"
}


log_stage_diagnostic_header() {
            echo -e "  ${C_ERROR}= Diagnostic Report =${C_CLEAR}"
}

log_color_reset() {
    echo -e "${C_CLEAR}"
}

log_huge_success() {
    echo -e "${C_SUCCESS}=== HUGE SUCCESS ===${C_CLEAR}"
}

log_note() {
    echo -e "${C_HILIGHT}NOTE:${C_CLEAR} ${*}"
}

log_stage_error() {
    NAME=${1}
    echo -e " ${C_ERROR}== Error in stage ${C_HILIGHT}${NAME}${C_ERROR} ( ${C_TEMP}${LOG_FILE}${C_ERROR} ) ==${C_CLEAR}"
}

log_stage_footer() {
    NAME=${1}
    echo -e "${C_HEADER}=== Finished stage ${C_HILIGHT}${NAME}${C_HEADER} ===${C_CLEAR}"
}

log_stage_header() {
    NAME=${1}
    echo -e "${C_HEADER}=== Executing stage ${C_HILIGHT}${NAME}${C_HEADER} ===${C_CLEAR}"
}

log_stage_success() {
    echo -e " ${C_SUCCESS}== Stage Success ==${C_CLEAR}"
}

log_temp_dir() {
    echo -e "Working in ${C_TEMP}${TEMP_DIR}${C_CLEAR}"
}

if [[ -v GATE_DEBUG && ${GATE_DEBUG} = "1" ]]; then
    export LOG_FILE=/dev/stderr
elif [[ -v TEMP_DIR ]]; then
    export LOG_FILE=${TEMP_DIR}/gate.log
else
    export LOG_FILE=/dev/null
fi
