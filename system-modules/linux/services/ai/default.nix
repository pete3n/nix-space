# Directory hook for local AI modules.
{ ... }:
{
  imports = [
		./llama-reranker
    ./ollama
    ./open-webui
  ];
}
