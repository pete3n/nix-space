# Local inference tooling for aichat: TTS, document reading, transcription.
#
# Split from aichat.nix because these need a local model server.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.nixSpace.programs.aichat.local;

  piperModel = "${cfg.modelDir}/piper/${cfg.piperVoice}.onnx";
  whisperModel = "${cfg.modelDir}/whisper/${cfg.whisperModel}.bin";

  whisperPackage = pkgs.whisper-cpp-vulkan;

  # Shared by ai-speak and ai-read. PIPER_MODEL and AUDIO_PLAYER can both be
  # overridden from the environment for a one-off voice or output.
  ttsHeader = # sh
    ''
      AUDIO_PLAYER=''${AUDIO_PLAYER:-${lib.escapeShellArg cfg.audioPlayer}}
      PIPER_MODEL="''${PIPER_MODEL:-${piperModel}}"
    '';

  modelsFetch = pkgs.writeShellApplication {
    name = "ai-models-fetch";
    runtimeInputs = with pkgs; [
      coreutils
      curl
    ];

    text = # sh
    ''
      PIPER_BASE_URL="${cfg.piperBaseUrl}"
      PIPER_DIR="${cfg.modelDir}/piper"
      PIPER_VOICE="${cfg.piperVoice}"
      WHISPER_BASE_URL="${cfg.whisperBaseUrl}"
      WHISPER_DIR="${cfg.modelDir}/whisper"
      WHISPER_MODEL="${cfg.whisperModel}"
    ''
    + builtins.readFile ./ai-models-fetch.sh;
  };

  aiSpeak = pkgs.writeShellApplication {
    name = "ai-speak";
    runtimeInputs = with pkgs; [
      coreutils
      piper-tts
    ];
    text = ttsHeader + builtins.readFile ./ai-speak.sh;
  };

  aiRead = pkgs.writeShellApplication {
    name = "ai-read";
    runtimeInputs = with pkgs; [
      coreutils
      file
      gawk
      pandoc
      piper-tts
      poppler-utils
    ];
    text = ttsHeader + builtins.readFile ./ai-read.sh;
  };

  aiTranscribe = pkgs.writeShellApplication {
    name = "ai-transcribe";
    runtimeInputs = [ whisperPackage ];

    text = # sh
    ''
      TRANSCRIBE_LANGUAGE="${cfg.transcribeLanguage}"
      WHISPER_MODEL="''${WHISPER_MODEL:-${whisperModel}}"
    ''
    + builtins.readFile ./ai-transcribe.sh;
  };
in
{
  options.nixSpace.programs.aichat.local = {
    enable = mkEnableOption "local inference tooling (TTS, transcription, document reading)";

    modelDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share";
      description = ''
        Base directory for downloaded models. Piper voices land under
        <modelDir>/piper, whisper models under <modelDir>/whisper.

        Not managed by home-manager: these are multi-GB binaries that do not
        belong in the Nix store, and nothing here creates or populates the
        directory. Run ai-models-fetch.
      '';
    };

    piperVoice = mkOption {
      type = types.str;
      default = "en_US-amy-medium";
      description = ''
        Piper voice name, of the form <lang>_<REGION>-<name>-<quality>. The
        parts are used to build the download path under piperBaseUrl.
      '';
    };

    whisperModel = mkOption {
      type = types.str;
      default = "ggml-medium.en";
      example = "ggml-small.en";
      description = ''
        Whisper model name. medium.en is roughly 1.5 GB; small.en is about
        0.5 GB and noticeably faster on CPU.
      '';
    };

    audioPlayer = mkOption {
      type = types.str;
      default = "${pkgs.pulseaudio}/bin/paplay --raw --rate=22050 --format=s16le --channels=1";
      description = ''
        Command consuming raw 22.05 kHz mono s16le on stdin.

        An option because the player is platform-dependent: paplay needs
        PulseAudio or a PipeWire compatibility layer, and macOS has neither.
      '';
    };

    transcribeLanguage = mkOption {
      type = types.str;
      default = "en";
      description = "Default language passed to whisper.";
    };

    piperBaseUrl = mkOption {
      type = types.str;
      default = "https://huggingface.co/rhasspy/piper-voices/resolve/main";
      description = ''
        Root of the piper-voices tree. Voices are fetched from
        <piperBaseUrl>/<lang>/<lang>_<REGION>/<name>/<quality>/<voice>.onnx.
      '';
    };

    whisperBaseUrl = mkOption {
      type = types.str;
      default = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main";
      description = "Base URL for whisper model downloads.";
    };
  };

  config = mkIf (config.nixSpace.programs.aichat.enable && cfg.enable) {
    home.packages = [
      pkgs.piper-tts
      pkgs.poppler-utils # pdftotext, for PDF reading and RAG
      pkgs.pandoc # docx/doc conversion
      whisperPackage
      modelsFetch
      aiSpeak
      aiRead
      aiTranscribe
    ];
  };
}
