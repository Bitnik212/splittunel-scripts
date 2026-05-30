from __future__ import annotations

from pathlib import Path
from tempfile import NamedTemporaryFile


class LineFileRepository:

    @classmethod
    def read(cls, path: Path) -> list[str]:
        if not path.exists():
            return []
        return [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]

    @classmethod
    def write(cls, path: Path, lines: list[str]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as tmp:
            for line in lines:
                tmp.write(line)
                tmp.write("\n")
            tmp_path = Path(tmp.name)
        tmp_path.replace(path)
