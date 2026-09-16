#!/usr/bin/env bash
#
# Written by Joseph Cameron
# https://github.com/jfcameron/transcribe
#
set -euo pipefail

FORCE_WHISPER=0
LANGUAGE="en"
OUTPUT_DIR="."
OUTPUT_FORMAT="vtt"
WHISPER_MODEL="${WHISPER_MODEL:-$HOME/.local/share/whisper/ggml-base.bin}"

DESCRIPTION="$(cat <<EOF
Usage: $(basename "$0") [OPTIONS] INPUT

Download or transcribe captions for a video.
INPUT may be a streaming URL (specific platforms depend on yt-dlp), a remote file (specific protocols depend on yt-dlp) or a local file.

For streaming URLs the script will try to download captions provided by the video service itself,
but fall back to transcribing locally via whisper if none are available. Plain files go straight to whisper transcription.

Options:
 -l LANG     Subtitle language code (ISO 639-1) (default: $LANGUAGE)
 -m MODEL    Path to whisper ggml model file
           (default: $WHISPER_MODEL or ~/.local/share/whisper/ggml-base.bin)
 -f FORMAT   Output format: vtt, srt, txt (default: $OUTPUT_FORMAT)
 -o DIR      Output directory (default: $OUTPUT_DIR)
 -w          Force whisper transcription, skipping caption download attempts.
 -h, --help Print this help statement

Output is named after the video ID for streaming URLs (e.g. dQw4w9WgXcQ.en.vtt),
or the input basename for plain files (e.g. myvideo.en.vtt).
EOF
)"

# =============================================================================================
# Functions
# =============================================================================================
error() { echo -e "\033[1;31mError:\033[0m $*" >&2; exit 1; }

info() { echo -e "\033[1;33mInfo:\033[0m $*"; }

success() { echo -e "\033[1;32mSuccess:\033[0m $*" >&2; exit 0; }   

requires() {
    if ! command -v "$1" &>/dev/null; then
        error "'$1' is not installed or not in PATH."
    fi
}

run_whisper() {
    local audio_file="$1"
    [[ -f "$WHISPER_MODEL" ]] || error "whisper model not found: $WHISPER_MODEL (set -m or \$WHISPER_MODEL)"
    info "Transcribing with whisper..."
    local whisper_out="$WORK_DIR/transcription"
    case "$OUTPUT_FORMAT" in
        srt) local format_flag="--output-srt" ;;
        txt) local format_flag="--output-txt" ;;
        vtt) local format_flag="--output-vtt" ;;
        *)   error "unsupported output format for whisper: $OUTPUT_FORMAT (use vtt, srt, or txt)" ;;
    esac
    whisper-cli \
        -m "$WHISPER_MODEL" \
        -f "$audio_file" \
        --language "$LANGUAGE" \
        "$format_flag" \
        --output-file "$whisper_out" \
        || error "whisper-cli failed"
    local whisper_result="$whisper_out.$OUTPUT_FORMAT"
    [[ -f "$whisper_result" ]] || error "whisper output not found (expected $whisper_result)"
    mv "$whisper_result" "$OUTPUT_FILE"
    success "Transcript written to \`$OUTPUT_FILE\`"
}

find_sub() {
    local found
    found="$(find "$WORK_DIR" -maxdepth 1 -name "*.$LANGUAGE.*" | head -1)"
    echo "$found"
}

# =============================================================================================
# Main
# =============================================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) OUTPUT_FORMAT="$2"; shift 2 ;;
        -h|--help) info "${DESCRIPTION}"; exit 0 ;;
        -l) LANGUAGE="$2"; shift 2 ;;
        -m) WHISPER_MODEL="$2"; shift 2 ;;
        -o) OUTPUT_DIR="$2"; shift 2 ;;
        -w) FORCE_WHISPER=1; shift ;;
        -*) error "unknown option: $1" ;;
        *) break ;;
    esac
done

[[ $# -lt 1 ]] && { echo "${DESCRIPTION}"; exit 1; }
INPUT="$1"

requires ffmpeg
requires whisper-cli
requires yt-dlp

WORK_DIR="$(mktemp -d)"
trap '[[ -n "$WORK_DIR" ]] && rm -rf "$WORK_DIR"' EXIT

mkdir -p "$OUTPUT_DIR"

# answers 2 questions: ytdlp supports the url and what ytdlp would name the file
VIDEO_ID="$(yt-dlp --print id --no-warnings "$INPUT" 2>/dev/null)" || true

if [[ -n "$VIDEO_ID" ]]; then
    OUTPUT_FILE="$OUTPUT_DIR/$VIDEO_ID.$LANGUAGE.$OUTPUT_FORMAT"

    if [[ $FORCE_WHISPER -eq 0 ]]; then
        info "Trying manual captions..."
        yt-dlp \
            --skip-download \
            --write-subs \
            --sub-langs "$LANGUAGE" \
            --sub-format "$OUTPUT_FORMAT/best" \
            --no-warnings \
            -o "$WORK_DIR/%(id)s" \
            "$INPUT" 2>/dev/null || true

        SUB_FILE="$(find_sub)"
        if [[ -n "$SUB_FILE" ]]; then
            info "Found manual captions."
            mv "$SUB_FILE" "$OUTPUT_FILE"
            success "Transcript copied to \`$OUTPUT_FILE\`"
        fi

        info "No manual captions. Trying automatic captions..."
        yt-dlp \
            --skip-download \
            --write-auto-subs \
            --sub-langs "$LANGUAGE" \
            --sub-format "$OUTPUT_FORMAT/best" \
            --no-warnings \
            -o "$WORK_DIR/%(id)s" \
            "$INPUT" 2>/dev/null || true

        SUB_FILE="$(find_sub)"
        if [[ -n "$SUB_FILE" ]]; then
            info "Found automatic captions."
            mv "$SUB_FILE" "$OUTPUT_FILE"
            success "Transcript copied to \`$OUTPUT_FILE\`"
        fi

        info "No captions available..."
    fi

    AUDIO_FILE="$WORK_DIR/audio.mp3"
    info "Downloading audio..."
    yt-dlp -x --audio-format mp3 --no-warnings -o "$AUDIO_FILE" "$INPUT" \
        || error "failed to download audio"
    run_whisper "$AUDIO_FILE"
fi

INPUT_BASE="$(basename "$INPUT")"
INPUT_STEM="${INPUT_BASE%.*}"
OUTPUT_FILE="$OUTPUT_DIR/$INPUT_STEM.$LANGUAGE.$OUTPUT_FORMAT"

if [[ -f "$INPUT" ]]; then
    info "Local file detected..."
    AUDIO_FILE="$WORK_DIR/audio.mp3"
    ffmpeg -i "$INPUT" -vn -q:a 2 "$AUDIO_FILE"        
    run_whisper "$AUDIO_FILE"
else
    info "Remote file detected..."
    AUDIO_FILE="$WORK_DIR/audio.mp3"
    yt-dlp -x --audio-format mp3 --no-warnings -o "$AUDIO_FILE" "$INPUT" \
        || error "failed to download - URL does not point to a video file"
    run_whisper "$AUDIO_FILE"
fi

error "source type is unrecognized."

