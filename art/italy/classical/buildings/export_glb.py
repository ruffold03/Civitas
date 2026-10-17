#!/usr/bin/env python3
"""Low-poly classical Italian building meshes → glTF 2.0 (.glb).

Origin is the anchor-cell corner, Y-up, 1 unit = 1 cell.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent

PLASTER = (0.91, 0.84, 0.72)
STONE = (0.76, 0.72, 0.64)
GOLD_STONE = (0.78, 0.66, 0.42)
TERRACOTTA = (0.74, 0.36, 0.22)
ROOF_DARK = (0.58, 0.27, 0.17)
WOOD = (0.45, 0.30, 0.18)
DARK_WOOD = (0.28, 0.17, 0.11)
LINTEL = (0.62, 0.56, 0.48)
SHADOW = (0.22, 0.18, 0.14)


def _v(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s)


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _norm(v):
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length < 1e-9:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


class Mesh:
    def __init__(self, name: str) -> None:
        self.name = name
        self.parts: dict[tuple, dict] = {}

    def _part(self, color: tuple) -> dict:
        key = tuple(round(c, 4) for c in color[:3])
        if key not in self.parts:
            self.parts[key] = {"color": key, "positions": [], "normals": [], "indices": []}
        return self.parts[key]

    def add_tri(self, a, b, c, color) -> None:
        n = _norm(_cross(_sub(b, a), _sub(c, a)))
        part = self._part(color)
        i = len(part["positions"])
        part["positions"].extend((a, b, c))
        part["normals"].extend((n, n, n))
        part["indices"].extend((i, i + 1, i + 2))

    def add_quad(self, a, b, c, d, color) -> None:
        self.add_tri(a, b, c, color)
        self.add_tri(a, c, d, color)

    def add_box(self, cx, cy, cz, sx, sy, sz, color) -> None:
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        p = {
            "lbb": (cx - hx, cy - hy, cz - hz),
            "lbf": (cx - hx, cy - hy, cz + hz),
            "ltb": (cx - hx, cy + hy, cz - hz),
            "ltf": (cx - hx, cy + hy, cz + hz),
            "rbb": (cx + hx, cy - hy, cz - hz),
            "rbf": (cx + hx, cy - hy, cz + hz),
            "rtb": (cx + hx, cy + hy, cz - hz),
            "rtf": (cx + hx, cy + hy, cz + hz),
        }
        self.add_quad(p["rbf"], p["rbb"], p["rtb"], p["rtf"], color)
        self.add_quad(p["lbb"], p["lbf"], p["ltf"], p["ltb"], color)
        self.add_quad(p["ltf"], p["rtf"], p["rtb"], p["ltb"], color)
        self.add_quad(p["lbb"], p["rbb"], p["rbf"], p["lbf"], color)
        self.add_quad(p["lbf"], p["rbf"], p["rtf"], p["ltf"], color)
        self.add_quad(p["rbb"], p["lbb"], p["ltb"], p["rtb"], color)

    def add_gable_roof(self, x0, x1, z0, z1, y_eave, y_ridge, color, overhang=0.04) -> None:
        x0 -= overhang
        x1 += overhang
        z0 -= overhang * 0.5
        z1 += overhang * 0.5
        xm = (x0 + x1) * 0.5
        a0, r0, b0 = (x0, y_eave, z0), (xm, y_ridge, z0), (x1, y_eave, z0)
        a1, r1, b1 = (x0, y_eave, z1), (xm, y_ridge, z1), (x1, y_eave, z1)
        self.add_quad(a0, r0, r1, a1, color)
        self.add_quad(r0, b0, b1, r1, color)
        self.add_tri(a0, b0, r0, color)
        self.add_tri(b1, a1, r1, color)

    def add_pediment(self, x0, x1, z_front, z_back, y0, y1, color) -> None:
        xm = (x0 + x1) * 0.5
        f0, f1, fr = (x0, y0, z_front), (x1, y0, z_front), (xm, y1, z_front)
        b0, b1, br = (x0, y0, z_back), (x1, y0, z_back), (xm, y1, z_back)
        self.add_tri(f0, f1, fr, color)
        self.add_tri(b1, b0, br, color)
        self.add_quad(f0, fr, br, b0, color)
        self.add_quad(fr, f1, b1, br, color)


def _pad4(data: bytes, pad: bytes) -> bytes:
    extra = (4 - (len(data) % 4)) % 4
    return data + pad * extra


def write_glb(path: Path, mesh: Mesh) -> None:
    blobs: list[bytes] = []
    views: list[dict] = []
    accessors: list[dict] = []
    primitives: list[dict] = []
    materials: list[dict] = []
    offset = 0

    def push(data: bytes, target: int, stride: int | None = None) -> int:
        nonlocal offset
        if stride:
            align = (stride - (offset % stride)) % stride
            if align:
                blobs.append(b"\x00" * align)
                offset += align
        view_i = len(views)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        blobs.append(data)
        offset += len(data)
        return view_i

    for color, part in mesh.parts.items():
        mat_i = len(materials)
        materials.append(
            {
                "name": "mat_%d" % mat_i,
                "pbrMetallicRoughness": {
                    "baseColorFactor": [color[0], color[1], color[2], 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.78,
                },
            }
        )
        pos = part["positions"]
        nrm = part["normals"]
        idx = part["indices"]
        pos_bytes = b"".join(struct.pack("<fff", *v) for v in pos)
        nrm_bytes = b"".join(struct.pack("<fff", *v) for v in nrm)
        idx_bytes = b"".join(struct.pack("<H", i) for i in idx)
        pos_view = push(pos_bytes, 34962, 4)
        nrm_view = push(nrm_bytes, 34962, 4)
        idx_view = push(idx_bytes, 34963, 2)
        xs, ys, zs = zip(*pos)
        pos_acc = len(accessors)
        accessors.append(
            {
                "bufferView": pos_view,
                "componentType": 5126,
                "count": len(pos),
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            }
        )
        nrm_acc = len(accessors)
        accessors.append(
            {
                "bufferView": nrm_view,
                "componentType": 5126,
                "count": len(nrm),
                "type": "VEC3",
            }
        )
        idx_acc = len(accessors)
        accessors.append(
            {
                "bufferView": idx_view,
                "componentType": 5123,
                "count": len(idx),
                "type": "SCALAR",
            }
        )
        primitives.append(
            {
                "attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc},
                "indices": idx_acc,
                "material": mat_i,
            }
        )

    bin_chunk = _pad4(b"".join(blobs), b"\x00")
    gltf = {
        "asset": {"version": "2.0", "generator": "civitas-export_glb"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": mesh.name}],
        "meshes": [{"name": mesh.name, "primitives": primitives}],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_chunk)}],
        "materials": materials,
    }
    json_chunk = _pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    header = struct.pack("<4sII", b"glTF", 2, total)
    json_header = struct.pack("<I4s", len(json_chunk), b"JSON")
    bin_header = struct.pack("<I4s", len(bin_chunk), b"BIN\x00")
    path.write_bytes(header + json_header + json_chunk + bin_header + bin_chunk)


def build_domus() -> Mesh:
    m = Mesh("domus")
    m.add_box(0.50, 0.03, 0.50, 0.86, 0.06, 0.82, STONE)
    m.add_box(0.50, 0.25, 0.50, 0.76, 0.38, 0.70, PLASTER)
    m.add_box(0.50, 0.16, 0.86, 0.16, 0.26, 0.04, DARK_WOOD)
    m.add_box(0.28, 0.30, 0.86, 0.10, 0.10, 0.03, SHADOW)
    m.add_box(0.72, 0.30, 0.86, 0.10, 0.10, 0.03, SHADOW)
    m.add_box(0.89, 0.30, 0.50, 0.03, 0.11, 0.12, SHADOW)
    m.add_gable_roof(0.10, 0.90, 0.10, 0.90, 0.44, 0.68, TERRACOTTA)
    m.add_box(0.26, 0.64, 0.28, 0.08, 0.18, 0.08, ROOF_DARK)
    m.add_box(0.26, 0.74, 0.28, 0.10, 0.03, 0.10, STONE)
    return m


def build_town_hall() -> Mesh:
    m = Mesh("town_hall")
    m.add_box(0.50, 0.04, 0.58, 0.88, 0.08, 0.78, STONE)
    m.add_box(0.50, 0.10, 0.72, 0.70, 0.04, 0.22, LINTEL)
    m.add_box(0.50, 0.40, 0.46, 0.74, 0.56, 0.62, GOLD_STONE)
    for x in (0.22, 0.40, 0.60, 0.78):
        m.add_box(x, 0.36, 0.80, 0.07, 0.52, 0.07, PLASTER)
        m.add_box(x, 0.63, 0.80, 0.09, 0.04, 0.09, LINTEL)
    m.add_box(0.50, 0.68, 0.52, 0.84, 0.08, 0.76, STONE)
    m.add_pediment(0.14, 0.86, 0.90, 0.78, 0.72, 0.96, GOLD_STONE)
    m.add_gable_roof(0.16, 0.84, 0.14, 0.78, 0.72, 0.90, TERRACOTTA, overhang=0.03)
    m.add_box(0.50, 0.98, 0.46, 0.18, 0.20, 0.18, GOLD_STONE)
    m.add_box(0.50, 1.10, 0.46, 0.22, 0.04, 0.22, LINTEL)
    m.add_box(0.50, 1.18, 0.46, 0.08, 0.12, 0.08, TERRACOTTA)
    m.add_box(0.50, 0.28, 0.78, 0.14, 0.28, 0.04, DARK_WOOD)
    return m


def build_farm() -> Mesh:
    m = Mesh("farm")
    m.add_box(0.42, 0.025, 0.50, 0.78, 0.05, 0.78, STONE)
    m.add_box(0.42, 0.22, 0.50, 0.68, 0.34, 0.66, PLASTER)
    m.add_box(0.42, 0.14, 0.84, 0.12, 0.22, 0.03, DARK_WOOD)
    m.add_gable_roof(0.08, 0.76, 0.12, 0.88, 0.39, 0.58, TERRACOTTA, overhang=0.03)
    m.add_box(1.42, 0.03, 0.50, 0.96, 0.06, 0.82, STONE)
    m.add_box(1.42, 0.28, 0.50, 0.88, 0.44, 0.74, WOOD)
    m.add_box(1.42, 0.22, 0.88, 0.32, 0.32, 0.04, DARK_WOOD)
    m.add_gable_roof(0.96, 1.90, 0.08, 0.92, 0.50, 0.72, ROOF_DARK, overhang=0.04)
    for x in (0.92, 1.18, 1.46, 1.72, 1.92):
        m.add_box(x, 0.10, 0.08, 0.04, 0.16, 0.04, WOOD)
        m.add_box(x, 0.10, 0.92, 0.04, 0.16, 0.04, WOOD)
    m.add_box(1.42, 0.16, 0.08, 1.00, 0.03, 0.03, WOOD)
    m.add_box(1.42, 0.16, 0.92, 1.00, 0.03, 0.03, WOOD)
    m.add_box(1.05, 0.07, 0.28, 0.30, 0.08, 0.14, LINTEL)
    m.add_box(0.22, 0.58, 0.28, 0.07, 0.14, 0.07, ROOF_DARK)
    return m


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, builder in (
        ("domus", build_domus),
        ("town_hall", build_town_hall),
        ("farm", build_farm),
    ):
        path = OUT_DIR / ("%s.glb" % name)
        write_glb(path, builder())
        print("wrote", path, "(%d bytes)" % path.stat().st_size)


if __name__ == "__main__":
    main()
