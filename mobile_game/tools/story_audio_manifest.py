#!/usr/bin/env python3
"""Build the narration/music plan from the exact story text shown by the game.

This tool creates a JSON plan only. It neither calls a speech/music provider nor
changes the authored story. Run it from any directory with Python 3.10+:

    python tools/story_audio_manifest.py
    python tools/story_audio_manifest.py --check --list
    python tools/story_audio_manifest.py --check --validate-assets

The last command is intended for use after the audio files have been generated.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


PROJECT = Path(__file__).resolve().parents[1]
CHAPTERS_PATH = Path("data/chapters.json")
GAME_PATH = Path("scripts/game_main.gd")
OUTPUT_PATH = Path("data/audio_v13.json")
AUDIO_ROOT = "res://assets/audio_v13"

# Each arrangement has its own identity while leaving room for Chinese speech.
# These are generation prompts, not claims that a recording already exists.
MUSIC_BRIEFS = [
    {
        "mood": "亲切、明亮、第一次结伴冒险的期待",
        "instruments": ["木吉他", "柔和木琴", "轻拨弦乐", "竹笛"],
        "bpm": 92,
        "prompt": "温暖童话冒险的村庄配乐。木吉他与木琴交替奏出轻巧旋律，竹笛回应，柔和弦乐托底。轻快但不催促，像孩子们在清晨院落结识一位新朋友。自然有呼吸，避免尖锐高音和密集鼓点。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "幽静、神秘、萤火引路中的温暖",
        "instruments": ["竖琴泛音", "气声长笛", "钟琴", "低音弦乐"],
        "bpm": 80,
        "prompt": "夜间萤火森林的童话探索配乐。稀疏竖琴泛音与柔软气声长笛，远处少量钟琴像萤火闪烁，低弦保持安静的神秘感。旋律带一点寻找同伴的希望，避免恐怖音效和突发惊吓。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "开阔、轻盈、风车重新转动的希望",
        "instruments": ["曼陀铃", "木管", "拨弦大提琴", "轻手鼓"],
        "bpm": 108,
        "prompt": "辽阔风车原野的自然冒险配乐。曼陀铃轻盈分解和弦与木管宽阔旋律交织，拨弦大提琴和很轻的手鼓形成风车转动般的节拍。明亮、有向前旅行的动感，同时保留平静田野的空气感。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "流动、澄澈、月光水面下的一丝谜意",
        "instruments": ["马林巴", "柔和钢琴", "箫", "细腻弦乐"],
        "bpm": 84,
        "prompt": "月光水乡的流动探索配乐。马林巴与柔和钢琴形成舒展波纹，箫吹出清澈克制的旋律，弦乐像水面倒影。带一点真假回声的谜意，最终仍然安心温柔。避免真实流水声掩盖提示音。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "古老、庄重、发现父亲往事的敬意",
        "instruments": ["钢片琴", "低音木管", "低弦", "稀疏金属钟音"],
        "bpm": 80,
        "prompt": "旧王遗迹的古老星图探索配乐。钢片琴与低音木管缓缓问答，低弦保持宽广空间，稀疏柔和金属钟音提示记忆苏醒。庄重而不阴森，情绪是理解父亲与朋友共同守护人间的历史。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "紧迫、坚定、伙伴互相回应的勇气",
        "instruments": ["短弓弦乐", "低鼓", "圆号", "清亮木管"],
        "bpm": 116,
        "prompt": "村庄星脉裂隙的守护冒险配乐。短弓弦乐与低鼓构成稳定紧迫节奏，温暖圆号给出坚定旋律，清亮木管回应此前村庄的希望。有救援与守护的力量，避免凶暴轰鸣或连续高潮，留出敌人预警的声音空间。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
    {
        "mood": "辽远、温柔、带着思念接过守护之灯",
        "instruments": ["钢琴", "竖琴", "温暖弦乐", "清亮钟琴"],
        "bpm": 80,
        "prompt": "星灯岛与冒险尾声的温柔配乐。钢琴和竖琴留白对话，温暖弦乐缓慢展开，极少量钟琴像星海中亮起的灯。既有想念父亲的细腻情绪，也有朋友相伴与成长的安定希望。悲伤克制，结尾落在明亮和弦。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环，为中文旁白保留空间。",
    },
]


def text_hash(text: str) -> str:
    """Hash the UTF-8 spoken text, including punctuation and paragraph breaks."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def closing_line(game_source: str) -> str:
    """Extract only the narrative suffix of the current final-clear dialog.

    GDScript's quoted literal here uses the JSON-compatible escape subset. A
    source change outside _complete_stage cannot accidentally supply the line.
    Failure is deliberate: a changed dialog must be reviewed rather than silently
    producing a recording which no longer matches the screen.
    """
    function = re.search(
        r"(?ms)^func _complete_stage\([^\n]*\n(.*?)(?=^func |\Z)", game_source
    )
    if function is None:
        raise ValueError("Cannot find game_main.gd::_complete_stage().")
    suffixes = re.findall(
        r'body\s*\+\s*("(?:[^"\\]|\\.)*")', function.group(1)
    )
    # Audio integration names the same suffix instead of inlining it in body.
    suffixes += re.findall(
        r'var\s+closing\s*=\s*("(?:[^"\\]|\\.)*")', function.group(1)
    )
    candidates = []
    for quoted in suffixes:
        value = json.loads(quoted)
        normalized = value.removeprefix("\n\n")
        if normalized.startswith("七章冒险已完成。"):
            candidates.append(normalized)
    if len(candidates) != 1:
        raise ValueError("Expected exactly one final-dialog narrative closing line.")
    return candidates[0]


def story_entry(
    story_id: str,
    title: str,
    text: str,
    kind: str,
    chapter_index: int,
    sources: list[str],
    **extra: Any,
) -> dict[str, Any]:
    if not text or text != text.strip():
        raise ValueError(f"{story_id}: story text is empty or has outer whitespace.")
    # Rewards and live instructions are appended separately by the game UI.
    if "经验 +" in text or "本次实战目标：" in text or "妖怪命中至少扣除" in text:
        raise ValueError(f"{story_id}: non-narrative UI text entered the recording.")
    return {
        "id": story_id,
        "kind": kind,
        "title": title,
        "chapter_index": chapter_index,
        **extra,
        "text": text,
        "path": f"{AUDIO_ROOT}/voice/{story_id}.mp3",
        "text_sha256": text_hash(text),
        "character_count": len(text),
        "estimated_duration_seconds": round(len(re.sub(r"\s", "", text)) / 4.2 + 0.8, 1),
        "sources": sources,
    }


def build_manifest(project: Path) -> dict[str, Any]:
    authored = json.loads((project / CHAPTERS_PATH).read_text(encoding="utf-8-sig"))
    chapters = authored["chapters"]
    if len(chapters) != 7 or any(len(c.get("levels", [])) != 3 for c in chapters):
        raise ValueError("Expected 7 chapters with 3 levels each, matching campaign.stage_data().")
    conclusion = closing_line((project / GAME_PATH).read_text(encoding="utf-8-sig"))
    stories: dict[str, dict[str, Any]] = {}
    regions = []
    stage_index = 0
    for chapter_index, chapter in enumerate(chapters):
        pointer = f"res://data/chapters.json#/chapters/{chapter_index}"
        intro_id = f"intro_{chapter_index}"
        stories[intro_id] = story_entry(
            intro_id, str(chapter["title"]), str(chapter["summary"]), "chapter_intro",
            chapter_index, [f"{pointer}/summary"], chapter_id=str(chapter["id"]),
            stage_index=stage_index,
        )
        brief = MUSIC_BRIEFS[chapter_index]
        regions.append({
            "id": f"chapter_{chapter_index}",
            "chapter_index": chapter_index,
            "chapter_id": str(chapter["id"]),
            "name": str(chapter["region"]),
            "path": f"{AUDIO_ROOT}/music/region_{chapter_index}.mp3",
            "gain": 0.6,
            **brief,
            "loop": True,
            "bars": 32,
            "target_duration_seconds": round(32 * 4 * 60 / brief["bpm"], 3),
        })
        # Same chapter-order/level-order flattening used by Campaign._init().
        for level_index, level in enumerate(chapter["levels"]):
            is_ending = stage_index == 20
            story_id = "ending" if is_ending else f"clear_{stage_index}"
            text = str(level["success"])
            sources = [f"{pointer}/levels/{level_index}/success"]
            if is_ending:
                text += "\n\n" + conclusion
                sources.append("res://scripts/game_main.gd#_complete_stage/final_dialog_closing")
            stories[story_id] = story_entry(
                story_id, str(level["name"]), text,
                "ending" if is_ending else "stage_clear", chapter_index, sources,
                chapter_id=str(chapter["id"]), stage_index=stage_index,
                level_index=level_index, level_id=str(level["id"]),
            )
            stage_index += 1

    # Direct lookup works for every stage index without producing duplicate TTS.
    stories["clear_20"] = {
        **stories["ending"],
        "id": "clear_20",
        "alias_of": "ending",
    }
    unique = [entry for entry in stories.values() if "alias_of" not in entry]
    expected = {*(f"intro_{i}" for i in range(7)), *(f"clear_{i}" for i in range(21)), "ending"}
    if stories.keys() != expected or len(unique) != 28:
        raise ValueError("Narration coverage differs from 7 intros + 21 clears (ending shared).")

    return {
        "version": 1,
        "language": "zh-CN",
        "generated_by": "res://tools/story_audio_manifest.py",
        "source_policy": "与章节简介、通关故事及最终对话结尾逐字一致；不朗读奖励、经验、操作提示或实战目标；不改写原故事。",
        "asset_policy": "音频随游戏离线打包；独立录音与全部音乐已生成，制作参数及文件校验见各音频目录 production/score_manifest 记录。带 alias_of 的条目复用同一录音。",
        "voice": {
            "role": "narrator",
            "style": "温暖、自然、清晰的中文童话旁白，情绪克制，人物名保持一致；不添加原文没有的台词。",
            "rate": 1.0,
            "pronunciation": {"旺仔": "wàng zǎi", "小馒头": "xiǎo mán tou", "小龙": "xiǎo lóng", "星契": "xīng qì", "埙": "xūn"},
        },
        "music": {
            "contexts": {
                "title": {
                    "id": "title", "name": "星灯岛 · 约定之光",
                    "path": f"{AUDIO_ROOT}/music/title.mp3", "gain": 0.6,
                    "mood": "温暖、奇幻、星海中相遇与启程的期待",
                    "instruments": ["钢琴", "竖琴", "木管", "柔和弦乐"],
                    "bpm": 84,
                    "prompt": "温暖奇幻冒险游戏的标题配乐。钢琴奏出容易记住的简短星光主题，竖琴点缀，木管与柔和弦乐逐渐加入。像夜空下一盏灯邀请朋友启程，明亮、亲切、有一点辽远的星海感。纯器乐，无人声，无歌词，无突然音量变化，首尾可平滑循环。",
                    "loop": True, "bars": 32, "target_duration_seconds": round(32 * 4 * 60 / 84, 3),
                },
                "battle": {
                    "id": "battle", "name": "伙伴并肩",
                    "path": f"{AUDIO_ROOT}/music/battle.mp3", "gain": 0.7,
                    "mood": "灵动、警觉、有节奏的伙伴战斗",
                    "instruments": ["拨弦弦乐", "木管", "低鼓", "轻打击乐"],
                    "bpm": 120,
                    "prompt": "伙伴并肩战斗的原创管弦乐。拨弦弦乐与轻打击乐保持清晰节拍，木管奏出勇敢简洁的动机，低鼓克制有力。紧张但不压迫，给战斗预警和中文旁白留出空间。纯器乐，无人声，无歌词，首尾可平滑循环。",
                    "loop": True, "bars": 32, "target_duration_seconds": 64,
                },
                "boss": {
                    "id": "boss", "name": "守灯之战",
                    "path": f"{AUDIO_ROOT}/music/boss.mp3", "gain": 0.7,
                    "mood": "庄严、紧张、守护星灯的决心",
                    "instruments": ["圆号", "短弓弦乐", "低弦", "定音鼓"],
                    "bpm": 112,
                    "prompt": "守护星灯的首领战原创管弦乐。圆号提出有分量的主题，低弦与短弓弦乐形成推进，定音鼓标记段落。戏剧性充足但避免噪声和刺耳铜管，不覆盖敌人预警。纯器乐，无人声，无歌词，首尾可平滑循环。",
                    "loop": True, "bars": 32, "target_duration_seconds": round(32 * 4 * 60 / 112, 3),
                },
            },
            "regions": regions,
            "ending_region_id": "chapter_6",
        },
        "stories": stories,
        "mix": {
            "master_db": 0.0,
            "music_db": -15.0,
            "voice_db": -2.0,
            "effects_db": -4.0,
            "music_duck_db": -10.0,
            "duck_attack_seconds": 0.18,
            "duck_release_seconds": 0.65,
            "music_crossfade_seconds": 1.5,
            "voice_fade_seconds": 0.12,
            "voice_bus": "Voice",
            "music_bus": "Music",
            "effects_bus": "SFX",
            "pause_with_game": True,
            "one_voice_at_a_time": True,
        },
        "coverage": {
            "chapter_intro_count": 7,
            "stage_clear_count": 21,
            "unique_voice_file_count": len(unique),
            "story_entry_count": len(stories),
            "music_file_count": len(regions) + 3,
            "unique_voice_character_count": sum(len(e["text"]) for e in unique),
            "unique_voice_han_character_count": sum(len(re.findall(r"[\u3400-\u9fff]", e["text"])) for e in unique),
            "estimated_voice_seconds": round(sum(e["estimated_duration_seconds"] for e in unique), 1),
        },
    }


def planned_audio(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    music = manifest["music"]
    return [*music["contexts"].values(), *music["regions"], *(
        story for story in manifest["stories"].values() if "alias_of" not in story
    )]


def validate_assets(project: Path, manifest: dict[str, Any]) -> list[str]:
    missing = []
    for entry in planned_audio(manifest):
        relative = Path(entry["path"].removeprefix("res://"))
        asset = project / relative
        if not asset.is_file() or asset.stat().st_size == 0:
            missing.append(relative.as_posix())
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", type=Path, default=PROJECT, help="Godot source project directory")
    parser.add_argument("--output", type=Path, help="Override output path (default: PROJECT/data/audio_v13.json)")
    parser.add_argument("--check", action="store_true", help="Check the committed manifest without writing it")
    parser.add_argument("--list", action="store_true", help="Print the exact unique narration scripts")
    parser.add_argument("--validate-assets", action="store_true", help="Fail if any planned audio file is absent or empty")
    args = parser.parse_args()
    project = args.project.resolve()
    output = args.output.resolve() if args.output else project / OUTPUT_PATH
    try:
        manifest = build_manifest(project)
        encoded = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
        if args.check:
            if not output.is_file() or output.read_text(encoding="utf-8-sig") != encoded:
                print(f"OUT OF DATE: {output}", file=sys.stderr)
                return 1
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(encoded, encoding="utf-8", newline="\n")
        coverage = manifest["coverage"]
        print(f"{'CHECKED' if args.check else 'WROTE'}: {output}")
        print(f"Voice: {coverage['unique_voice_file_count']} unique files / {coverage['story_entry_count']} entries; "
              f"{coverage['unique_voice_character_count']} characters / {coverage['unique_voice_han_character_count']} Han characters; "
              f"estimated {coverage['estimated_voice_seconds']:.1f} seconds.")
        print(f"Music: {coverage['music_file_count']} distinct tracks (title + battle + boss + 7 regions).")
        if args.list:
            for entry in manifest["stories"].values():
                if "alias_of" not in entry:
                    print(f"\n[{entry['id']}] {entry['title']}\n{entry['text']}")
            print("\n[clear_20] alias of ending; reuses ending.mp3.")
        if args.validate_assets:
            missing = validate_assets(project, manifest)
            if missing:
                print(f"MISSING AUDIO: {len(missing)} files", file=sys.stderr)
                for relative in missing:
                    print(relative, file=sys.stderr)
                return 1
            print(f"All {len(planned_audio(manifest))} planned audio files exist and are non-empty.")
        return 0
    except (OSError, KeyError, ValueError, TypeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
