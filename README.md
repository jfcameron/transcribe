# transcribe
uses yt-dlp and whisper-cli to produce a transcript for audio/video streams and files

    Usage: transcribe.sh [OPTIONS] INPUT

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

