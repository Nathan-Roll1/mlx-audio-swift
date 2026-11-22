"""Create a local decoder-quantized MLX copy of the pinned Fourier 2B release."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

from huggingface_hub import snapshot_download
import mlx.core as mx
from mlx_audio.convert import build_quant_predicate
from mlx_audio.lm.convert import quantize_model, save_config, save_model
from mlx_audio.stt.models.qwen3_asr import ModelConfig, Qwen3ASRModel

REPO = "oruk/oruk-fourier-2b"
REVISION = "8c2a8871f1304aa2f634da4fb95e24438c4945b9"
SOURCE_SHA256 = "e64765ffdd90c83704c0951e0d88b7f2ed84499af5c208f7ddf8d922cf08441c"
SUPPORT = ("config.json", "generation_config.json", "processor_config.json",
           "tokenizer.json", "tokenizer_config.json", "chat_template.jinja", "README.md")


def legacy_key(name):
    """Translate the HF-native parameter namespace to the original Qwen release layout."""
    if name.startswith("model.audio_tower."):
        return "thinker." + name.removeprefix("model.")
    if name.startswith("model.language_model."):
        return "thinker.model." + name.removeprefix("model.language_model.")
    if name.startswith("model.multi_modal_projector.linear_"):
        return "thinker.audio_tower.proj" + name.removeprefix("model.multi_modal_projector.linear_")
    raise ValueError(f"Unknown Fourier parameter: {name}")


def prepare(destination):
    if destination.exists():
        raise FileExistsError(f"Choose a new output directory: {destination}")
    source = Path(snapshot_download(REPO, revision=REVISION, allow_patterns=["model.safetensors", *SUPPORT]))
    weights_path = source / "model.safetensors"
    with weights_path.open("rb") as handle:
        if hashlib.file_digest(handle, "sha256").hexdigest() != SOURCE_SHA256:
            raise ValueError("Original checkpoint checksum mismatch.")
    config = json.loads((source/"config.json").read_text())
    model = Qwen3ASRModel(ModelConfig.from_dict(config))
    hf_weights = mx.load(str(weights_path))
    legacy = {legacy_key(key): value for key,value in hf_weights.items()}
    if len(legacy) != len(hf_weights):
        raise ValueError("Parameter name collision.")
    # Stock MLX Audio performs the three PyTorch-to-MLX convolution transposes here.
    model.load_weights(list(model.sanitize(legacy).items()), strict=True)
    del hf_weights, legacy
    _, config = quantize_model(model, config, 64, 4, mode="affine",
                               quant_predicate=build_quant_predicate(model))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as tmp:
        out = Path(tmp) / "model"
        out.mkdir()
        for item in SUPPORT:
            if item != "config.json":
                shutil.copyfile(source/item, out/item)
        save_model(out, model, donate_model=True)
        save_config(config, config_path=out/"config.json")
        provenance = {"source":REPO, "revision":REVISION, "sha256":SOURCE_SHA256,
                      "license":"CC BY-NC 4.0", "conversion":"MLX Audio 0.6.7, affine 4-bit eligible decoder layers, group size 64; original audio encoder precision"}
        (out/"fourier-conversion.json").write_text(json.dumps(provenance,indent=2)+"\n")
        out.rename(destination)
    print(f"Created {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output",type=Path)
    args = parser.parse_args()
    prepare(args.output.expanduser().absolute())
